#!/usr/bin/env bash
# Tests for airdrop-keep — both halves.
#
# Every test here comes from something that actually broke, not from a coverage
# target. The send-side ones in particular are the bugs that shipped to a user
# on 2026-09-16 and took four rounds to find; each one is phrased so it fails
# against the build that had the bug.
#
#   ./tests/test_airdrop.sh
#
# macOS-only tests are skipped elsewhere (CI runs the portable ones on Linux).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m  %s (%s)\n' "$1" "$2"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3" "expected [$2], got [$1]"; fi; }

echo
echo "=== receive side: airdrop-keep.sh ==="

# A file that looks like it arrived via AirDrop at $2 (epoch seconds).
mk_airdrop_file() {
  printf 'x' > "$1"
  xattr -w com.apple.quarantine "0081;$(printf '%x' "$2");sharingd;" "$1" 2>/dev/null
}

if [ "$IS_MAC" = "1" ]; then
  run_keep() {
    AIRDROP_SRC="$TMP/dl" AIRDROP_KEEP="$TMP/keep" AIRDROP_STATE="$TMP/state" \
      AIRDROP_BATCH_GAP="${1:-120}" bash "$HERE/airdrop-keep.sh" 2>&1
  }
  reset() { rm -rf "$TMP/dl" "$TMP/keep" "$TMP/state"; mkdir -p "$TMP/dl"; }
  now=1750000000

  # THE core promise of this tool: it never touches the originals.
  reset
  mk_airdrop_file "$TMP/dl/a.jpg" "$now"
  before="$(cksum < "$TMP/dl/a.jpg")"
  run_keep >/dev/null
  if [ -f "$TMP/dl/a.jpg" ] && [ "$(cksum < "$TMP/dl/a.jpg")" = "$before" ]; then
    ok "original file is left in place, unmodified"
  else
    no "original file is left in place, unmodified" "the source file was moved, deleted or changed"
  fi
  link="$(find "$TMP/keep" -name 'a.jpg' 2>/dev/null | head -1)"
  if [ -L "$link" ]; then ok "batch entry is a symlink, not a copy"
  else no "batch entry is a symlink, not a copy" "found: ${link:-nothing}"; fi

  # Batching: the gap is what separates one transfer from the next.
  reset
  mk_airdrop_file "$TMP/dl/one.jpg" "$now"
  mk_airdrop_file "$TMP/dl/two.jpg" $((now + 10))
  run_keep 120 >/dev/null
  check "$(find "$TMP/keep" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "1" \
        "two files 10s apart land in ONE batch"

  reset
  mk_airdrop_file "$TMP/dl/one.jpg" "$now"
  mk_airdrop_file "$TMP/dl/two.jpg" $((now + 600))
  run_keep 120 >/dev/null
  check "$(find "$TMP/keep" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "2" \
        "two files 600s apart split into TWO batches"

  # Idempotence is what makes the launchd watcher safe to fire constantly.
  reset
  mk_airdrop_file "$TMP/dl/a.jpg" "$now"
  run_keep >/dev/null
  second="$(run_keep)"
  check "$(printf '%s' "$second" | grep -o 'indexed [0-9]*' | awk '{print $2}')" "0" \
        "second run indexes 0 new files"
  check "$(find "$TMP/keep" -name 'a.jpg*' | wc -l | tr -d ' ')" "1" \
        "second run does not duplicate the link"

  # Only AirDrop files. A browser download shares the folder and must be ignored.
  reset
  mk_airdrop_file "$TMP/dl/air.jpg" "$now"
  printf 'x' > "$TMP/dl/browser.jpg"
  xattr -w com.apple.quarantine "0081;$(printf '%x' "$now");Safari;" "$TMP/dl/browser.jpg" 2>/dev/null
  run_keep >/dev/null
  if [ -z "$(find "$TMP/keep" -name 'browser.jpg' 2>/dev/null)" ]; then
    ok "a Safari download in the same folder is ignored"
  else
    no "a Safari download in the same folder is ignored" "non-AirDrop file was indexed"
  fi
else
  skip "receive-side tests" "needs macOS xattr/quarantine"
fi

echo
echo "=== messages-keep: moving locally-saved media out of Downloads ==="

if [ "$IS_MAC" = "1" ]; then
  MK() { MESSAGES_SRC="$TMP/mdl" MESSAGES_KEEP="$TMP/mkeep" MESSAGES_STATE="$TMP/mstate" \
           bash "$HERE/messages-keep.sh" "$@" 2>&1; }
  mreset() { rm -rf "$TMP/mdl" "$TMP/mkeep" "$TMP/mstate"; mkdir -p "$TMP/mdl"; }

  # A dry run must be a genuine no-op. This tool MOVES files; if the default
  # ever stops being safe, it is the kind of mistake you notice too late.
  mreset
  printf 'x' > "$TMP/mdl/IMG_1.jpg"
  MK >/dev/null
  if [ -f "$TMP/mdl/IMG_1.jpg" ] && [ ! -d "$TMP/mkeep" ]; then
    ok "dry run moves nothing and creates nothing"
  else
    no "dry run moves nothing and creates nothing" "the default run had side effects"
  fi

  mreset
  printf 'x' > "$TMP/mdl/IMG_1.jpg"
  MK --commit >/dev/null
  if [ ! -f "$TMP/mdl/IMG_1.jpg" ] && [ -n "$(find "$TMP/mkeep" -name 'IMG_1.jpg' 2>/dev/null)" ]; then
    ok "--commit moves an untagged image out of Downloads"
  else
    no "--commit moves an untagged image out of Downloads"
  fi

  # The whole discrimination: anything with a KNOWN origin is not yours-from-Messages.
  mreset
  printf 'x' > "$TMP/mdl/airdropped.jpg"
  xattr -w com.apple.quarantine "0081;68c00000;sharingd;" "$TMP/mdl/airdropped.jpg" 2>/dev/null
  printf 'x' > "$TMP/mdl/downloaded.jpg"
  xattr -w com.apple.quarantine "0081;68c00000;Chrome;" "$TMP/mdl/downloaded.jpg" 2>/dev/null
  MK --commit >/dev/null
  if [ -f "$TMP/mdl/airdropped.jpg" ] && [ -f "$TMP/mdl/downloaded.jpg" ]; then
    ok "AirDrop and browser files are left alone"
  else
    no "AirDrop and browser files are left alone" "a file with a known source was moved"
  fi

  mreset
  printf 'x' > "$TMP/mdl/notes.pdf"; printf 'x' > "$TMP/mdl/archive.zip"
  MK --commit >/dev/null
  if [ -f "$TMP/mdl/notes.pdf" ] && [ -f "$TMP/mdl/archive.zip" ]; then
    ok "non-media files are left alone"
  else
    no "non-media files are left alone"
  fi

  # Reversibility is what makes moving acceptable at all.
  mreset
  printf 'abc' > "$TMP/mdl/IMG_9.jpg"
  before="$(cksum < "$TMP/mdl/IMG_9.jpg")"
  MK --commit >/dev/null
  MK --undo >/dev/null
  if [ -f "$TMP/mdl/IMG_9.jpg" ] && [ "$(cksum < "$TMP/mdl/IMG_9.jpg")" = "$before" ]; then
    ok "--undo puts the file back, byte-identical"
  else
    no "--undo puts the file back, byte-identical" "undo did not restore the original"
  fi

  # Two real files can share a name. Overwriting one would destroy a photo.
  mreset
  mkdir -p "$TMP/mkeep"
  printf 'first' > "$TMP/mdl/IMG_5.jpg"
  MK --commit >/dev/null
  printf 'second' > "$TMP/mdl/IMG_5.jpg"
  MK --commit >/dev/null
  check "$(find "$TMP/mkeep" -name 'IMG_5*.jpg' | wc -l | tr -d ' ')" "2" \
        "a same-named second file is kept, not overwritten"

  # Nothing is ever destroyed: every input is still somewhere afterwards.
  mreset
  for i in 1 2 3; do printf 'x%s' "$i" > "$TMP/mdl/IMG_c$i.jpg"; done
  MK --commit >/dev/null
  total=$(( $(find "$TMP/mdl" -type f | wc -l) + $(find "$TMP/mkeep" -type f 2>/dev/null | wc -l) ))
  check "$(printf '%s' "$total" | tr -d ' ')" "3" "no file is lost or deleted by a move"
else
  skip "messages-keep tests" "needs macOS xattr"
fi

echo
echo "=== send side: the Quick Action ==="

SWIFT="$HERE/AirDropSend.swift"

# The bug that shipped: AppleScript cannot implement
# sharingService:didFailToShareItems:error: (`error` is a reserved word), so the
# tool was blind to its own failures for three debugging rounds.
if grep -q "didFailToShareItems" "$SWIFT"; then
  ok "sender implements didFailToShareItems (can report WHY a send failed)"
else
  no "sender implements didFailToShareItems (can report WHY a send failed)"
fi

# The other shipped bug: quitting the instant didShareItems arrives killed the
# process mid-handoff, because that callback fires when the recipient is PICKED.
if grep -A3 "func sharingService.*didShareItems" "$SWIFT" | grep -q "asyncAfter"; then
  ok "does not terminate synchronously inside didShareItems"
else
  no "does not terminate synchronously inside didShareItems" \
     "quitting there aborts the transfer the user just started"
fi

# A script cannot receive the click; only a real NSApplication event loop can.
# Anchored and uncommented on purpose: `grep -q "app.run()"` matched a line that
# had been COMMENTED OUT, so this test passed against a build with the event loop
# removed. Found by mutation, not by the suite.
if grep -qE '^[[:space:]]*app\.run\(\)' "$SWIFT"; then
  ok "sender runs a real NSApplication event loop"
else
  no "sender runs a real NSApplication event loop" \
     "without app.run() the picker draws but never receives the click"
fi

if [ "$IS_MAC" = "1" ] && command -v swiftc >/dev/null 2>&1; then
  if swiftc -O -o "$TMP/adsend" "$SWIFT" 2>"$TMP/swifterr"; then
    ok "AirDropSend.swift compiles"
  else
    no "AirDropSend.swift compiles" "$(head -3 "$TMP/swifterr")"
  fi

  # --- installer behaviour, against a scratch Services dir -------------------
  export AIRDROP_SERVICES_DIR="$TMP/Services"
  if bash "$HERE/install-quick-action.sh" >"$TMP/install.out" 2>&1; then
    B="$TMP/Services/AirDrop.workflow"
    plutil -lint "$B/Contents/Info.plist" >/dev/null 2>&1 \
      && ok "Info.plist is a valid plist" || no "Info.plist is a valid plist"
    plutil -lint "$B/Contents/document.wflow" >/dev/null 2>&1 \
      && ok "document.wflow is a valid plist" || no "document.wflow is a valid plist"

    # It must be a compiled binary. A script here is the original bug.
    if file "$B/Contents/Resources/AirDropSend.app/Contents/MacOS/AirDropSend" 2>/dev/null | grep -q "Mach-O"; then
      ok "installed sender is a compiled Mach-O binary, not a script"
    else
      no "installed sender is a compiled Mach-O binary, not a script"
    fi

    check "$(plutil -extract NSServices.0.NSSendFileTypes.0 raw -o - "$B/Contents/Info.plist" 2>/dev/null)" \
          "public.item" "Quick Action offers itself for every file type"

    CMD="$(python3 -c "
import plistlib,sys
d=plistlib.load(open('$B/Contents/document.wflow','rb'))
print(d['actions'][0]['action']['ActionParameters']['COMMAND_STRING'])" 2>/dev/null)"
    IM="$(python3 -c "
import plistlib
d=plistlib.load(open('$B/Contents/document.wflow','rb'))
print(d['actions'][0]['action']['ActionParameters']['inputMethod'])" 2>/dev/null)"
    # inputMethod 0 sends paths on stdin, where "\$@" is empty and nothing sends.
    check "$IM" "1" "workflow passes the selection AS ARGUMENTS, not on stdin"

    # The wrapper must not kill itself. `pkill -f` on the helper path matched the
    # wrapper's own command line, killing it before it launched anything.
    killline="$(printf '%s' "$CMD" | grep -E '^\s*/usr/bin/pkill' || true)"
    if [ -z "$killline" ]; then
      no "wrapper kills a previous picker" "no pkill line found"
    else
      pat="$(printf '%s' "$killline" | sed -E 's/.*pkill +(-[a-z]+ +)*//; s/ *2>.*//; s/^"//; s/"$//')"
      if printf '%s' "$CMD" | grep -qE "^\s*/usr/bin/pkill" && printf '%s' "$killline" | grep -q -- "-x"; then
        ok "previous picker is killed by process NAME (-x), which cannot match the wrapper"
      else
        if printf '%s' "$CMD" | grep -v pkill | grep -qF "$pat"; then
          no "kill pattern must not match the wrapper itself" \
             "pattern [$pat] appears elsewhere in the wrapper — it would kill itself"
        else
          ok "kill pattern does not appear elsewhere in the wrapper"
        fi
      fi
    fi

    # The wrapper must point at the bundle it was installed into.
    if printf '%s' "$CMD" | grep -q "$TMP/Services/AirDrop.workflow"; then
      ok "wrapper points at the installed bundle, not a hard-coded path"
    else
      no "wrapper points at the installed bundle, not a hard-coded path" \
         "$(printf '%s' "$CMD" | grep '^APP=' || echo 'no APP= line')"
    fi

    if bash "$HERE/install-quick-action.sh" --uninstall >/dev/null 2>&1 && [ ! -e "$B" ]; then
      ok "--uninstall removes the bundle"
    else
      no "--uninstall removes the bundle"
    fi
  else
    no "installer succeeds against a scratch Services dir" "$(tail -2 "$TMP/install.out")"
  fi

  # A broken sender must not produce a half-installed Quick Action that silently
  # does nothing — the worst possible outcome for a menu item.
  BROKEN="$TMP/broken"; mkdir -p "$BROKEN"
  cp "$HERE/install-quick-action.sh" "$BROKEN/"
  echo 'this is not valid swift @@@' > "$BROKEN/AirDropSend.swift"
  AIRDROP_SERVICES_DIR="$TMP/Services2" bash "$BROKEN/install-quick-action.sh" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 0 ] && [ ! -e "$TMP/Services2/AirDrop.workflow" ]; then
    ok "a sender that does not compile is refused, leaving nothing installed"
  else
    no "a sender that does not compile is refused, leaving nothing installed" \
       "exit=$rc, bundle present=$([ -e "$TMP/Services2/AirDrop.workflow" ] && echo yes || echo no)"
  fi
  unset AIRDROP_SERVICES_DIR
else
  skip "installer + compile tests" "needs macOS with swiftc"
fi

echo
printf '  %d passed, %d failed, %d skipped\n\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
