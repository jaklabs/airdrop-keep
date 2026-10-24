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
run() { /bin/zsh "$HERE/compress-to-zip.zsh" "$@"; }

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

echo; printf '  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
