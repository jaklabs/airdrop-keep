#!/usr/bin/env bash
# install.sh — set up airdrop-keep: build the clickable launcher, index existing batches,
# and (optionally) enable the background watcher that captures every future AirDrop.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KEEP="${AIRDROP_KEEP:-$HOME/AirDrop Keep}"
STATE="$HOME/.airdrop-keep"
mkdir -p "$KEEP" "$STATE"

# 1. First pass — organize whatever AirDrop history is already in Downloads.
"$HERE/airdrop-keep.sh"

# 2. A double-clickable launcher that opens the Keep folder in Finder.
CMD="$KEEP/⟵ Open AirDrop Keep.command"
cat > "$CMD" <<EOF
#!/bin/bash
"$HERE/airdrop-keep.sh" --open-keep
EOF
chmod +x "$CMD"

# 3. Pin ~/AirDrop Keep to the Finder sidebar if 'mysides' is available (brew install mysides).
if command -v mysides >/dev/null 2>&1; then
  mysides add "AirDrop Keep" "file://$KEEP/" 2>/dev/null && echo "✓ pinned to Finder sidebar"
else
  echo "• (optional) 'brew install mysides' then re-run to auto-pin the sidebar item."
  echo "  Or drag the ~/AirDrop Keep folder into Finder's sidebar once, manually."
fi

echo
echo "✓ Installed. Your AirDrop history is organized in: $KEEP"
echo
echo "To capture EVERY future AirDrop automatically, enable the background watcher:"
echo "    ./enable-watcher.sh      (turn on)"
echo "    ./disable-watcher.sh     (turn off)"
