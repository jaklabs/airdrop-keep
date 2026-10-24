#!/usr/bin/env bash
# install-compress-action.sh — compress files from a KEYBOARD SHORTCUT.
#
# Finder's Compress lives only in the right-click menu and cannot be given a
# reliable shortcut (its menu title changes: "Compress “x”", "Compress 3 Items").
# This installs a Quick Action, "Compress to Zip", that does the same job and is
# bound to ⌃⌥⌘Z (Control-Option-Command-Z, "Z for zip") in Finder.
#
#   select files in Finder → ⌃⌥⌘Z
#
# Same results as Finder's Compress: one item → "<name>.zip" next to it, several
# → "Archive.zip"; an existing zip is never overwritten ("Archive 2.zip"...).
# Uses /usr/bin/ditto, the tool Finder itself uses, so Mac metadata and
# permissions survive and nothing lands in a __MACOSX folder.
#
#   ./install-compress-action.sh              install (or update)
#   ./install-compress-action.sh --uninstall  remove it
set -uo pipefail

NAME="Compress to Zip"
SHORTCUT="@~^z"   # ⌘ ⌥ ⌃ Z in Cocoa key-equivalent notation
SERVICES="${COMPRESS_SERVICES_DIR:-$HOME/Library/Services}"
BUNDLE="$SERVICES/$NAME.workflow"
PBS_KEY="(null) - $NAME - runWorkflowAsService"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$BUNDLE"
    defaults delete pbs NSServicesStatus 2>/dev/null >/dev/null || true
    /System/Library/CoreServices/pbs -flush 2>/dev/null
    [ -e "$BUNDLE" ] && { echo "FAILED — $BUNDLE still present"; exit 1; }
    echo "Removed."; exit 0
fi

# The action itself. Kept as a standalone file too (compress-to-zip.zsh) so the
# tests run exactly the code Finder runs.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$(cat "$HERE/compress-to-zip.zsh")" || { echo "FAILED — compress-to-zip.zsh missing"; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents" || exit 1
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleIdentifier</key><string>com.jak.airdrop-keep.compress</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key><dict><key>default</key><string>$NAME</string></dict>
			<key>NSMessage</key><string>runWorkflowAsService</string>
			<key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
			<key>NSSendFileTypes</key><array><string>public.item</string></array>
		</dict>
	</array>
</dict>
</plist>
PLIST

CMD="$CMD" python3 - "$BUNDLE/Contents/document.wflow" <<'PY'
import os, plistlib, sys, uuid
action = {
    "action": {
        "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3", "AMApplication": ["Automator"],
        "AMParameterProperties": {"COMMAND_STRING": {}, "CheckedForUserDefaultShell": {}, "inputMethod": {}, "shell": {}, "source": {}},
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {"COMMAND_STRING": os.environ["CMD"], "CheckedForUserDefaultShell": True, "inputMethod": 1, "shell": "/bin/zsh", "source": ""},
        "BundleIdentifier": "com.apple.RunShellScript", "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False, "CanShowWhenRun": True, "Category": ["AMCategoryUtilities"],
        "Class Name": "RunShellScriptAction",
        "InputUUID": str(uuid.uuid4()).upper(), "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
        "OutputUUID": str(uuid.uuid4()).upper(), "UUID": str(uuid.uuid4()).upper(),
        "UnlocalizedApplications": ["Automator"], "arguments": {}, "isViewVisible": 1,
        "location": "309.000000:253.000000",
        "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
    },
    "isViewVisible": 1,
}
doc = {
    "AMApplicationBuild": "528", "AMApplicationVersion": "2.10", "AMDocumentVersion": "2",
    "actions": [action], "connectors": {},
    "workflowMetaData": {
        "serviceApplicationBundleID": "com.apple.finder",
        "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceProcessesInput": 0,
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
    },
}
with open(sys.argv[1], "wb") as f:
    plistlib.dump(doc, f)
PY

# Bind the shortcut (the same setting System Settings → Keyboard → Keyboard
# Shortcuts → Services writes).
if [ -z "${COMPRESS_SERVICES_DIR:-}" ]; then
    defaults write pbs NSServicesStatus -dict-add "\"$PBS_KEY\"" \
      "{ key_equivalent = \"$SHORTCUT\"; enabled_context_menu = 1; enabled_services_menu = 1; presentation_modes = { ContextMenu = 1; ServicesMenu = 1; }; }"
fi

# --- verify, rather than announce -------------------------------------------
fail=""
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || fail="$fail Info.plist"
plutil -lint "$BUNDLE/Contents/document.wflow" >/dev/null 2>&1 || fail="$fail document.wflow"
if [ -z "${COMPRESS_SERVICES_DIR:-}" ]; then
    defaults read pbs NSServicesStatus 2>/dev/null | grep -q "$NAME" || fail="$fail shortcut"
fi
if [ -n "$fail" ]; then echo "FAILED —$fail"; rm -rf "$BUNDLE"; exit 1; fi

/System/Library/CoreServices/pbs -flush 2>/dev/null
echo "Installed: $NAME"
echo "  Select files in Finder and press ⌃⌥⌘Z (Control-Option-Command-Z)."
echo "  Also in right-click → Quick Actions → $NAME."
echo "  If the shortcut does nothing yet, log out and back in once (macOS caches Services per login)."
