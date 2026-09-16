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
- `airdrop-send.js` — the SEND side (added 2026-09-16): opens the AirDrop picker preloaded with the
  given paths, via `NSSharingService` `NSSharingServiceNameSendViaAirDrop`. Run with
  `osascript -l JavaScript`.
  ⚠️ **It is JavaScript because AppleScript is structurally blind to failures here.** The service
  reports why a send failed through `sharingService:didFailToShareItems:error:`, and AppleScript
  cannot implement that selector at all — `error` is a reserved word and may not be a handler label.
  The first two versions were AppleScript, and both times a broken send produced *no* diagnostic and
  an hour of guessing. JXA registers a real delegate subclass and writes the domain/code/message to
  `~/Library/Caches/airdrop-send.log`. **Read that log before theorising.**
  ⚠️⚠️ **Two changes each stop the picker being drawn, and both look like fixes.** Verified by
  screenshot both ways on macOS 26.5.1: (1) `setActivationPolicy:`/`activateIgnoringOtherApps:`, and
  (2) compiling the helper into an `.app` — droplet OR stay-open applet; `on open` runs and
  `performWithItems:` returns, but nothing appears. Plain `osascript`, no activation, pumped
  `NSRunLoop`.
  ⚠️ No early exit on `didShareItems:` — that callback fires when the recipient is **picked**, not
  when the file lands, and quitting there kills the process mid-handoff.
  ⚠️ The delegate is held weakly by the service; keep the strong reference or callbacks stop
  arriving silently.
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
