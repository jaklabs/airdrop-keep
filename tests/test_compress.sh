#!/usr/bin/env bash
# Tests for the "Compress to Zip" Quick Action (compress-to-zip.zsh + installer).
# Runs the exact script Finder runs, on throwaway files. macOS only (ditto, zsh, plutil).
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
no() { FAIL=$((FAIL + 1)); echo "  FAIL  $1  ($2)"; }
[ "$(uname)" = Darwin ] || { echo "  SKIP  needs macOS"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
W="$TMP/work dir"; mkdir -p "$W/My Folder/sub"
echo hi > "$W/report one.pdf"; echo a > "$W/My Folder/a.txt"; echo b > "$W/My Folder/sub/b.txt"; echo c > "$W/c.txt"
run() { /bin/zsh "$HERE/compress-to-zip.zsh" "$@" >/dev/null; }

run "$W/report one.pdf"
got=$(zipinfo -1 "$W/report one.pdf.zip" 2>&1)
[ "$got" = "report one.pdf" ] && ok "one file → <name>.zip holding just that file" || no "one file → <name>.zip holding just that file" "$got"

run "$W/My Folder"
got=$(zipinfo -1 "$W/My Folder.zip" 2>&1 | LC_ALL=C sort | tr '\n' '|')
[ "$got" = "My Folder/|My Folder/a.txt|My Folder/sub/|My Folder/sub/b.txt|" ] && ok "a folder unzips as that folder" || no "a folder unzips as that folder" "$got"

run "$W/report one.pdf"
[ -f "$W/report one.pdf 2.zip" ] && [ "$(zipinfo -1 "$W/report one.pdf.zip")" = "report one.pdf" ] \
  && ok "an existing zip is never overwritten (→ '… 2.zip')" || no "an existing zip is never overwritten" "$(ls "$W")"

run "$W/report one.pdf" "$W/c.txt" "$W/My Folder"
got=$(zipinfo -1 "$W/Archive.zip" 2>&1 | LC_ALL=C sort | tr '\n' '|')
[ "$got" = "My Folder/|My Folder/a.txt|My Folder/sub/|My Folder/sub/b.txt|c.txt|report one.pdf|" ] && ok "several items → Archive.zip with each item at the top" || no "several items → Archive.zip" "$got"

X="$TMP/x"; mkdir "$X"; (cd "$X" && unzip -q "$W/Archive.zip")
[ -f "$X/c.txt" ] && [ ! -L "$X/c.txt" ] && [ "$(cat "$X/My Folder/sub/b.txt")" = b ] \
  && ok "Archive.zip holds real files, not the staging links" || no "Archive.zip holds real files" "$(ls -l "$X")"

run "$W/c.txt" "$W/report one.pdf"
[ -f "$W/Archive 2.zip" ] && ok "a second Archive.zip becomes 'Archive 2.zip'" || no "second archive name" "$(ls "$W")"

run; [ $? -eq 0 ] && ok "no selection does nothing" || no "no selection does nothing" "non-zero exit"

COMPRESS_SERVICES_DIR="$TMP/Services" bash "$HERE/install-compress-action.sh" >/dev/null
B="$TMP/Services/Compress to Zip.workflow/Contents"
plutil -lint "$B/Info.plist" >/dev/null && plutil -lint "$B/document.wflow" >/dev/null \
  && ok "installer writes a valid Quick Action bundle" || no "installer writes a valid bundle" "plutil failed"
plutil -convert xml1 -o - "$B/document.wflow" | grep -q "ditto -c -k" \
  && ok "the installed action runs the tested script" || no "installed action runs the tested script" "script not embedded"

# Clean zips: a file carrying Mac metadata must not drag a __MACOSX folder in.
echo meta > "$W/tagged.txt"; xattr -w com.apple.metadata:test "x" "$W/tagged.txt"
run "$W/tagged.txt"
got=$(zipinfo -1 "$W/tagged.txt.zip" 2>&1)
[ "$got" = "tagged.txt" ] && ok "zips are clean: no __MACOSX or ._ files" || no "zips are clean" "$got"

# The app: its core logic, then the built app itself.
if command -v swiftc >/dev/null 2>&1; then
  CB="$TMP/core"; mkdir -p "$CB"; cp "$HERE/tests/CompressCoreTests.swift" "$CB/main.swift"
  if swiftc -o "$CB/coretests" "$HERE/CompressCore.swift" "$CB/main.swift" 2>"$CB/log"; then
    "$CB/coretests" "$HERE/compress-to-zip.zsh" | sed 's/^/    /'
    [ "${PIPESTATUS[0]}" -eq 0 ] && ok "app core: all checks pass" || no "app core" "see failures above"
  else
    no "app core compiles" "$(head -5 "$CB/log")"
  fi

  COMPRESS_APP_DIR="$TMP/Apps" bash "$HERE/install-compress-app.sh" >/dev/null 2>"$TMP/app.log"
  APP="$TMP/Apps/Compress to Zip.app"
  [ -x "$APP/Contents/MacOS/CompressToZip" ] && ok "the app builds and installs" || no "the app builds and installs" "$(cat "$TMP/app.log")"
  cmp -s "$APP/Contents/Resources/compress-to-zip.zsh" "$HERE/compress-to-zip.zsh" \
    && ok "the app carries the same tested script" || no "app carries the tested script" "missing or different"
  plutil -convert xml1 -o - "$APP/Contents/Info.plist" | grep -q "public.item" \
    && plutil -convert xml1 -o - "$APP/Contents/Info.plist" | grep -q "<string>None</string>" \
    && ok "accepts drops on its Dock icon without becoming anyone's default app" || no "document types" "Info.plist"
  D="$TMP/dl"; mkdir -p "$D"; echo old > "$D/report one.pdf.zip"
  OUT=$("$APP/Contents/MacOS/CompressToZip" --headless --download-dir "$D" "$W/report one.pdf")
  [ "$OUT" = "$D/report one.pdf 2.zip" ] && [ "$(cat "$D/report one.pdf.zip")" = old ] && [ "$(zipinfo -1 "$OUT")" = "report one.pdf" ] \
    && ok "the built app zips and downloads without overwriting" || no "app download path" "$OUT"
  "$APP/Contents/MacOS/CompressToZip" --headless --download-dir "$D" "$W/nope.txt" >/dev/null 2>&1
  [ $? -ne 0 ] && ok "the built app reports a failure instead of pretending" || no "app failure reporting" "exit 0 on a missing file"
  grep -q 'keyEquivalent = ""' "$HERE/CompressToZipApp.swift" \
    && ok "Download is click-only (a stray Return cannot save)" || no "Download is click-only" "Return key still bound"
else
  echo "  SKIP  app tests (needs swiftc)"
fi

echo; printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
