#!/usr/bin/env bash
# airdrop-keep — organize AirDrop-received files into browsable, timestamped batches.
#
# AirDrop drops everything into ~/Downloads with no history, so relocating a file later
# means re-sending it. macOS tags AirDrop files with quarantine agent `sharingd`, and the
# quarantine string's 2nd field is the exact receive-time — files from the same transfer
# share it. We use that to reconstruct "batches" and build a browsable index.
#
# NON-DESTRUCTIVE: originals stay in ~/Downloads. Each batch folder holds symlinks back to
# them plus a manifest.txt. Idempotent — safe to run repeatedly (that's how the watcher works).
#
# Usage:
#   ./airdrop-keep.sh              # scan + index any new AirDrop batches
#   ./airdrop-keep.sh --open       # ...then open the most recent batch in Finder
#   ./airdrop-keep.sh --open-keep  # just open ~/AirDrop Keep in Finder
#
# Env overrides: AIRDROP_SRC (default ~/Downloads), AIRDROP_KEEP (default ~/AirDrop Keep),
#   AIRDROP_BATCH_GAP (seconds between files to still count as one batch, default 120).
set -euo pipefail

SRC="${AIRDROP_SRC:-$HOME/Downloads}"
KEEP="${AIRDROP_KEEP:-$HOME/AirDrop Keep}"
GAP="${AIRDROP_BATCH_GAP:-120}"
STATE="$HOME/.airdrop-keep"; SEEN="$STATE/seen.txt"
mkdir -p "$KEEP" "$STATE"; touch "$SEEN"

open_keep() { open "$KEEP"; }
[ "${1:-}" = "--open-keep" ] && { open_keep; exit 0; }

# --- 1. Collect AirDrop files as "epoch<TAB>path", sorted by receive-time ---
rows="$(mktemp)"; trap 'rm -f "$rows"' EXIT
while IFS= read -r -d '' f; do
  q="$(xattr -p com.apple.quarantine "$f" 2>/dev/null)" || continue
  case "$q" in *';sharingd;'*) : ;; *) continue ;; esac      # AirDrop only
  hexts="$(printf '%s' "$q" | awk -F';' '{print $2}')"
  [ -n "$hexts" ] || continue
  ts=$((16#$hexts))
  printf '%s\t%s\n' "$ts" "$f"
done < <(find "$SRC" -maxdepth 1 -type f -print0) | sort -n > "$rows"

# --- 2. Walk in time order; break into batches on a gap > $GAP; index new files ---
prev_ts=0; batch_ts=0; batch_dir=""; new_files=0; latest_dir=""
while IFS=$'\t' read -r ts path; do
  [ -n "${ts:-}" ] || continue
  if [ "$batch_ts" -eq 0 ] || [ $((ts - prev_ts)) -gt "$GAP" ]; then
    batch_ts="$ts"                                            # start a new batch
    label="$(date -r "$batch_ts" '+%Y-%m-%d  %H%M')"
    batch_dir="$KEEP/$label"
    # de-collide if two batches land in the same minute
    [ -e "$batch_dir" ] && [ "$batch_dir" != "$latest_dir" ] && batch_dir="$KEEP/$label-$(date -r "$batch_ts" '+%S')"
  fi
  prev_ts="$ts"; latest_dir="$batch_dir"

  id="$path"                                                  # stable per-file key
  grep -qxF "$id" "$SEEN" && continue                         # already indexed

  mkdir -p "$batch_dir"
  base="$(basename "$path")"; link="$batch_dir/$base"
  n=1; while [ -e "$link" ]; do link="$batch_dir/${base%.*} ($n).${base##*.}"; n=$((n+1)); done
  ln -s "$path" "$link"

  if [ ! -f "$batch_dir/manifest.txt" ]; then
    { echo "AirDrop batch — $(date -r "$batch_ts" '+%A, %B %-d %Y at %-I:%M %p')"
      echo "Originals live in: $SRC"
      echo "---"; } > "$batch_dir/manifest.txt"
  fi
  sz="$(du -h "$path" 2>/dev/null | cut -f1 | tr -d ' ')"
  printf '%s   %s   (%s)\n' "$(date -r "$ts" '+%H:%M:%S')" "$base" "${sz:-?}" >> "$batch_dir/manifest.txt"
  echo "$id" >> "$SEEN"
  new_files=$((new_files+1))
done < "$rows"

echo "airdrop-keep: indexed $new_files new file(s) into \"$KEEP\""
if [ "${1:-}" = "--open" ] && [ -n "$latest_dir" ]; then open "$latest_dir"; fi
