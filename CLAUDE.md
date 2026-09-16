# airdrop-keep

macOS tool that organizes AirDrop-received files into browsable, timestamped **batches** in
`~/AirDrop Keep/`, so you can go back to a transfer instead of re-sending it to relocate a file.
See **README.md** for the full story + the Apple Feedback writeup.

## How it works (the one insight)
AirDrop-received files carry quarantine agent **`sharingd`** (vs `Safari`/`Chrome`/`Preview` for
other sources), and the quarantine string's **2nd field is the receive-epoch** — files from one
transfer share it. `airdrop-keep.sh` filters on `sharingd`, groups by that timestamp
(`AIRDROP_BATCH_GAP`, default 120s), and drops symlinks + a manifest per batch. **Non-destructive**
(originals stay in `~/Downloads`) and **idempotent** (state in `~/.airdrop-keep/seen.txt`).

## Files
- `airdrop-send.applescript` — the SEND side (added 2026-09-16): opens the AirDrop picker
  preloaded with the given paths, via `NSSharingService` `com.apple.share.AirDrop.send`.
  ⚠️⚠️ **Three changes each stop the picker appearing, and all three look like fixes.** Verified by
  screenshot both ways on macOS 26.5.1: (1) `setActivationPolicy:`/`activateIgnoringOtherApps:`,
  (2) compiling it into an `.app` — droplet OR stay-open applet; `on open` runs and
  `performWithItems:` returns, but nothing is drawn, and (3) a completion delegate.
  **Plain `osascript`, no activation, pumped `NSRunLoop`, no delegate — that exact shape.**
  ⚠️ The delegate one shipped and was the reported bug: `sharingService:didShareItems:` fires when
  the user **picks a recipient**, not when the file lands, so exiting there killed the process
  mid-handoff — picker opens, click closes it, nothing sent. There is no delegate now; it just
  outlives the transfer (900s) and the wrapper kills the previous helper by recorded PID.
  ⚠️ It pumps `NSRunLoop` rather than calling `delay`: the picker belongs to this process and dies
  with it, and `delay` does not reliably run the loop.
  ⚠️ AppleScript reserved words cost several compile cycles: `error` cannot be a handler label,
  `items` cannot be a formal parameter, `if X then A else B` needs block form. `osacompile -o
  /dev/null` stays in the installer so a non-compiling helper is never installed.
- `install-quick-action.sh` — builds + installs the Finder Quick Action to `~/Library/Services/`.
  Run it per machine. `--uninstall` removes it. Verifies the bundle after writing it and deletes a
  malformed one rather than leaving a menu item that silently does nothing.
- `airdrop-keep.sh` — the engine. `--open` (open newest batch), `--open-keep` (open the folder).
- `install.sh` — first pass + clickable launcher + optional sidebar pin (`mysides`).
- `enable-watcher.sh` / `disable-watcher.sh` — toggle the `launchd` WatchPaths agent on `~/Downloads`.
- `com.jak.airdrop-keep.plist` — the agent template (`__SCRIPT__/__DOWNLOADS__/__STATE__` filled at enable).

## Conventions
- Part of `~/claude-server` — see root map in `../CLAUDE.md`. Git → **PUBLIC** `jaklabs/airdrop-keep`
  (open-sourced 2026-08-28 as a dev-tip / Apple-Feedback proof-of-concept + FDE-portfolio piece).
  Keep it secret-free — it's public.
- Stdlib/bash only, no deps. Never moves or deletes user files — links only.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
