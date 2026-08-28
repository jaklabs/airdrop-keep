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
- `airdrop-keep.sh` — the engine. `--open` (open newest batch), `--open-keep` (open the folder).
- `install.sh` — first pass + clickable launcher + optional sidebar pin (`mysides`).
- `enable-watcher.sh` / `disable-watcher.sh` — toggle the `launchd` WatchPaths agent on `~/Downloads`.
- `com.jak.airdrop-keep.plist` — the agent template (`__SCRIPT__/__DOWNLOADS__/__STATE__` filled at enable).

## Conventions
- Part of `~/claude-server` — see root map in `../CLAUDE.md`. Git → private `jaklabs/airdrop-keep`
  (candidate to go **public** as a dev-tip / Apple-Feedback proof-of-concept).
- Stdlib/bash only, no deps. Never moves or deletes user files — links only.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
