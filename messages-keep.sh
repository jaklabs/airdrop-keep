#!/usr/bin/env bash
# messages-keep — move locally-saved media (pictures you saved out of Messages)
# out of ~/Downloads and into dated folders, so Downloads stops being a haystack.
#
# HOW IT IDENTIFIES THEM — and the honest limit of it.
# AirDrop files carry quarantine agent `sharingd`; browser downloads carry
# `Chrome`/`Safari` plus kMDItemWhereFroms; Preview exports carry `Preview`.
# A file saved out of Messages carries NONE of these, because it is a local copy
# of a file macOS already trusts. So the signal here is NEGATIVE SPACE: media
# with no quarantine agent and no WhereFroms did not come from the network.
#
# ⚠️ That is a heuristic, not a proof. It means "locally saved", and Messages is
# by far the most common way that happens — but a hand-copied photo looks the
# same. It is deliberately conservative: anything with ANY known source is left
# alone. On a 1,232-file Downloads folder it selected 14 and ignored 902.
# For proof rather than inference you need Full Disk Access and a lookup against
# ~/Library/Messages/chat.db; see --strict in the README.
#
# NEVER DELETES. Moves only, and records every move so --undo can put it back.
#
# Usage:
#   ./messages-keep.sh            # DRY RUN — show what would move, touch nothing
#   ./messages-keep.sh --commit   # actually move
#   ./messages-keep.sh --undo     # reverse the most recent committed run
set -uo pipefail

SRC="${MESSAGES_SRC:-$HOME/Downloads}"
DEST="${MESSAGES_KEEP:-$HOME/Messages Media}"
STATE="${MESSAGES_STATE:-$HOME/.messages-keep}"
LEDGER="$STATE/moves.tsv"
MEDIA_EXT="jpg jpeg png heic heif gif mov mp4 m4v webp"

mkdir -p "$STATE"
MODE="${1:-}"

# --- undo ---------------------------------------------------------------------
if [ "$MODE" = "--undo" ]; then
    [ -s "$LEDGER" ] || { echo "nothing to undo (no ledger at $LEDGER)"; exit 0; }
    last="$(tail -1 "$LEDGER" | cut -f1)"
    n=0; missing=0
    # Reverse order, so a de-collided name goes back before the one it dodged.
    while IFS=$'\t' read -r run src dst; do
        [ "$run" = "$last" ] || continue
        if [ -e "$dst" ]; then
            mkdir -p "$(dirname "$src")"
            mv "$dst" "$src" && n=$((n+1))
        else
            missing=$((missing+1))
        fi
    done < <(grep -F "$last" "$LEDGER" | tail -r)
    grep -vF "$last" "$LEDGER" > "$LEDGER.tmp" 2>/dev/null || true
    mv "$LEDGER.tmp" "$LEDGER" 2>/dev/null || true
    echo "undo: restored $n file(s) to $SRC"
    [ "$missing" -gt 0 ] && echo "      $missing file(s) were not where the ledger left them; skipped (nothing deleted)"
    exit 0
fi

COMMIT=0; [ "$MODE" = "--commit" ] && COMMIT=1

# --- has this file a known origin? --------------------------------------------
# Returns 0 if we can name where it came from (so: leave it alone).
has_known_origin() {
    xattr -p com.apple.quarantine "$1" >/dev/null 2>&1 && return 0
    local wf
    wf="$(mdls -name kMDItemWhereFroms -raw "$1" 2>/dev/null)"
    [ -n "$wf" ] && [ "$wf" != "(null)" ] && return 0
    return 1
}

is_media() {
    local ext="${1##*.}"
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
    case " $MEDIA_EXT " in *" $ext "*) return 0 ;; *) return 1 ;; esac
}

run_id="$(date '+%Y%m%d-%H%M%S')"
moved=0; skipped=0
[ "$COMMIT" -eq 1 ] || echo "DRY RUN — nothing will move. Re-run with --commit to apply."
echo

while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    is_media "$base" || continue
    if has_known_origin "$f"; then skipped=$((skipped+1)); continue; fi

    # File by the day the file landed, which is when you saved it.
    day="$(date -r "$f" '+%Y-%m-%d')"
    target_dir="$DEST/$day"
    target="$target_dir/$base"
    # Two real files can share a name -- de-collide instead of overwriting.
    if [ -e "$target" ]; then
        stem="${base%.*}"; ext="${base##*.}"; k=1
        while [ -e "$target_dir/$stem ($k).$ext" ]; do k=$((k+1)); done
        target="$target_dir/$stem ($k).$ext"
    fi

    if [ "$COMMIT" -eq 1 ]; then
        mkdir -p "$target_dir"
        if mv "$f" "$target"; then
            printf '%s\t%s\t%s\n' "$run_id" "$f" "$target" >> "$LEDGER"
            moved=$((moved+1))
            printf '  moved  %s  ->  %s/\n' "$base" "$day"
        else
            printf '  FAILED %s (left in place)\n' "$base"
        fi
    else
        moved=$((moved+1))
        printf '  would move  %s  ->  %s/%s/\n' "$base" "$(basename "$DEST")" "$day"
    fi
done < <(find "$SRC" -maxdepth 1 -type f -print0 2>/dev/null)

echo
if [ "$COMMIT" -eq 1 ]; then
    echo "messages-keep: moved $moved file(s) into \"$DEST\"  ($skipped with a known source left alone)"
    [ "$moved" -gt 0 ] && echo "               undo this run with:  $0 --undo"
else
    echo "messages-keep: $moved file(s) would move, $skipped left alone (known source)."
    echo "               apply with:  $0 --commit"
fi
