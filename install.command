#!/usr/bin/env bash
# Double-clickable installer for the AirDrop Quick Action.
#
# Downloading the repo as a ZIP and double-clicking this is the whole install —
# no git, no Terminal. It fetches nothing itself; everything it needs is in the
# folder next to it.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
echo "Installing the AirDrop Quick Action..."
echo
if ! command -v /usr/bin/swiftc >/dev/null 2>&1; then
  echo "The Xcode command line tools are needed to build the sender."
  echo "Running: xcode-select --install"
  echo "Let that finish, then double-click this file again."
  xcode-select --install 2>/dev/null
  read -r -p "Press return to close."
  exit 1
fi
./install-quick-action.sh
echo
echo "Done. Right-click a file in Finder → Quick Actions → AirDrop."
echo
echo "The FIRST send from Desktop, Documents or Downloads shows a one-time"
echo "macOS permission prompt — allow it, or nothing will send."
echo "⚠️  On a multi-display Mac that prompt can appear on your OTHER screen."
echo
read -r -p "Press return to close."
