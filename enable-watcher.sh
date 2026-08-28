#!/usr/bin/env bash
# Enable the LaunchAgent that indexes new AirDrops the moment ~/Downloads changes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.airdrop-keep"; mkdir -p "$STATE"
DEST="$HOME/Library/LaunchAgents/com.jak.airdrop-keep.plist"

sed -e "s|__SCRIPT__|$HERE/airdrop-keep.sh|" \
    -e "s|__DOWNLOADS__|${AIRDROP_SRC:-$HOME/Downloads}|" \
    -e "s|__STATE__|$STATE|g" \
    "$HERE/com.jak.airdrop-keep.plist" > "$DEST"

launchctl unload "$DEST" 2>/dev/null || true
launchctl load "$DEST"
echo "✓ Watcher enabled — every AirDrop from now on is auto-organized into ~/AirDrop Keep."
echo "  Log: $STATE/airdrop-keep.log   ·   Disable: ./disable-watcher.sh"
