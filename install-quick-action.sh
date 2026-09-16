#!/usr/bin/env bash
# install-quick-action.sh — add an "AirDrop" item to the Finder right-click menu.
#
# macOS already has right-click → Share → AirDrop. This puts AirDrop one level
# up, as a Quick Action, so it is one hop instead of two — and, more usefully, a
# Quick Action can be given a KEYBOARD SHORTCUT (System Settings → Keyboard →
# Keyboard Shortcuts → Services), which the built-in Share menu cannot.
#
# Works on any Mac: run it on each machine you want it on. Nothing is compiled
# and there are no dependencies — it builds an Automator .workflow bundle and
# drops it in ~/Library/Services/.
#
#   ./install-quick-action.sh              install (or reinstall/update)
#   ./install-quick-action.sh --uninstall  remove it
set -uo pipefail

NAME="AirDrop"
SERVICES="$HOME/Library/Services"
BUNDLE="$SERVICES/$NAME.workflow"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$HERE/airdrop-send.applescript"

if [ "${1:-}" = "--uninstall" ]; then
    rm -rf "$BUNDLE"
    /System/Library/CoreServices/pbs -flush 2>/dev/null
    if [ -e "$BUNDLE" ]; then echo "FAILED — $BUNDLE still present"; exit 1; fi
    echo "Removed. The AirDrop item will disappear from the menu within a few seconds."
    exit 0
fi

[ -f "$HELPER_SRC" ] || { echo "FAILED — helper not found next to this script: $HELPER_SRC"; exit 1; }

# Fail before installing rather than after: a Quick Action that silently does
# nothing is worse than one that was never added.
if ! /usr/bin/osascript -e 'use framework "AppKit"
return (current application'"'"'s NSSharingService'"'"'s sharingServiceNamed:"com.apple.share.AirDrop.send") is not missing value' 2>/dev/null | grep -q true; then
    echo "FAILED — this Mac does not offer the AirDrop sharing service."
    exit 1
fi
/usr/bin/osacompile -o /dev/null "$HELPER_SRC" 2>/dev/null || {
    echo "FAILED — $HELPER_SRC does not compile; not installing a broken action."; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/Resources" || exit 1
cp "$HELPER_SRC" "$BUNDLE/Contents/Resources/airdrop-send.applescript"

# NSSendFileTypes public.item = every file AND folder, so the item is present on
# anything you can right-click in Finder.
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleIdentifier</key><string>com.jak.airdrop-keep.quickaction</string>
	<key>CFBundleName</key><string>AirDrop</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key><dict><key>default</key><string>AirDrop</string></dict>
			<key>NSMessage</key><string>runWorkflowAsService</string>
			<key>NSRequiredContext</key><dict><key>NSApplicationIdentifier</key><string>com.apple.finder</string></dict>
			<key>NSSendFileTypes</key><array><string>public.item</string></array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# The shell script the action runs. Input arrives as arguments (inputMethod 1),
# so "$@" is the selected paths, already POSIX and space-safe.
#
# The pidfile exists because AppleScript cannot implement the cancel callback
# (see airdrop-send.applescript), so a cancelled share leaves the helper idling
# until its timeout. Matching on the command line with pkill is NOT safe here:
# this very shell's argv contains the string "airdrop-send.applescript", so it
# would kill itself before ever reaching osascript.
read -r -d '' CMD <<'SH'
HELPER="$HOME/Library/Services/AirDrop.workflow/Contents/Resources/airdrop-send.applescript"
PIDFILE="$HOME/Library/Caches/com.jak.airdrop-quickaction.pid"
[ $# -eq 0 ] && exit 0
# One picker at a time. Kill by RECORDED PID, not by pattern: this wrapper's own
# command line contains "airdrop-send.applescript", so `pkill -f` on that would
# kill the wrapper before it ever reached osascript.
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
/usr/bin/osascript "$HELPER" "$@" &
child=$!
echo "$child" > "$PIDFILE"
wait "$child"
rm -f "$PIDFILE"
SH

CMD="$CMD" python3 - "$BUNDLE/Contents/document.wflow" <<'PY'
import os, plistlib, sys, uuid
out = sys.argv[1]
action = {
    "action": {
        "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3",
        "AMApplication": ["Automator"],
        "AMParameterProperties": {
            "COMMAND_STRING": {}, "CheckedForUserDefaultShell": {},
            "inputMethod": {}, "shell": {}, "source": {},
        },
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {
            "COMMAND_STRING": os.environ["CMD"],
            "CheckedForUserDefaultShell": True,
            "inputMethod": 1,          # 1 = pass input as arguments
            "shell": "/bin/zsh",
            "source": "",
        },
        "BundleIdentifier": "com.apple.RunShellScript",
        "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False,
        "CanShowWhenRun": True,
        "Category": ["AMCategoryUtilities"],
        "Class Name": "RunShellScriptAction",
        "InputUUID": str(uuid.uuid4()).upper(),
        "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
        "OutputUUID": str(uuid.uuid4()).upper(),
        "UUID": str(uuid.uuid4()).upper(),
        "UnlocalizedApplications": ["Automator"],
        "arguments": {},
        "isViewVisible": 1,
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
with open(out, "wb") as f:
    plistlib.dump(doc, f)
PY

# --- verify, rather than announce -------------------------------------------
fail=""
[ -f "$BUNDLE/Contents/Info.plist" ] || fail="$fail Info.plist"
[ -f "$BUNDLE/Contents/document.wflow" ] || fail="$fail document.wflow"
[ -f "$BUNDLE/Contents/Resources/airdrop-send.applescript" ] || fail="$fail helper"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || fail="$fail Info.plist(invalid)"
plutil -lint "$BUNDLE/Contents/document.wflow" >/dev/null 2>&1 || fail="$fail document.wflow(invalid)"
if [ -n "$fail" ]; then
    echo "FAILED — bundle is incomplete or malformed:$fail"
    rm -rf "$BUNDLE"
    exit 1
fi

/System/Library/CoreServices/pbs -flush 2>/dev/null
echo "Installed: $BUNDLE"
echo
echo "  Right-click any file or folder in Finder → Quick Actions → AirDrop"
echo "  (on a single file it often appears directly in the menu)"
echo
echo "  Optional, and the part that makes it faster than Share → AirDrop:"
echo "  give it a keyboard shortcut in System Settings → Keyboard →"
echo "  Keyboard Shortcuts… → Services → General → AirDrop."
echo
echo "  If it does not appear, log out and back in — the Services menu is"
echo "  cached per login session and pbs -flush does not always take."
