#!/bin/sh
# what MowBite and other apps know the updater by, worked out from its code: the topics, the labels, the interface's
# requests, its settings and the keys of its answer and status, the environment it takes, and its image, container and
# port. the form of a status value where the code says it (a comment "# form: status <key> <form>"). static.sh compares it with test/contract.txt, a change of it goes in with that file in the same commit:
#   sh test/contract.sh > test/contract.txt
cd "$(dirname "$0")/.." || exit 1
src='updater.sh lib.sh self.sh www/cgi-bin/updater www/cgi-bin/index.cgi'
# (a part's own key, $1, $p, ${id}...; a key only known when it runs, "$key", is left out)
part='s/\$\{?(1|p|id)\}?/<part>/g'
{
  # shellcheck disable=SC2086
  grep -ohE 'mowbite/[a-z_/]+|robot_state/json' $src | sed 's/^/topic /'
  # shellcheck disable=SC2086
  grep -ohE 'mowbite\.update[a-z_.]*[a-z]|openmower\.ui[a-z_.]*[a-z]' $src compose.yaml | sed 's/^/label /'
  sed -n '/^POST)/,/^GET)/p' www/cgi-bin/updater | grep -E '^  [a-z][^)]*\)' | grep -v '^  case' | sed -E 's/^  ([^)]*)\).*/request \1/'
  grep -ohE '(keep|pick) "?[a-z_${}]+' www/cgi-bin/updater | sed -E 's/^(keep|pick) "?/setting /; '"$part"
  sed -n '/^GET)/,$p' www/cgi-bin/updater | grep -oE '\\?"[a-z_]+\\?":' | tr -d '\\":' | sed 's/^/answer /'
  # shellcheck disable=SC2086
  grep -ohE '(^|[;&|{(]) *status "?[A-Za-z0-9_${}]+' $src | sed -E 's/.*status "?/status /; '"$part"
  # shellcheck disable=SC2086
  grep -ohE '\$\{[A-Z][A-Z0-9_]*:-' $src | grep -vE 'CONTENT_|XDG_' | tr -d '${:-' | sed 's/^/env /'
  # shellcheck disable=SC2086
  sed -n 's/^ *# form: /form /p' $src
  docker compose -f compose.yaml config --format json |
    jq -r '.services.updater | "compose image \(.image)", "compose container \(.container_name)", "compose network \(.network_mode)", (.volumes[] | "compose volume \(.target)")'
} | grep -v ' \$$' | LC_ALL=C sort -u
