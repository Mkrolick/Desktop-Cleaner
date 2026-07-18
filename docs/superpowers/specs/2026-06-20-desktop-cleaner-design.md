# Desktop Cleaner — Design

**Date:** 2026-06-20
**Status:** Implemented and tested

> **Revision (2026-07-18, v2 — background app).** The Terminal-based
> `Clean Desktop.command` launcher described below was replaced by a generated
> **`Clean Desktop.app`** bundle: double-clicking runs `bin/clean-desktop.sh`
> headlessly — no Terminal window, no "Press any key to close" pause
> (`pause_and_exit` was removed). Output is captured to
> `~/Documents/Desktop/.last-run.txt`; every outcome, including preflight
> failures, is reported via macOS notification. TCC permission grants now attach
> to **Clean Desktop** (the app), not Terminal, so the permission guidance below
> is outdated. `install.sh` builds the bundle, replaces only marker-matched
> launchers it generated, removes the retired `.command`, and fails loudly on
> any build error. Sections below describe the v1 Terminal flow where they
> mention `.command`, Terminal windows, or `read -n 1`.

> **Revision (post-implementation safety review).** The original design had Claude
> run the `mv`/`mkdir` commands directly under a tool allowlist. An adversarial
> review found this unsafe: Claude Code's permission engine blocks any `mv` with a
> flag, so the `mv -n` no-overwrite guard was silently dropped (Claude fell back to
> flagless `mv`), and `claude -p` exits 0 even on auth errors, so a failed run
> looked like success. The architecture below is the corrected one: **Claude only
> classifies names → buckets (with no file tools); the shell performs every
> filesystem operation**, making move-only / no-overwrite / honest-reporting real
> guarantees rather than model-dependent ones.

## Goal

A single double-clickable icon on the macOS Desktop that, when clicked, moves
every loose item off the Desktop into `~/Documents/Desktop/`, sorted into
type-based subfolders by Claude Code, then prints a summary. Fully automatic —
no confirmation prompt.

## Behavior (decisions)

- **Trigger:** double-click `Clean Desktop.command` on the Desktop.
- **Action:** move (not copy) + smart-sort by **file type**.
- **Autonomy:** "just do it, show a summary" — no pre-confirmation.
- **Move, never delete:** files are relocated with `mv`, so they vanish from the
  Desktop but always remain recoverable under `~/Documents/Desktop/`. `rm` is
  intentionally excluded so the tool can never destroy data.

## Approach

**Claude classifies, the shell moves.** A thin launcher runs a shell
orchestrator. The orchestrator enumerates the Desktop, asks Claude headless
(`claude -p`, **no file tools**) to map each item *name* to a bucket label, then
does all the moving itself with deterministic, collision-safe `mv -n`. Claude
supplies judgment (screenshots vs images, unknown extensions, `.app` bundles);
the shell supplies the safety guarantees.

Rejected: Claude-runs-`mv` (unsafe — see Revision note), pure-shell (no judgment),
and hybrid (more moving parts).

## Components

All live in this repo (version-controlled):

| File | Responsibility |
|------|----------------|
| `bin/clean-desktop.sh` | Orchestrator. Locates `claude`, preflights (access probe, dest-not-inside-src), enumerates movable items into an array, builds a numbered manifest, calls Claude to classify, then moves each item with a free-name + `mv -n`, verifies, tallies, logs, notifies, and keeps the window open. |
| `prompt/sort-prompt.md` | Pure classification prompt: given numbered names, output `<index> <Bucket>` lines. No tools, injection-resistant. |
| `install.sh` | Writes `Clean Desktop.command` to the Desktop (thin wrapper → `bin/clean-desktop.sh`), `chmod +x`, clears the quarantine xattr, prints macOS permission guidance. |
| `README.md` | How it works, install steps, safety notes, macOS permission heads-up. |

The Desktop launcher `Clean Desktop.command` is a thin wrapper so all logic
stays in the repo and updates take effect without reinstalling.

## Data flow

1. User double-clicks `Clean Desktop.command` → Terminal opens, runs the wrapper.
2. Wrapper `exec`s `bin/clean-desktop.sh`.
3. Orchestrator preflights: locate `claude`, probe that `$SRC` is readable
   (distinguish a TCC denial from an empty Desktop), reject `$DEST` inside `$SRC`,
   ensure `$DEST` exists.
4. It enumerates movable items (the `$SRC/*` glob skips dotfiles; it also keeps
   broken symlinks via `-L` and excludes the launcher) into a bash array, so
   spaces/quotes/newlines in names never need escaping. Empty set → "Desktop
   already clean ✨" and exit (Claude is never called).
5. It builds a numbered manifest (`1. name [type: …]`) and pipes it to
   `claude -p` with **no tools**. Claude returns `<index> <bucket>` lines.
6. The orchestrator parses those lines (tolerating `1.`/`1)` and stray prose),
   defaults any unclassified item to `Misc`, and **aborts moving nothing** if
   zero valid classifications come back (the auth-error / not-logged-in case).
7. For each item it computes a guaranteed-free target name, runs `mv -n`, and
   verifies the source is gone and the target exists before counting it moved.
8. It prints a filesystem-derived summary, appends to the log, posts a macOS
   notification, and holds the window open (`read -n 1`).

## Category buckets (inside `~/Documents/Desktop/`)

`Screenshots/`, `Images/`, `PDFs/`, `Documents/`, `Spreadsheets/`,
`Presentations/`, `Archives/`, `Installers/`, `Audio/`, `Video/`, `Code/`,
`Folders/` (for existing directories), `Misc/` (anything unrecognized).

Screenshots are detected by macOS naming (`Screenshot*` / `Screen Shot*`) and
routed to `Screenshots/` rather than `Images/`.

## Safety properties

- **Move-only:** the shell never calls `rm`; nothing can be deleted. Claude has
  no file tools at all.
- **No overwrite:** the shell computes a free `name 2.ext`/`name 3.ext` before
  every move (for files *and* directories — no merge/nest) and uses `mv -n`.
- **No self-move:** the launcher and all hidden files are excluded from the set.
- **Honest reporting:** counts are read from the filesystem and each move is
  verified; a Claude error yields zero classifications → abort with nothing
  moved, not a false success.
- **Injection-resistant:** filenames are passed as data to a no-tool model that
  is told to ignore embedded instructions; even a steered model has no tools.
- **Audit trail:** each run appends a filesystem-derived summary to
  `~/Documents/Desktop/.cleanup-log.txt`.
- **Graceful no-op:** empty Desktop → friendly message, no Claude call.

## macOS notes

- The launcher is created locally, so it is not Gatekeeper-quarantined; the
  install step also clears any quarantine xattr defensively.
- `~/Desktop`/`~/Documents` are TCC-protected. macOS usually prompts Terminal on
  first run; if it silently denies instead, the orchestrator's read probe catches
  it and points the user at System Settings ▸ Privacy & Security ▸ Files & Folders.
- The orchestrator finds `claude` even outside an interactive shell: it prepends
  common bin dirs to `PATH` and falls back to a candidate list that includes
  native-installer, Homebrew, npm-global, and nvm/volta/fnm locations.
- A completion notification (`osascript`) is posted so the result is visible even
  if Terminal's "When the shell exits" preference closes the window.
- Targets bash 3.2 (the system `/bin/bash`): no associative arrays, `mapfile`, or
  bash-4 features; classification handoff uses indices + a here-string so the
  parse loop stays in the current shell.

## Testing (performed)

- **Adversarial sandbox:** files with spaces, an apostrophe, an embedded
  double-quote, a screenshot-named png, a no-extension file, an unknown
  extension, a `.app`-less folder, a broken symlink, and a prompt-injection
  filename — plus a pre-existing **file** collision and a pre-existing
  **directory** collision. Verified every item landed in the right bucket, both
  collisions produced `… 2` siblings (original contents intact, no overwrite, no
  nesting), the launcher and hidden file were untouched, and counts matched the
  filesystem.
- **Claude-failure path:** a stub classifier that prints an error and exits 0 →
  orchestrator aborts, moves nothing, exits non-zero.
- **No-op path:** Desktop with only a hidden file + the launcher → "already
  clean", Claude never invoked.

## Out of scope (possible future opt-ins)

- Actually deleting throwaway types (e.g. old `.dmg`) instead of archiving.
- Pre-move confirmation / dry-run mode.
- Topic-based sorting (reading file contents to group by project).
