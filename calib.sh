#!/bin/sh
# OpenMower's mower_params.yaml changed for a calibration, run by the updater in a helper container of its own image
# with only the file's folder at /p (no network, no docker): the values asked for and nothing else, the rest of the file
# byte for byte. write: a copy of the file before as <file>.mowbite-<unix> (the newest 2 kept), the new one written next
# to it with its owner and mode, renamed over it and read again to see it's what was meant. back: the newest copy put
# back the same way. read: the values of the paths as the file has them. a path is its keys joined by / (ll/services/x)
#   calib.sh write <file> <path> <value> [<path> <value> ...]   "ok <path> <old> <new>" a line, then "backup <name>"
#   calib.sh back <file>                                         "back <name>"
#   calib.sh read <file> <path> [<path> ...]                     "<path> <value>" for each one it has, "backup <name>"
#                                                                for the newest copy when there is one
# "refused <why>" and 1 when it can't: a file it doesn't know how to change safely is left as it is
set -u
cd /p 2> /dev/null || { echo "refused no_folder"; exit 1; }
what=${1:-}
file=${2:-}
case $file in '' | */* | .*) echo "refused no_file"; exit 1 ;; esac
[ -f "$file" ] && [ ! -L "$file" ] || { echo "refused no_file"; exit 1; }
[ "$(wc -c < "$file")" -le 65536 ] || { echo "refused too_big"; exit 1; }
shift 2

# the file as block mappings, the paths of its keys: "<line> <path> <value>" for each key line with a plain value,
# "<line> <path>" for the others. refused for what makes a value's place unclear (tabs, more than one document, merge
# keys, an anchor or alias on a key line)
keys() {
  awk '
    /^[ ]*#/ || /^[ ]*$/ { next }
    /\t/ { print "refused tabs"; exit 1 }
    /^(---|\.\.\.)/ { if (NR > 1 || $0 !~ /^---[ ]*$/) { print "refused documents"; exit 1 } next }
    /^[ ]*<<[ ]*:/ { print "refused merge_keys"; exit 1 }
    match($0, /^ *[A-Za-z0-9_]+:/) {
      len = RLENGTH
      ind = match($0, /[^ ]/) - 1
      key = substr($0, ind + 1, len - ind - 1)
      rest = substr($0, len + 1)
      while (d > 0 && at[d] >= ind) d--
      at[++d] = ind
      k[d] = key
      p = k[1]
      for (i = 2; i <= d; i++) p = p "/" k[i]
      v = rest
      sub(/^ +/, "", v)
      sub(/ +#.*$/, "", v)
      sub(/ +$/, "", v)
      if (v ~ /^[&*]/) { print "refused anchors " p; exit 1 }
      print NR, p, v
    }
  ' "$file"
}

# a value as a number the file takes
number() { printf '%s' "$1" | grep -Eq '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$'; }
# the newest copy of ours (the names sort by their time)
newest() {
  n=
  for f in "$file".mowbite-*; do [ -e "$f" ] && n=$f; done
  echo "$n"
}

case $what in
read)
  k=$(keys) || { echo "$k" | tail -n1; exit 1; }
  for p in "$@"; do
    # (a value with spaces in quotes whole, e.g. a password for the redaction of logs)
    printf '%s\n' "$k" | awk -v p="$p" '$2 == p && NF >= 3 { v = $0; sub(/^[^ ]+ [^ ]+ /, "", v); print p, v }'
  done
  last=$(newest)
  [ -z "$last" ] || echo "backup $last"
  ;;
write)
  [ $# -ge 2 ] && [ $(($# % 2)) -eq 0 ] || { echo "refused no_values"; exit 1; }
  k=$(keys) || { echo "$k" | tail -n1; exit 1; }
  want=
  while [ $# -ge 2 ]; do
    number "$2" || { echo "refused not_a_number $1"; exit 1; }
    n=$(printf '%s\n' "$k" | awk -v p="$1" '$2 == p' | wc -l)
    [ "$n" -eq 1 ] || { if [ "$n" -eq 0 ]; then echo "refused missing $1"; else echo "refused twice $1"; fi; exit 1; }
    line=$(printf '%s\n' "$k" | awk -v p="$1" '$2 == p { print $1, NF == 3 ? $3 : "" }')
    old=${line#* }
    number "$old" || { echo "refused not_a_number_now $1"; exit 1; }
    want="$want ${line%% *} $1 $old $2"
    shift 2
  done
  t=$(date +%s)
  back="$file.mowbite-$t"
  new=".$file.mowbite-new"
  owner=$(stat -c '%u:%g' "$file") && mode=$(stat -c '%a' "$file") || { echo "refused no_stat"; exit 1; }
  cp -p "$file" "$back" || { echo "refused no_copy"; exit 1; }
  # only the value of each line asked for, its spaces and its comment kept
  awk -v want="$want" '
    BEGIN { n = split(want, w, " "); for (i = 1; i < n; i += 4) to[w[i]] = w[i + 3] }
    (NR in to) {
      match($0, /^ *[A-Za-z0-9_]+: */)
      head = substr($0, 1, RLENGTH)
      rest = substr($0, RLENGTH + 1)
      match(rest, /^[^ #]+/)
      print head to[NR] substr(rest, RLENGTH + 1)
      next
    }
    { print }
  ' "$file" > "$new" && chown "$owner" "$new" && chmod "$mode" "$new" || {
    rm -f "$new" "$back"
    echo "refused no_write"
    exit 1
  }
  # (a file without a newline at its end keeps it that way)
  if [ -n "$(tail -c1 "$file")" ]; then
    head -c "$(($(wc -c < "$new") - 1))" "$new" > "$new.x" && cat "$new.x" > "$new" && rm -f "$new.x"
  fi
  # the same lines but those asked for, and those with the new value
  if ! awk -v want="$want" '
    BEGIN { n = split(want, w, " "); for (i = 1; i < n; i += 4) to[w[i]] = 1 }
    NR == FNR { a[FNR] = $0; na = FNR; next }
    { b[FNR] = $0; nb = FNR }
    END {
      if (na != nb) exit 1
      for (i = 1; i <= na; i++) if (!(i in to) && a[i] != b[i]) exit 1
    }
  ' "$back" "$new"; then
    rm -f "$new" "$back"
    echo "refused check"
    exit 1
  fi
  mv -f "$new" "$file" || { rm -f "$new" "$back"; echo "refused no_rename"; exit 1; }
  k=$(keys) || { cp -p "$back" "$file"; echo "refused check"; exit 1; }
  # shellcheck disable=SC2086
  set -- $want
  while [ $# -ge 4 ]; do
    now=$(printf '%s\n' "$k" | awk -v p="$2" '$2 == p && NF == 3 { print $3 }')
    [ "$now" = "$4" ] || { cp -p "$back" "$file"; echo "refused check $2"; exit 1; }
    echo "ok $2 $3 $4"
    shift 4
  done
  # the newest two copies of ours, the others' copies stay
  set -- "$file".mowbite-*
  while [ $# -gt 2 ]; do
    rm -f "$1"
    shift
  done
  echo "backup $back"
  ;;
back)
  last=$(newest)
  [ -n "$last" ] || { echo "refused no_backup"; exit 1; }
  new=".$file.mowbite-new"
  cp -p "$last" "$new" && chown "$(stat -c '%u:%g' "$file")" "$new" && chmod "$(stat -c '%a' "$file")" "$new" &&
    mv -f "$new" "$file" || { rm -f "$new"; echo "refused no_write"; exit 1; }
  echo "back $last"
  ;;
*)
  echo "refused what"
  exit 1
  ;;
esac
