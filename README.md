# airdrop-keep

**Give AirDrop the receiving history Apple never did.**

AirDrop dumps everything you receive into `~/Downloads` with zero grouping and zero history. So when you want a file again later, you can't find it — and end up **re-sending it from your phone just to relocate it on your Mac.** That's the papercut this fixes.

macOS quietly tags every AirDrop-received file with the quarantine agent **`sharingd`**, and the quarantine record's 2nd field is the **exact receive-time** — so files from the *same* transfer share it. `airdrop-keep` reads that to reconstruct **batches** and builds a browsable index.

## What you get
```
~/AirDrop Keep/
├── 2026-08-11  2304/        ← one folder per AirDrop transfer, named by date+time
│   ├── 5199.JPG             ← links back to the originals (nothing is moved)
│   ├── 5200.JPG
│   └── manifest.txt         ← time, filenames, sizes
├── 2026-08-28  1422/
└── ⟵ Open AirDrop Keep.command
```
Pin `~/AirDrop Keep` to your Finder sidebar → **one click shows every AirDrop batch you've ever received**, newest sorted right in. No more re-sending to find things.

## Design guarantees
- **Non-destructive.** Originals stay in `~/Downloads`. Batch folders hold symlinks + a manifest. Delete `~/AirDrop Keep` anytime; your files are untouched.
- **Idempotent.** Re-running only indexes *new* arrivals (state in `~/.airdrop-keep/seen.txt`). That's what makes the background watcher cheap.
- **No dependencies.** Pure `bash` + built-in macOS tools. Runs offline.

## Install
```bash
./install.sh          # organizes existing AirDrop history + adds the clickable launcher
./enable-watcher.sh   # (optional) auto-organize every FUTURE AirDrop the moment it lands
./disable-watcher.sh  # turn the watcher back off
```
The watcher is a `launchd` **WatchPaths** agent on `~/Downloads` — fires only when the folder changes.

## Tunables (env vars)
- `AIRDROP_BATCH_GAP` — seconds between files that still count as one batch (default `120`).
- `AIRDROP_SRC` / `AIRDROP_KEEP` — override source (`~/Downloads`) and destination (`~/AirDrop Keep`).

---

## 📮 The dev tip → Apple Feedback
This tool is a workaround for a real gap. The underlying **feature request worth filing with Apple** (Feedback Assistant, or developer.apple.com/bug-report):

> **Title:** AirDrop should keep a browsable Received history, grouped by transfer
>
> **Area:** AirDrop / Finder / System
>
> **Description:** Received AirDrop files land in ~/Downloads with no grouping and no history, so relocating a previously-received file is painful — users routinely re-send the file from the source device just to find it again on the Mac. The OS already has the data to solve this: received files are tagged with the `sharingd` quarantine agent and a precise receive-timestamp, so items from a single transfer are trivially group-able. **Request:** a Finder "AirDrop Received" smart location (like Recents/AirDrop's send panel) that lists received files grouped into per-transfer batches with sender and timestamp — no third-party tooling required.
>
> **Steps to reproduce the pain:** Receive several AirDrop batches over a week → try to reopen a specific earlier batch → notice there is no grouped history; files are intermixed in Downloads by name, not by transfer.

Filing it with a clean, reproducible writeup (and a link to this tool as the proof-of-concept) is exactly the kind of thing that gets engineer attention. This repo is that proof-of-concept.
