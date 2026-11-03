# Desktop Cleaner

One double-click tidies your macOS Desktop: every loose file and folder is
**moved** into `~/Documents/Filed/`, sorted into type-based subfolders. It
runs silently in the background — no Terminal window opens — and posts a macOS
notification (plus a log entry) when it's done.

**Claude does the thinking; the script does the moving.** Claude Code runs
headless with **no file tools at all** — it only reads a list of item *names* and
replies with a bucket for each. The shell script (`bin/clean-desktop.sh`) then
performs every filesystem operation itself. That separation is what makes the
safety promises real instead of model-dependent:

- **Never deletes** — the script never calls `rm`.
- **Never overwrites** — the script computes a guaranteed-free name before each
  move (`report.pdf` → `report 2.pdf`) and moves with `mv -n`.
- **Can't fake success** — "moved" is verified against the filesystem, not
  Claude's exit code, so an error (e.g. not logged in) aborts with nothing moved
  rather than silently reporting success.

## Install

One line, no clone needed:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mkrolick/Desktop-Cleaner/main/bootstrap.sh)"
```

This clones the repo into `~/.desktop-cleaner` (re-running it updates the
clone) and runs the installer. Leave that folder where it is — the app runs
the cleaner from it.

Or, from your own clone of this repo:

```sh
./install.sh
```

**Prerequisites:** macOS, plus [Claude Code](https://claude.com/claude-code)
installed and logged in (it classifies the files; the shell script does all
the moving).

The app's launcher is a small compiled binary — it can't be a shell script,
because macOS grants folder access to the binary a process is running, and a
`#!/bin/bash` executable identifies itself as `/bin/bash`, which macOS refuses
to prompt for. `install.sh` downloads that binary (checksum verified) from the
[latest release](https://github.com/Mkrolick/Desktop-Cleaner/releases/latest),
so no developer tools are needed. If it can't be fetched — offline, or a fork
with no release — it's compiled from `src/launcher.c` instead, which needs the
Xcode Command Line Tools (`xcode-select --install`). Force the source build
with `DESKTOP_CLEANER_BUILD_FROM_SOURCE=1 ./install.sh`.

Either way this puts **`Clean Desktop.app`** on your Desktop. Double-click it
anytime — no window opens; it runs in the background and notifies you when
it's finished.

- First run only: macOS may ask "Clean Desktop" for permission to access your
  Desktop/Documents folders — click **OK**.
- The app just points at `bin/clean-desktop.sh` in this repo, so edits here
  take effect immediately. If you *move this repo*, re-run `./install.sh`.
  - Exception: if this repo lives inside a macOS-protected folder
    (`~/Desktop`, `~/Documents`, or `~/Downloads`), a Finder-launched app
    isn't allowed to execute a script out of it. In that case `install.sh`
    copies the runtime to `~/Library/Application Support/Desktop Cleaner/` and
    the app runs that copy — so re-run `./install.sh` after editing. (Cloning
    outside those folders — e.g. `~/.desktop-cleaner` — avoids the copy and
    keeps edit-in-place.)
- Upgrading from an older version? `install.sh` automatically removes the old
  Terminal-based `Clean Desktop.command` launcher.
- Older versions filed into `~/Documents/Desktop/`; it's now
  `~/Documents/Filed/`. The app's launcher has that folder compiled in, so
  re-install to switch it over. Launchers from release v2.1.0 and earlier
  still use the old folder; if that is still the latest release, build the
  launcher yourself with `DESKTOP_CLEANER_BUILD_FROM_SOURCE=1 ./install.sh`.
  To keep your earlier files in the same place, move the old folder once
  (only when `~/Documents/Filed/` doesn't exist yet):
  `mv ~/Documents/Desktop ~/Documents/Filed`.

## Finder integration

`install.sh` also installs a **Quick Action**
(`~/Library/Services/Clean Desktop.workflow`), so you can clean up straight
from Finder without touching the app icon:

- **Right-click any file or folder on the Desktop** (or any Finder item) →
  **Quick Actions ▸ Clean Desktop**. What you clicked doesn't matter — the
  selection is ignored and the whole Desktop is cleaned as usual.
- The same entry lives under **Finder ▸ Services ▸ Clean Desktop** in the menu
  bar, which works even with nothing selected.
- Want a hotkey? System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services ▸
  General ▸ Clean Desktop.

Note: right-clicking the empty Desktop *background* won't show Quick Actions —
macOS only offers them for a clicked item. (If the Desktop is empty, there's
nothing to clean anyway.) The Quick Action just launches `Clean Desktop.app`
in the background, so it uses the same permissions and logs as double-clicking
the app. If the menu item doesn't appear right away, log out and back in — the
services registry can lag.

## What goes where

Inside `~/Documents/Filed/`:

| Bucket | Contents |
|--------|----------|
| `Screenshots/` | macOS screenshots (`Screenshot…`, `Screen Shot…`) |
| `Images/` | jpg, png, gif, heic, webp, svg, … |
| `PDFs/` | pdf |
| `Documents/` | doc, docx, txt, rtf, pages, md, … |
| `Spreadsheets/` | xls, xlsx, csv, numbers, … |
| `Presentations/` | ppt, pptx, key |
| `Archives/` | zip, tar, gz, rar, 7z, … |
| `Installers/` | dmg, pkg, `.app` bundles |
| `Audio/` / `Video/` | media files |
| `Code/` | py, js, ts, html, json, sh, … |
| `Folders/` | other directories |
| `Misc/` | anything unrecognized |

## Safety

- **Move-only** — the script never calls `rm`; nothing can be deleted.
- **No overwrites** — collisions become `report 2.pdf`, `report 3.pdf`, … for
  files *and* folders (it never merges or nests onto an existing item).
- **No self-move** — the app and all hidden files are left alone.
- **Honest reporting** — counts come from the filesystem; a Claude error aborts
  with nothing moved instead of faking a success.
- **Audit trail** — every run appends to `~/Documents/Filed/.cleanup-log.txt`,
  and the full output of the latest run is saved to
  `~/Documents/Filed/.last-run.txt`.
- **Graceful no-op** — an already-clean Desktop just says so (Claude isn't even
  called).

## macOS permissions (first run)

`~/Desktop` and `~/Documents` are protected. macOS usually prompts **"Clean
Desktop"** for access on the first run — click **OK**. If it doesn't prompt and
the notification says it's blocked, grant access manually in **System Settings ▸
Privacy & Security ▸ Files & Folders** (or **Full Disk Access**) and enable
**Clean Desktop**.

## Customizing

Edit `prompt/sort-prompt.md` to add, rename, or re-route buckets — it's plain
English. No need to reinstall.

## Uninstall

Delete `Clean Desktop.app` from your Desktop and
`~/Library/Services/Clean Desktop.workflow`. (Your sorted files in
`~/Documents/Filed/` stay put.)

## How it works

```
Clean Desktop.app  (Desktop launcher, double-clickable, no window)
        └─ exec ─▶ bin/clean-desktop.sh   (orchestrator, output → .last-run.txt)
                        ├─ preflight: find claude, check access, ensure dest
                        ├─ enumerate movable items (skip launcher + hidden)
                        ├─ no-op if Desktop already clean
                        ├─ claude -p  (NO tools) ── classify each name → bucket
                        │      using prompt/sort-prompt.md
                        └─ for each item: compute a free name, `mv -n` it,
                               verify it moved, tally, log, summarize
```

Claude never touches the filesystem — it only maps names to bucket labels. All
moving, collision-handling, counting, and success-checking happen in the shell.
