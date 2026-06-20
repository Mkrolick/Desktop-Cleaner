# Desktop Cleaner

One double-click tidies your macOS Desktop: every loose file and folder is
**moved** into `~/Documents/Desktop/`, sorted into type-based subfolders. Then it
prints (and logs) a summary.

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

```sh
./install.sh
```

This puts **`Clean Desktop.command`** on your Desktop. Double-click it anytime.

- First run only: macOS may ask Terminal for permission to access your
  Desktop/Documents folders — click **OK**.
- The launcher just points at `bin/clean-desktop.sh` in this repo, so edits here
  take effect immediately. If you *move this repo*, re-run `./install.sh`.

## What goes where

Inside `~/Documents/Desktop/`:

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
- **No self-move** — the launcher and all hidden files are left alone.
- **Honest reporting** — counts come from the filesystem; a Claude error aborts
  with nothing moved instead of faking a success.
- **Audit trail** — every run appends to `~/Documents/Desktop/.cleanup-log.txt`.
- **Graceful no-op** — an already-clean Desktop just says so (Claude isn't even
  called).

## macOS permissions (first run)

`~/Desktop` and `~/Documents` are protected. macOS usually prompts Terminal for
access on the first run — click **OK**. If it doesn't prompt and the tool reports
it's blocked, grant access manually in **System Settings ▸ Privacy & Security ▸
Files & Folders** (or **Full Disk Access**) and enable **Terminal**.

If the Terminal window closes before you can read the summary, set **Terminal ▸
Settings ▸ Profiles ▸ Shell ▸ "When the shell exits"** to **"Don't close the
window."** (The summary is also saved to the log and shown as a notification.)

## Customizing

Edit `prompt/sort-prompt.md` to add, rename, or re-route buckets — it's plain
English. No need to reinstall.

## Uninstall

Delete `Clean Desktop.command` from your Desktop. (Your sorted files in
`~/Documents/Desktop/` stay put.)

## How it works

```
Clean Desktop.command  (Desktop launcher, double-clickable)
        └─ exec ─▶ bin/clean-desktop.sh   (orchestrator)
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
