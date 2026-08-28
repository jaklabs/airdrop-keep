#!/usr/bin/env bash
# Turn off the background watcher (indexing still works when you run airdrop-keep.sh by hand).
set -euo pipefail
DEST="$HOME/Library/LaunchAgents/com.jak.airdrop-keep.plist"
launchctl unload "$DEST" 2>/dev/null || true
rm -f "$DEST"
echo "✓ Watcher disabled."
