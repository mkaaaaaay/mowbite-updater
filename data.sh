#!/bin/sh
# a part's data kept before an update and put back, run by the updater in a helper container of its own image without
# network, the data's folder or volume at /s (read-only, but to put back), a kept copy's folder at /o (to keep) or /b
# (to put back, read-only). a piece is a file in /s by its name, or "." all of it
#   data.sh keep <n> <piece>   <n>.tar of it in /o and <n>.sums, what the tar holds; <n>.schema for . with a schema
#                              file. 3 when there's no such piece
#   data.sh put <n> <piece>    /b/<n>.tar unpacked next to the piece and checked against /b/<n>.sums (a copy cut
#                              short unpacks without a word), moved over it, then read again against them. done
#                              again from the start it ends the same (a stop halfway)
#   data.sh schema <n> <piece> the number in the piece's schema file, 1 without one (the format before it had one)
set -u
# (unpacked here first: on the same disk, so it's moved over and not copied)
STAGE=.updater-put
what=${1:-}
n=${2:-}
piece=${3:-}
case $n in '' | *[!0-9]*) echo "data.sh: no number" >&2; exit 1 ;; esac
case $piece in '' | .. | -* | */*) echo "data.sh: no piece" >&2; exit 1 ;; esac
cd /s || exit 1

# each thing in it a line, by name: "<owner>:<group>:<mode> <sha256, - for no file> <name>", a link "link <where to>
# <name>" (tar doesn't give a link its owner back, nothing goes by it). its folder itself not: it isn't replaced
sums() {
  find "$1" | sort | while IFS= read -r f; do
    [ "$f" = . ] && continue
    if [ -L "$f" ]; then
      printf 'link %s %s\n' "$(readlink "$f")" "$f"
      continue
    fi
    if [ -f "$f" ]; then h=$(sha256sum < "$f" | cut -d' ' -f1); else h=-; fi
    printf '%s %s %s\n' "$(stat -c %u:%g:%a "$f")" "$h" "$f"
  done
}
schema() {
  v=$(head -c 20 "$1/schema" 2> /dev/null | tr -d ' \n')
  case $v in '' | *[!0-9]*) echo 1 ;; *) echo "$v" ;; esac
}

case $what in
keep)
  [ -e "$piece" ] || [ -L "$piece" ] || exit 3
  [ "$piece" = . ] || [ ! -d "$piece" ] || { echo "data.sh: a folder only as ." >&2; exit 1; }
  tar -cf "/o/$n.tar" --numeric-owner --exclude "./$STAGE" -- "$piece" || exit 1
  # (what the tar holds, not the folder again: it may have changed meanwhile)
  rm -rf /tmp/k && mkdir /tmp/k && tar -xf "/o/$n.tar" -C /tmp/k --numeric-owner && (cd /tmp/k && sums "$piece") > "/o/$n.sums" || exit 1
  if [ -d "$piece" ] && [ -f "$piece/schema" ]; then schema "$piece" > "/o/$n.schema" || exit 1; fi
  ;;
put)
  rm -rf "$STAGE" && mkdir "$STAGE" || exit 1
  tar -xf "/b/$n.tar" -C "$STAGE" --numeric-owner || { rm -rf "$STAGE"; exit 1; }
  (cd "$STAGE" && sums "$piece") | cmp -s - "/b/$n.sums" || { rm -rf "$STAGE"; echo "data.sh: the copy of $piece isn't what was kept" >&2; exit 1; }
  if [ "$piece" = . ]; then
    # (all of it: what's there goes, what was kept comes. done again it finds the rest of either)
    for e in * .[!.]* ..?*; do
      [ -e "$e" ] || [ -L "$e" ] || continue
      [ "$e" = "$STAGE" ] || rm -rf "$e" || exit 1
    done
    for e in "$STAGE"/* "$STAGE"/.[!.]* "$STAGE"/..?*; do
      [ -e "$e" ] || [ -L "$e" ] || continue
      mv "$e" . || exit 1
    done
  else
    # (a file renamed over the one there: it's the old one or the new one, never half of it)
    mv "$STAGE/$piece" "$piece" || exit 1
  fi
  rm -rf "$STAGE"
  sync
  sums "$piece" | cmp -s - "/b/$n.sums" || { echo "data.sh: $piece isn't what was kept" >&2; exit 1; }
  ;;
schema) schema "$piece" ;;
*) exit 1 ;;
esac
