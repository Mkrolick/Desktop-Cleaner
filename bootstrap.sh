#!/bin/bash
#
# Desktop Cleaner — one-line bootstrap installer
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mkrolick/Desktop-Cleaner/main/bootstrap.sh)"
#
# Clones the repo into ~/.desktop-cleaner (or updates an existing clone) and
# runs install.sh, which puts "Clean Desktop.app" on your Desktop and a
# "Clean Desktop" Quick Action in Finder. The clone must stay put afterwards —
# the app runs the cleaner from it. ~/.desktop-cleaner is deliberately outside
# ~/Documents so reading the repo never needs a macOS Documents permission.
#
# Overrides (mostly for testing):
#   DESKTOP_CLEANER_REPO    git URL/path to clone   (default: the GitHub repo)
#   DESKTOP_CLEANER_BRANCH  branch to install       (default: main)
#   DESKTOP_CLEANER_HOME    where to clone          (default: ~/.desktop-cleaner)

set -u

REPO_URL="${DESKTOP_CLEANER_REPO:-https://github.com/Mkrolick/Desktop-Cleaner.git}"
BRANCH="${DESKTOP_CLEANER_BRANCH:-main}"
CLONE_DIR="${DESKTOP_CLEANER_HOME:-$HOME/.desktop-cleaner}"

die() { echo "❌ $1"; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Desktop Cleaner is macOS-only."
command -v git >/dev/null 2>&1 || \
  die "git is required — install the Xcode Command Line Tools: xcode-select --install"

if ! command -v claude >/dev/null 2>&1; then
  echo "⚠️  Claude Code ('claude') was not found on your PATH. Desktop Cleaner"
  echo "   uses it to classify files — install it from https://claude.com/claude-code"
  echo "   and log in before your first cleanup. (Installing the launcher anyway.)"
  echo
fi

if [ -d "$CLONE_DIR/.git" ]; then
  echo "↻ Updating existing copy in ${CLONE_DIR}…"
  git -C "$CLONE_DIR" pull --ff-only || \
    die "Could not update $CLONE_DIR — fix it (or delete it) and re-run."
elif [ -e "$CLONE_DIR" ] || [ -L "$CLONE_DIR" ]; then
  die "$CLONE_DIR exists but is not a git clone — move it aside and re-run."
else
  echo "⬇️  Cloning into ${CLONE_DIR}…"
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$CLONE_DIR" || die "Clone failed."
fi

cd "$CLONE_DIR" || die "Cannot enter $CLONE_DIR."
exec ./install.sh
