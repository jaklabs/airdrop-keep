#!/usr/bin/env bash
# install-compress-app.sh — the Compress to Zip app.
#
# A window you drag files into (or click to choose them). It zips them, then
# Download saves the zip to ~/Downloads and shows it in Finder; Save As… picks
# another place. Dropping files on its Dock icon works too.
#
# Native AppKit, compiled here with swiftc (Xcode command line tools). The zip
# itself is made by compress-to-zip.zsh, copied into the app, so the app, the
# ⌃⌥⌘Z Quick Action and the tests all run the same code.
#
#   ./install-compress-app.sh              build + install to ~/Applications
#   ./install-compress-app.sh --dock       ...and add it to the Dock
#   ./install-compress-app.sh --uninstall  remove it
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${COMPRESS_APP_DIR:-$HOME/Applications}"
APP="$DEST/Compress to Zip.app"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$APP"; [ -e "$APP" ] && { echo "FAILED — $APP still present"; exit 1; }
    echo "Removed. (If it is in the Dock, drag it out.)"; exit 0
fi
command -v /usr/bin/swiftc >/dev/null || { echo "FAILED — swiftc not found: xcode-select --install"; exit 1; }

BUILD="$(mktemp -d)"
STAGE="$BUILD/Compress to Zip.app/Contents"
mkdir -p "$STAGE/MacOS" "$STAGE/Resources"
/usr/bin/swiftc -O -parse-as-library -o "$STAGE/MacOS/CompressToZip" \
    "$HERE/CompressCore.swift" "$HERE/CompressToZipApp.swift" 2>"$BUILD/swiftc.log" \
  || { echo "FAILED — could not compile:"; cat "$BUILD/swiftc.log"; exit 1; }
cp "$HERE/compress-to-zip.zsh" "$STAGE/Resources/compress-to-zip.zsh"
ICON="/System/Library/CoreServices/Applications/Archive Utility.app/Contents/Resources/ArchiveUtility.icns"
[ -f "$ICON" ] && cp "$ICON" "$STAGE/Resources/AppIcon.icns"
cat > "$STAGE/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>Compress to Zip</string>
	<key>CFBundleDisplayName</key><string>Compress to Zip</string>
	<key>CFBundleExecutable</key><string>CompressToZip</string>
	<key>CFBundleIdentifier</key><string>com.jak.airdrop-keep.compress-app</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2.0</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<!-- Lets files be dropped on the Dock icon. Rank None: it never becomes the
	     default app for opening anything. -->
	<key>CFBundleDocumentTypes</key>
	<array><dict>
		<key>CFBundleTypeName</key><string>Anything</string>
		<key>CFBundleTypeRole</key><string>Viewer</string>
		<key>LSHandlerRank</key><string>None</string>
		<key>LSItemContentTypes</key><array><string>public.item</string><string>public.folder</string></array>
	</dict></array>
</dict></plist>
PLIST
plutil -lint "$STAGE/Info.plist" >/dev/null || { echo "FAILED — Info.plist invalid"; exit 1; }
/usr/bin/codesign --force --deep --sign - "$BUILD/Compress to Zip.app" 2>/dev/null

# The packaged app must actually zip, before it replaces anything installed.
T="$(mktemp -d)"; echo check > "$T/check.txt"
OUT=$("$STAGE/MacOS/CompressToZip" --headless --download-dir "$T/out" "$T/check.txt" 2>&1)
[ -f "$OUT" ] && [ "$(/usr/bin/zipinfo -1 "$OUT" 2>/dev/null)" = "check.txt" ] \
  || { echo "FAILED — the built app could not make a zip: $OUT"; exit 1; }
rm -rf "$T"

mkdir -p "$DEST" && rm -rf "$APP" && mv "$BUILD/Compress to Zip.app" "$APP" || { echo "FAILED — install"; exit 1; }
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null
echo "Installed: $APP"

if [ "${1:-}" = "--dock" ]; then
    if defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "Compress%20to%20Zip.app"; then
        echo "Already in the Dock."
    else
        URL="file://$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$APP")/"
        defaults write com.apple.dock persistent-apps -array-add \
          "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$URL</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
        killall Dock
        echo "Added to the Dock."
    fi
fi
