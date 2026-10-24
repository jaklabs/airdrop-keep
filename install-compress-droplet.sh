#!/usr/bin/env bash
# install-compress-droplet.sh — a drag-and-drop "Compress to Zip" app.
#
# Drop files or folders on its icon (Dock, Desktop, Finder sidebar) and they are
# zipped next to the originals, exactly like the ⌃⌥⌘Z Quick Action: one item →
# "<name>.zip", several → "Archive.zip", nothing overwritten. Double-clicking it
# just explains how to use it.
#
# Self-contained: the tested compress-to-zip.zsh is copied INTO the app, so the
# app keeps working if this repo moves.
#
#   ./install-compress-droplet.sh              install to ~/Applications
#   ./install-compress-droplet.sh --uninstall  remove it
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${COMPRESS_APP_DIR:-$HOME/Applications}"
APP="$DEST/Compress to Zip.app"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$APP"; [ -e "$APP" ] && { echo "FAILED — $APP still present"; exit 1; }
    echo "Removed."; exit 0
fi
[ -f "$HERE/compress-to-zip.zsh" ] || { echo "FAILED — compress-to-zip.zsh missing"; exit 1; }

SRC="$(mktemp -d)/droplet.applescript"
cat > "$SRC" <<'AS'
on open droppedItems
	set script_ to POSIX path of (path to resource "compress-to-zip.zsh")
	set args to ""
	repeat with anItem in droppedItems
		set args to args & " " & quoted form of POSIX path of anItem
	end repeat
	try
		do shell script "/bin/zsh " & quoted form of script_ & args
	on error msg
		display alert "Compress to Zip" message msg as warning
	end try
end open

on run
	display dialog "Drag files or folders onto this icon to zip them." & return & return & "One item becomes <name>.zip; several become Archive.zip, next to the originals." buttons {"OK"} default button 1 with title "Compress to Zip"
end run
AS

mkdir -p "$DEST" || exit 1
rm -rf "$APP"
/usr/bin/osacompile -o "$APP" "$SRC" || { echo "FAILED — osacompile"; exit 1; }
cp "$HERE/compress-to-zip.zsh" "$APP/Contents/Resources/compress-to-zip.zsh"
# Use the system's zip icon so it looks like what it does.
ICON=/System/Library/CoreServices/Applications/Archive\ Utility.app/Contents/Resources/ArchiveUtility.icns
[ -f "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/droplet.icns"
/usr/bin/plutil -replace CFBundleIdentifier -string com.jak.airdrop-keep.compress-droplet "$APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null

# verify, rather than announce
[ -f "$APP/Contents/Resources/compress-to-zip.zsh" ] && plutil -lint "$APP/Contents/Info.plist" >/dev/null \
  || { echo "FAILED — app incomplete"; rm -rf "$APP"; exit 1; }
touch "$APP"
echo "Installed: $APP"
echo "  Drag it into your Dock (or onto the Desktop), then drop files on it."
