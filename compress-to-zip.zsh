#!/bin/zsh
# compress-to-zip.zsh — the body of the "Compress to Zip" Quick Action (zsh).
# Arguments: the paths selected in Finder. Same results as Finder's Compress:
#   one item  → "<name>.zip" beside it
#   several   → "Archive.zip" beside them
# An existing zip is never overwritten: "Archive 2.zip", "Archive 3.zip", ...
[ $# -eq 0 ] && exit 0
dir="${1:h}"

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Compress to Zip\"" >/dev/null 2>&1; }

free_name() {  # $1 = base name without .zip
  local out="$dir/$1.zip" n=2
  while [ -e "$out" ]; do out="$dir/$1 $n.zip"; n=$((n + 1)); done
  print -r -- "$out"
}

if [ $# -eq 1 ]; then
  out="$(free_name "${1:t}")"
  # --keepParent makes a FOLDER unzip as that folder; on a single FILE it would
  # also wrap the file in its parent folder's name, so files go without it.
  if [ -d "$1" ]; then keep=(--keepParent); else keep=(); fi
  if /usr/bin/ditto -c -k --sequesterRsrc "${keep[@]}" "$1" "$out"; then
    notify "Created ${out:t}"
  else
    rm -f "$out"; notify "Could not compress ${1:t}"; exit 1
  fi
else
  # ditto takes one source, so the selection is gathered (as links, not copies)
  # in a temporary folder and compressed from there, the way Finder's Archive.zip looks.
  out="$(free_name Archive)"
  stage="$(/usr/bin/mktemp -d)" || exit 1
  for f in "$@"; do /bin/ln -s "$f" "$stage/${f:t}"; done
  if (cd "$stage" && /usr/bin/zip -r -q -X "$out" . -x '.DS_Store' '*/.DS_Store'); then
    notify "Created ${out:t} from $# items"
  else
    rm -f "$out"; notify "Could not compress the selection"; /bin/rm -rf "$stage"; exit 1
  fi
  /bin/rm -rf "$stage"
fi
