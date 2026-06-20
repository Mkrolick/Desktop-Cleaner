# Desktop Cleaner — Design

**Date:** 2026-06-20
**Status:** Approved (design), pending implementation

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

**Claude-driven, move-only (Approach A).** A thin launcher runs a shell
orchestrator, which invokes Claude headless (`claude -p`) with a locked-down
tool allowlist. Claude performs the categorization and `mv` commands and writes
the summary. The allowlist is the core safety mechanism.

Rejected: pure-shell (no Claude, no judgment) and hybrid (more moving parts).

## Components

All live in this repo (version-controlled):

| File | Responsibility |
|------|----------------|
| `bin/clean-desktop.sh` | Orchestrator. Sets `PATH`, defines source/dest, builds the exclusion list, invokes Claude, handles the no-op case, keeps the Terminal window open until a keypress. |
| `prompt/sort-prompt.md` | The instruction prompt for Claude: category map, rules, collision handling, summary format. |
| `install.sh` | Writes `Clean Desktop.command` to the Desktop (thin wrapper → `bin/clean-desktop.sh`), `chmod +x`, clears the quarantine xattr. |
| `README.md` | How it works, install steps, safety notes, macOS permission heads-up. |

The Desktop launcher `Clean Desktop.command` is a thin wrapper so all logic
stays in the repo and updates take effect without reinstalling.

## Data flow

1. User double-clicks `Clean Desktop.command` → Terminal opens, runs the wrapper.
2. Wrapper `exec`s `bin/clean-desktop.sh`.
3. Orchestrator ensures `~/Documents/Desktop/` exists, computes the set of
   movable items (everything in `~/Desktop` **except** hidden files and the
   launcher itself), and exits early with "Desktop already clean ✨" if empty.
4. Orchestrator invokes `claude -p "$(cat prompt/sort-prompt.md)"` with
   `--allowedTools` limited to `Bash(mkdir:*)`, `Bash(mv:*)`, `Bash(ls:*)`,
   `Bash(find:*)`, `Bash(file:*)`, and `Read`.
5. Claude creates the needed bucket folders, moves each item, appends to the log,
   and prints a per-category summary.
6. Orchestrator keeps the window open (`read -n 1`) so the summary is visible.

## Category buckets (inside `~/Documents/Desktop/`)

`Screenshots/`, `Images/`, `PDFs/`, `Documents/`, `Spreadsheets/`,
`Presentations/`, `Archives/`, `Installers/`, `Audio/`, `Video/`, `Code/`,
`Folders/` (for existing directories), `Misc/` (anything unrecognized).

Screenshots are detected by macOS naming (`Screenshot*` / `Screen Shot*`) and
routed to `Screenshots/` rather than `Images/`.

## Safety properties

- **Move-only:** no `rm` in the allowlist; nothing can be deleted.
- **No overwrite:** collisions get a `-1`, `-2`, … suffix (`mv -n` + rename).
- **No self-move:** the launcher and all hidden files are excluded from the set.
- **Scoped:** Claude operates only within `~/Desktop` and `~/Documents/Desktop`.
- **Audit trail:** each run appends what-moved-where to
  `~/Documents/Desktop/.cleanup-log.txt`.
- **Graceful no-op:** empty Desktop → friendly message, no Claude call.

## macOS notes

- The launcher is created locally, so it is not Gatekeeper-quarantined; the
  install step also clears any quarantine xattr defensively.
- First run may surface a one-time OS permission prompt for Terminal to access
  the Desktop/Documents folders (TCC). User approves once.
- `claude` is available via the user's shell as a function wrapping the real
  binary; the orchestrator calls the binary on `PATH` and sets `PATH` to include
  common npm/global bin locations so it works outside an interactive shell.

## Testing

- Seed a scratch Desktop-like directory with representative files (image, pdf,
  screenshot-named png, zip, dmg, code file, a folder, an unknown extension) and
  verify each lands in the right bucket, collisions get suffixed, hidden files
  and the launcher are untouched, and the log is written.
- Verify the no-op path (empty source) exits cleanly without calling Claude.

## Out of scope (possible future opt-ins)

- Actually deleting throwaway types (e.g. old `.dmg`) instead of archiving.
- Pre-move confirmation / dry-run mode.
- Topic-based sorting (reading file contents to group by project).
