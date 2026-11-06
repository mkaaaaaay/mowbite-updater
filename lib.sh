# shared by the updater (updater.sh), its own update (self.sh) and its interface (www/cgi-bin/updater): where things are,
# the settings, the status, the stacks, the parts. settings, status and log live in its own stack folder (.updater next
# to its compose.yaml): only it can write there, the page asks for them over http
OM=${OPENMOWER_CONTAINER:-open_mower_ros}
APP=${MOWBITE_CONTAINER:-mowbite}
PLANNER=${PLANNER_CONTAINER:-mowbite_planner}
# the labels a container is looked after by: mowbite.update=on, and mowbite.update.<key> for the rest
L=mowbite.update

# a container's compose label (project, project.working_dir, project.config_files, service)
label() { docker inspect -f "{{index .Config.Labels \"com.docker.compose.$2\"}}" "$1" 2>/dev/null; }
# a container's own setting for the updater (mowbite.update.<key>)
own() { docker inspect -f "{{index .Config.Labels \"$L.$2\"}}" "$1" 2>/dev/null; }
exists() { docker inspect "$1" > /dev/null 2>&1; }

# itself: by its name in compose.yaml, else by its id as its own mounts show it (on the host's network its hostname is the
# host's)
ME=${UPDATER_CONTAINER:-mowbite-updater}
# the helper of its own update (a test next to a real updater on the same docker: another name)
SELF=${UPDATER_SELF:-mowbite-updater-self}
# (its interface, asked every few seconds while its page is open, takes the folder it noted at its start: no docker)
if [ -n "$REQUEST_METHOD" ] && [ -z "$STATE_DIR" ] && [ -s /tmp/updater-state ]; then
  read -r STATE < /tmp/updater-state
else
  # (found by its id: then by its name, which stays when compose makes it anew)
  exists "$ME" || ME=$(docker inspect -f '{{.Name}}' "$(sed -n 's|.*/containers/\([0-9a-f]\{64\}\)/.*|\1|p' /proc/self/mountinfo 2>/dev/null | head -n1)" 2>/dev/null | sed 's|^/||')
  STATE=${STATE_DIR:-$(label "$ME" project.working_dir)/.updater}
fi
CONF=$STATE/conf
STATUS=$STATE/status
LOG=$STATE/log
REQ=$STATE/request
# the data kept before updates, on the mower only (mower_params.yaml has the ntrip login)
DATA=$STATE/data

now() { date +%s; }
up() { cut -d. -f1 /proc/uptime; }
log() {
  local tmp
  echo "$(date '+%F %T') $*" >> "$LOG"
  # a few hundred lines, nothing may grow
  if [ "$(wc -l < "$LOG")" -gt 400 ] && tmp=$(mktemp "$LOG.XXXXXX"); then
    if tail -n 300 "$LOG" > "$tmp"; then mv "$tmp" "$LOG"; else rm -f "$tmp"; fi
  fi
  # (callers chain on it: a log line never fails)
  return 0
}
# one line per value, the page gets them. no value: the key goes. written whole and moved in place, only when all of it
# got written (a full disk leaves the one there was)
status() {
  local key="$1" tmp
  shift
  [ -f "$STATUS" ] || : > "$STATUS"
  tmp=$(mktemp "$STATUS.XXXXXX") || return 0
  # (sed, not grep: busybox's grep doesn't say when it couldn't write)
  if sed "/^$key /d" "$STATUS" > "$tmp" 2> /dev/null && { [ $# -eq 0 ] || echo "$key $*" >> "$tmp"; } 2> /dev/null; then mv "$tmp" "$STATUS"; else rm -f "$tmp"; fi
}
get() { sed -n "s/^$1 //p" "$STATUS" 2>/dev/null | head -n1; }

# a container's stack the way dockge runs it, within $1 seconds: all its compose files and env files, from its folder
compose() {
  local t="$1" c="$2" l project dir files envs
  shift 2
  # (its labels in one go: project|folder|compose files|env files)
  l=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}|{{index .Config.Labels "com.docker.compose.project.environment_file"}}' "$c" 2>/dev/null)
  project=${l%%|*}
  l=${l#*|}
  dir=${l%%|*}
  l=${l#*|}
  files=${l%%|*}
  envs=${l#*|}
  # (paths with spaces don't happen in dockge's stacks)
  files=$(printf '%s' "$files" | tr ',' '\n' | sed '/./!d; s/^/-f /')
  envs=$(printf '%s' "$envs" | tr ',' '\n' | sed '/./!d' | while read -r f; do
    case $f in /*) echo "--env-file $f" ;; *) echo "--env-file $dir/$f" ;; esac
  done)
  # shellcheck disable=SC2086
  timeout "$t" docker compose -p "$project" --project-directory "$dir" $envs $files "$@"
}
in_compose() { [ -n "$(label "$1" project)" ] && [ -f "$(label "$1" project.config_files | cut -d, -f1)" ]; }
service() { label "$1" service; }

# a value as it was set, or the default. the file is only ever written by the cgi, which checks what goes in
conf() {
  v=$(sed -n "s/^$1 //p" "$CONF" 2>/dev/null | head -n1)
  echo "${v:-$2}"
}
valid() { printf '%s' "$1" | grep -Eq "^($2)\$"; }
TAG='[A-Za-z0-9][A-Za-z0-9._-]{0,63}'
# a release's version: 1.2.0, 1.2.0-beta.1
VERSION_RE='[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(-[0-9A-Za-z.]{1,32})?'
ID='[a-z][a-z0-9_]{0,40}'

# what a calibration may write into OpenMower's mower_params.yaml: its name for apps, the path of its keys, the unit
# and fixed bounds (not relative to the values before: the first calibration may be far off, and anyone on the network
# can ask). nothing else is ever written
CALIB='ticks_per_m ll/services/diff_drive/ticks_per_m ticks/m 100 10000
wheel_distance_m ll/services/diff_drive/wheel_distance_m m 0.15 0.80
antenna_offset_x xbot_positioning/antenna_offset_x m -0.60 0.60
antenna_offset_y xbot_positioning/antenna_offset_y m -0.30 0.30'
# lines "<path> <value>" of a request: each a path of the list, once, and a plain number within its bounds. the pairs on
# one line, 1 when one isn't like that or there's none
calib_valid() {
  awk -v list="$CALIB" '
    BEGIN { n = split(list, l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, " "); lo[f[2]] = f[4]; hi[f[2]] = f[5] } }
    NF == 0 { next }
    NF != 2 || !($1 in lo) || ($1 in seen) || $2 !~ /^-?[0-9]+(\.[0-9]+)?$/ || $2 + 0 < lo[$1] + 0 || $2 + 0 > hi[$1] + 0 { bad = 1; exit }
    { seen[$1] = 1; out = out (out == "" ? "" : " ") $1 " " $2 }
    END { if (bad || out == "") exit 1; print out }
  '
}

# the repository of an image reference (its tag or digest off)
repo_of() { printf '%s' "$1" | sed 's/@.*//; s/:[^:/]*$//'; }
digests() { docker image inspect -f '{{join .RepoDigests " "}}' "$1" 2>/dev/null; }
# all the digests it came with from repository $2 (one pushed under more tags has more), in one line
digests_in() { digests "$1" | tr ' ' '\n' | awk -F@ -v r="$2" '$1 == r {printf "%s%s", s, $2; s = " "}'; }

# the parts it looks after, as found at the last look (status "parts"): "<id>:<container>:<kind>" each
#   openmower  OpenMower: its image tag is VERSION in its stack's .env (edge, latest or its own)
#   image      a container from a registry: its tag pulled again, or the newest release (mowbite.update.stable)
#   build      a container built from a github context: built again when that moved or its base image changed
part_line() { get parts | tr ' ' '\n' | grep "^$1:"; }
box() { part_line "$1" | cut -d: -f2; }
kind() { part_line "$1" | cut -d: -f3; }
part_ids() { get parts | tr ' ' '\n' | cut -d: -f1 | grep .; }

# OpenMower's version as its .env says, the channel it's on when nothing else is set. read the way compose reads it:
# VERSION=edge, "edge", 'edge', with export in front or a comment after, windows line ends
om_env() { echo "$(label "$OM" project.working_dir)/.env"; }
om_version() {
  v=$({ tr -d '\r' < "$(om_env)"; } 2>/dev/null | sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}VERSION=//p' | head -n1 |
    sed 's/[[:space:]][[:space:]]*#.*//; s/^["'\'']//; s/["'\''][[:space:]]*$//; s/[[:space:]]*$//')
  valid "$v" "$TAG" && echo "$v"
}

# the channels: a part with releases beta or stable (the planner stable while none is set, its betas only for those who
# pick beta; the others beta), OpenMower edge, latest (its release) or what its .env has. automatic: 1 or 0 each
channel() {
  local d=beta
  [ "$1" = planner ] && d=stable
  [ "$(conf "$1" $d)" = stable ] && echo stable || echo beta
}
# (its interface takes the version of the .env as the updater noted it at its last look, the updater reads the file)
om_env_version() { if [ -n "$REQUEST_METHOD" ] && [ -n "$(get openmower_env)" ]; then get openmower_env; else om_version; fi; }
om_choices() { printf 'edge latest %s' "$(om_env_version)"; }
om_channel() {
  v=$(conf openmower "")
  case " $(om_choices) " in *" $v "*) [ -n "$v" ] && echo "$v" && return ;; esac
  v=$(om_env_version)
  echo "${v:-edge}"
}
auto() { [ "$(conf "$1_auto" 0)" = 1 ]; }
# the folders of the data kept, of part $1 or of all, newest first. $2: only those kept before an update (update) or
# before data was put back (put)
data_dirs() {
  local d
  printf '%s\n' "$DATA"/*-* | grep -E "/${1:-$ID}-[0-9]+\$" | awk -F- '{print $NF, $0}' | sort -nr |
    cut -d' ' -f2- | while IFS= read -r d; do
      [ -z "$2" ] || [ "$(cat "$d/why" 2> /dev/null)" = "$2" ] && echo "$d"
    done
}
