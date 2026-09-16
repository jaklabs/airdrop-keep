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
- `AirDropSend.swift` — the SEND side (2026-09-16). Compiled by the installer into
  `AirDropSend.app` inside the Quick Action bundle. Opens the AirDrop picker for the given paths and
  stays alive until the transfer finishes. Logs to `~/Library/Caches/airdrop-send.log` — **read that
  before theorising.**
  ⚠️ **It has to be a compiled app, and the reason is not stylistic.** `NSSharingService`'s picker is
  a real AppKit window that needs a process running a genuine `NSApplication` event loop to receive
  the click. `osascript` pumps an `NSRunLoop` but never dispatches events, so the picker *draws* (the
  window server does that regardless) while **no mouse event ever reaches it**: clicking a recipient
  produced no delegate callback at all, the window went half-transparent instead of closing, and
  nothing was sent. Two AppleScript/JXA versions shipped with that bug. There is no script-shaped fix.
  ⚠️ **`error` is an AppleScript reserved word, so AppleScript cannot implement
  `sharingService:didFailToShareItems:error:`** — the one callback that says why a send failed. Any
  AppleScript version of this is structurally blind to its own failures, which is *why* it took three
  attempts to find the cause. If this is ever ported back to a script, it loses that callback again.
  ⚠️ TCC: launched through LaunchServices the app has no inherited file access, so macOS prompts once
  per protected folder (Desktop/Documents/Downloads) and `canPerform` reads **false** until allowed.
  That is correct behaviour, not a bug — but it means a first send from a new folder shows a prompt.
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
