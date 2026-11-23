# shared by the updater (updater.sh), its own update (self.sh) and its interface (www/cgi-bin/updater): where things are,
# the settings, the status, the stacks, the parts. settings, status and log live in its own stack folder (.updater next
# to its compose.yaml): only it can write there, the page asks for them over http
OM=${OPENMOWER_CONTAINER:-open_mower_ros}
APP=${MOWBITE_CONTAINER:-mowbite}
PLANNER=${PLANNER_CONTAINER:-mowbite_planner}
# the labels a container is looked after by: mowbite.update=on, and mowbite.update.<key> for the rest
L=mowbite.update

# a container's compose label (project, project.working_dir, project.config_files, service), else as noted (gone_of)
label() {
  local v
  # (docker says an empty line for one that isn't there)
  if v=$(docker inspect -f "{{index .Config.Labels \"com.docker.compose.$2\"}}" "$1" 2>/dev/null); then echo "$v"; else gone_label "$1" "$2"; fi
}
# a container's compose labels in one go: project|folder|compose files|env files
COMPOSE_LABELS='{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}|{{index .Config.Labels "com.docker.compose.project.environment_file"}}'
# a container removed for OpenMower's update without a copy (gone_<part>): "<container> <image> <running|stopped> <its
# compose labels> <service> [<commit> <name> release|branch, what's built of it]"
gone_of() { awk -v c="$1" '$1 ~ /^gone_/ && $2 == c {sub(/^[^ ]* /, ""); print; exit}' "$STATUS" 2>/dev/null; }
gone() { [ -n "$(gone_of "$1")" ] && ! exists "$1"; }
# its notes, "gone_<part> <container>" a line
gone_list() { sed -n 's/^\(gone_[a-z0-9_]*\) \([^ ]*\) .*/\1 \2/p' "$STATUS" 2>/dev/null; }
gone_label() {
  local l n
  l=$(gone_of "$1")
  [ -n "$l" ] || return 1
  case $2 in
  service) echo "$l" | cut -d' ' -f5 && return ;;
  project) n=1 ;;
  project.working_dir) n=2 ;;
  project.config_files) n=3 ;;
  project.environment_file) n=4 ;;
  *) return 1 ;;
  esac
  echo "$l" | cut -d' ' -f4 | cut -d'|' -f"$n"
}
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
  tmp=$(mktemp "$STATUS.XXXXXX") || return 1
  # (sed, not grep: busybox's grep doesn't say when it couldn't write)
  if sed "/^$key /d" "$STATUS" > "$tmp" 2> /dev/null && { [ $# -eq 0 ] || echo "$key $*" >> "$tmp"; } 2> /dev/null; then mv "$tmp" "$STATUS"; else rm -f "$tmp"; return 1; fi
  # (the notes a stop halfway goes on from: on the disk before the step they're for)
  case $key in pending_* | changed_* | gone_* | nokeep_openmower | switch_os | os_drop | openmower_missing) sync ;; esac
}
get() { sed -n "s/^$1 //p" "$STATUS" 2>/dev/null | head -n1; }

# a container's stack the way dockge runs it, within $1 seconds: all its compose files and env files, from its folder
compose() {
  local t="$1" c="$2" l project dir files envs
  shift 2
  l=$(docker inspect -f "$COMPOSE_LABELS" "$c" 2>/dev/null) || l=$(gone_of "$c" | cut -d' ' -f4)
  project=${l%%|*}
  l=${l#*|}
  dir=${l%%|*}
  l=${l#*|}
  files=${l%%|*}
  envs=${l#*|}
  # (paths with spaces don't happen in dockge's stacks)
  files=$(printf '%s' "$files" | tr ',' '\n' | sed '/./!d; s/^/-f /')
  envs=$(printf '%s\n' "$envs" | tr ',' '\n' | sed '/./!d' | while read -r f; do
    case $f in /*) ;; *) f=$dir/$f ;; esac
    # (one it can't see left out: compose reads the folder's .env then)
    [ -f "$f" ] && echo "--env-file $f"
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
# the build part that runs as container $1
build_of() { get parts | tr ' ' '\n' | awk -F: -v c="$1" '$2 == c && $3 == "build" {print $1; exit}'; }
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

# a log as it may be shown: the given values out, the access in a url (user:password@) and what follows password,
# token, secret, a username or an api key with : or =, each as ***
redact() {
  # (through the environment: awk -v would read a backslash in one as an escape)
  SECRETS="$1" awk '
    function ci(w,   r, i, c, u, l) { r = ""; for (i = 1; i <= length(w); i++) { c = substr(w, i, 1); u = toupper(c); l = tolower(c); r = r (u != l ? "[" u l "]" : c) } return r }
    function lit(line, x,   out, p) { out = ""; while ((p = index(line, x)) > 0) { out = out substr(line, 1, p - 1) "***"; line = substr(line, p + length(x)) } return out line }
    BEGIN {
      n = split(ENVIRON["SECRETS"], s, "\n")
      # (up to the last @ before the host: a password can hold one)
      url = "://[^/@ :\"\047]+:[^ /\"\047]*@"
      kv = "(" ci("password") "|" ci("passwd") "|" ci("pwd") "|" ci("secret") "|" ci("token") "|" ci("username") "|" ci("api_key") "|" ci("apikey") ")[\"\047]?[ \t]*[:=][ \t]*[\"\047]?"
      val = "^[^\"\047 ,;}&]+"
    }
    {
      line = substr($0, 1, 1000)
      for (i = 1; i <= n; i++) if (length(s[i]) >= 3) line = lit(line, s[i])
      out = ""
      while (match(line, url)) { out = out substr(line, 1, RSTART + 2) "***:***@"; line = substr(line, RSTART + RLENGTH) }
      line = out line
      out = ""
      while (match(line, kv)) {
        head = substr(line, 1, RSTART + RLENGTH - 1)
        q = substr(head, length(head), 1)
        out = out head
        line = substr(line, RSTART + RLENGTH)
        # (in quotes: up to the closing one, spaces too)
        if (q == "\"" || q == "\047") { if (match(line, "^[^" q "]*")) line = "***" substr(line, RLENGTH + 1) }
        else if (match(line, val)) line = "***" substr(line, RLENGTH + 1)
      }
      print out line
    }'
}
