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
  ⚠️ Three AppleScript reserved words bite here and cost several compile cycles: `error` cannot be
  a handler label (so the cancel delegate is impossible), `items` cannot be a formal parameter, and
  `if X then A else B` needs block form. Keep `osacompile -o /dev/null` in the installer — it
  refuses to install an action that does not compile.
  ⚠️ It pumps `NSRunLoop` rather than calling `delay`: the AirDrop panel belongs to this process and
  dies with it, and delegate callbacks only fire while the loop runs.
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
