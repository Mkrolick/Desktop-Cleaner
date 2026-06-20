#!/bin/bash
#
# Desktop Cleaner — orchestrator
#
# Moves loose items off the Desktop into ~/Documents/Desktop, sorted by file
# type. Claude Code (headless, with NO file tools) only *classifies* each item
# into a bucket name; THIS SCRIPT performs every filesystem operation. That
# split is what makes the safety guarantees real rather than model-dependent:
#
#   • Never deletes  — this script never calls `rm`.
#   • Never overwrites — it computes a guaranteed-free target name and uses
#                        `mv -n`; a collision becomes "name 2.ext", "name 3.ext".
#   • Can't fake success — success is read from the filesystem (did the file
#                        actually move?), not from Claude's exit code, so an
#                        auth/network error aborts cleanly with nothing moved.
#
# Config (overridable, used for testing):
#   DESKTOP_CLEANER_SRC       source folder      (default: ~/Desktop)
#   DESKTOP_CLEANER_DEST      destination folder (default: ~/Documents/Desktop)
#   DESKTOP_CLEANER_LAUNCHER  launcher filename to never move

set -u

# --- locate self BEFORE any cd ----------------------------------------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SELF_DIR/.." && pwd)"
PROMPT_FILE="$REPO_DIR/prompt/sort-prompt.md"

# --- locate claude (a Finder-launched .command has a bare PATH, no rc) -------
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$PATH"
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
if [ -z "$CLAUDE_BIN" ]; then
  for c in \
    "$HOME/.local/bin/claude" \
    /opt/homebrew/bin/claude \
    /usr/local/bin/claude \
    "$HOME/.npm-global/bin/claude" \
    "$HOME"/.nvm/versions/node/*/bin/claude \
    "$HOME/.volta/bin/claude" \
    "$HOME"/.fnm/node-versions/*/installation/bin/claude \
    "$HOME/.bun/bin/claude"; do
    if [ -x "$c" ]; then CLAUDE_BIN="$c"; break; fi
  done
fi
# Test hook: let a harness substitute the classifier binary.
CLAUDE_BIN="${DESKTOP_CLEANER_CLAUDE:-$CLAUDE_BIN}"

# --- config -----------------------------------------------------------------
SRC="${DESKTOP_CLEANER_SRC:-$HOME/Desktop}"
DEST="${DESKTOP_CLEANER_DEST:-$HOME/Documents/Desktop}"
LAUNCHER_NAME="${DESKTOP_CLEANER_LAUNCHER:-Clean Desktop.command}"
LOG="$DEST/.cleanup-log.txt"

# The only bucket names Claude may choose; anything else is treated as Misc.
VALID_BUCKETS="Screenshots Images PDFs Documents Spreadsheets Presentations Archives Installers Audio Video Code Folders Misc"

notify() { # best-effort macOS notification (survives an auto-closed window)
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"Desktop Cleaner\"" >/dev/null 2>&1 || true
  fi
}

pause_and_exit() {
  echo
  printf 'Press any key to close…'
  read -n 1 -s -r _ 2>/dev/null || read -r _ 2>/dev/null || true
  echo
  exit "${1:-0}"
}

echo "🧹 Desktop Cleaner"
echo "   from: $SRC"
echo "   to:   $DEST"
echo

# --- preflight --------------------------------------------------------------
if [ ! -d "$SRC" ]; then
  echo "❌ Source folder not found: $SRC"
  pause_and_exit 1
fi
# Access probe — tell a genuine TCC denial apart from an empty Desktop.
if ! ls "$SRC" >/dev/null 2>&1; then
  echo "❌ macOS is blocking access to: $SRC"
  echo "   Grant access in System Settings ▸ Privacy & Security ▸ Files & Folders"
  echo "   (or Full Disk Access) for Terminal, then try again."
  pause_and_exit 1
fi
# Destination must not live inside the source, or we'd try to sort our own output.
case "$DEST/" in
  "$SRC/"*)
    echo "❌ Destination ($DEST) must not be inside the source ($SRC)."
    pause_and_exit 1 ;;
esac
if [ ! -f "$PROMPT_FILE" ]; then
  echo "❌ Missing prompt file: $PROMPT_FILE"
  pause_and_exit 1
fi
if [ -z "$CLAUDE_BIN" ]; then
  echo "❌ Could not find the 'claude' command."
  echo "   Run 'which claude' in Terminal; if it prints a path, symlink it into"
  echo "   ~/.local/bin and try again."
  pause_and_exit 1
fi
if ! mkdir -p "$DEST" 2>/dev/null; then
  echo "❌ Could not create destination: $DEST"
  pause_and_exit 1
fi

# --- enumerate movable items (array survives spaces/quotes/newlines) --------
names=()
for path in "$SRC"/*; do
  # Include real entries AND broken aliases/symlinks (-L); a plain glob already
  # skips dotfiles, so hidden files are left alone.
  if [ -e "$path" ] || [ -L "$path" ]; then :; else continue; fi
  base="$(basename "$path")"
  [ "$base" = "$LAUNCHER_NAME" ] && continue
  names+=("$base")
done

n=${#names[@]}
if [ "$n" -eq 0 ]; then
  echo "✨ Desktop is already clean — nothing to move."
  pause_and_exit 0
fi

echo "Found $n item(s). Asking Claude to classify them…"
echo

# --- build a numbered manifest (indices, not names, are the source of truth) -
manifest=""
i=0
while [ "$i" -lt "$n" ]; do
  idx=$((i + 1))
  raw="${names[$i]}"
  disp="$(printf '%s' "$raw" | tr '\n\t' '  ')"   # one line per item for display
  hint=""
  case "$raw" in
    *.*) : ;;  # has an extension; let Claude classify by it
    *)
      if [ -f "$SRC/$raw" ]; then
        hint="   [type: $(file -b "$SRC/$raw" 2>/dev/null | tr '\n\t' '  ')]"
      fi ;;
  esac
  if [ -d "$SRC/$raw" ] && [ ! -L "$SRC/$raw" ]; then
    case "$raw" in
      *.app) : ;;                      # app bundle -> Installers (by extension)
      *) hint="   [type: folder]" ;;
    esac
  fi
  manifest="$manifest$idx. $disp$hint
"
  i=$((i + 1))
done

# --- ask Claude to classify (NO tools: pure text in, text out) --------------
cd "$HOME" 2>/dev/null || true
FULL_PROMPT="$(cat "$PROMPT_FILE")

## Items to classify
Output one line per item: the number, a space, then exactly one bucket from:
$VALID_BUCKETS
Output ONLY those lines.

$manifest"

CLASS_OUT="$(printf '%s' "$FULL_PROMPT" | "$CLAUDE_BIN" -p 2>&1)"

# --- parse "<index> <bucket>" lines into a bucket per item ------------------
# Here-string (not a pipe) so the loop runs in this shell and the array sticks.
buckets=()
i=0
while [ "$i" -lt "$n" ]; do buckets+=(""); i=$((i + 1)); done

valid_count=0
while read -r num bkt _; do
  num="$(printf '%s' "$num" | tr -cd '0-9')"        # tolerate "1." / "1)"
  bkt="$(printf '%s' "$bkt" | tr -cd 'A-Za-z')"     # tolerate "Images." etc.
  [ -n "$num" ] || continue
  { [ "$num" -ge 1 ] && [ "$num" -le "$n" ]; } || continue
  ok=0
  for b in $VALID_BUCKETS; do [ "$b" = "$bkt" ] && ok=1 && break; done
  [ "$ok" -eq 1 ] || continue
  if [ -z "${buckets[$((num - 1))]}" ]; then
    buckets[$((num - 1))]="$bkt"
    valid_count=$((valid_count + 1))
  fi
done <<< "$CLASS_OUT"

if [ "$valid_count" -eq 0 ]; then
  echo "❌ Claude returned no usable classifications — nothing was moved."
  echo "   (Usually this means Claude isn't logged in or hit an error.)"
  echo "   Its output was:"
  echo "   ----"
  printf '%s\n' "$CLASS_OUT" | head -15 | sed 's/^/   /'
  echo "   ----"
  notify "Cleanup did NOT run — Claude error. Nothing moved."
  pause_and_exit 1
fi

# Anything Claude didn't classify is filed under Misc so nothing is left behind.
default_misc=0
i=0
while [ "$i" -lt "$n" ]; do
  if [ -z "${buckets[$i]}" ]; then
    buckets[$i]="Misc"
    default_misc=$((default_misc + 1))
  fi
  i=$((i + 1))
done

# --- move everything ourselves: free name + `mv -n`, verified per item ------
moved=0
failed=0
moved_buckets=""
i=0
while [ "$i" -lt "$n" ]; do
  base="${names[$i]}"
  bkt="${buckets[$i]}"
  src_path="$SRC/$base"
  tdir="$DEST/$bkt"
  mkdir -p "$tdir" 2>/dev/null

  # Compute a target name that does not already exist (no overwrite, no nesting).
  target="$tdir/$base"
  if [ -e "$target" ] || [ -L "$target" ]; then
    ext="${base##*.}"
    if [ "$ext" = "$base" ]; then stem="$base"; dot=""; else stem="${base%.*}"; dot=".$ext"; fi
    k=2
    while [ -e "$tdir/$stem $k$dot" ] || [ -L "$tdir/$stem $k$dot" ]; do k=$((k + 1)); done
    target="$tdir/$stem $k$dot"
  fi

  mv -n "$src_path" "$target" 2>/dev/null
  # Trust the filesystem, not mv's status: the source must be gone and the
  # target must now exist for this to count as moved.
  if { [ ! -e "$src_path" ] && [ ! -L "$src_path" ]; } && { [ -e "$target" ] || [ -L "$target" ]; }; then
    moved=$((moved + 1))
    moved_buckets="$moved_buckets $bkt"
  else
    failed=$((failed + 1))
  fi
  i=$((i + 1))
done

# --- report (numbers come from the filesystem, not from Claude) -------------
echo "✅ Moved $moved of $n item(s) into $DEST"
[ "$default_misc" -gt 0 ] && echo "   ($default_misc not auto-classified → Misc/)"
for b in $VALID_BUCKETS; do
  c=0
  for x in $moved_buckets; do [ "$x" = "$b" ] && c=$((c + 1)); done
  [ "$c" -gt 0 ] && printf '   • %-13s %d\n' "$b" "$c"
done
if [ "$failed" -gt 0 ]; then
  echo
  echo "⚠️  $failed item(s) could NOT be moved and remain on your Desktop."
  echo "   Nothing was deleted or overwritten."
fi

# --- audit log --------------------------------------------------------------
{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
  echo "Moved $moved of $n item(s) into $DEST"
  [ "$failed" -gt 0 ] && echo "  $failed could not be moved (left on Desktop)"
  echo
} >> "$LOG" 2>/dev/null || true

if [ "$failed" -gt 0 ] || [ "$moved" -eq 0 ]; then
  notify "Moved $moved item(s); $failed could not move."
  pause_and_exit 1
fi
notify "Cleaned up $moved item(s) into Documents/Desktop."
pause_and_exit 0
