#!/bin/sh
# MowBite Updater: keeps the containers of an OpenMower mower up to date, one part after the other and only while the
# mower is idle in its dock. a container of its own, the only one with docker. the parts, found by themselves:
#   OpenMower       open_mower_ros, its tag from VERSION in its stack's .env: edge, latest (its release) or its own.
#                   on OpenMowerOS 3 there's no such container, OpenMower comes with the OS update there
#   MowBite         its image again, beta (:latest) or stable (the newest release without a dash)
#   MowBite Planner built again from its github context when that moved or OpenMower changed under it
#   OpenMower's apps xtech's (ghcr.io/xtech/openmower-app) and the OpenMowerApp, their images again
#   any container with the label mowbite.update=on: pulled again, or built again from github. with
#     mowbite.update.check (":8080/health" on the container, or a url) or mowbite.update.log (a line in its log) it
#     shows it runs, mowbite.update.gate=none updates it with the mower out, mowbite.update.stable=github:<owner>/<repo>
#     gives it a stable channel, mowbite.update.name its name
# it looks every 6 hours whether there's something new, updates a part when asked (its page, MowBite) and the automatic
# ones at the time and on the days set. a part counts as updated when it runs on its new image and answers, otherwise
# it goes back to what ran before and leaves that version out; restarted again only while OpenMower doesn't drive the
# mower. only with room to spare. all through the stacks' own compose files, so dockge shows the same, files changed
# keep owner and rights, only its own change is ever put back. stopped halfway (power gone), it puts back what it
# changed and looks again at what it had restarted, at its next start. images built here aren't replaced or deleted by
# itself. last the leftovers go: its older rollback tags, images nothing uses, the build cache. what it does right now
# goes to the status as progress, for the bars on its page
. /lib.sh
# rollback tags (rb-<time>-<image>) kept once all runs again: an app's are small, OpenMower's and builds' are GBs
KEEP=2
KEEP_BIG=0
CHECK_EVERY=21600
# the night's window: from the time set, retried every 10 minutes for 3 hours while the mower isn't in the dock
WINDOW=180
# MB free a part needs before it starts (OpenMower: its download x5 and 1 GB more)
ROOM_APP=300
ROOM_BUILD=800
# seconds anything over the network or with docker may take, so nothing hangs for good
T_REGISTRY=60
T_PULL=1800
T_UP=300
T_BUILD=900

alive() { status alive "$(now)"; }

# --- the mower ---

# the mower as OpenMower says it right now over mqtt (nothing the broker kept from before): "1" idle in the dock, else
# "0 <state>" (MOWING, IDLE out of the dock or with the dock's power gone, unknown while OpenMower doesn't answer),
# nothing when there's no broker to ask
mqtt() {
  local t="$1"
  set -- -h "${MQTT_HOST:-127.0.0.1}" -p "${MQTT_PORT:-1883}"
  [ -n "$MQTT_USER" ] && set -- "$@" -u "$MQTT_USER" -P "$MQTT_PASSWORD"
  timeout 10 mosquitto_sub "$@" -t "${MQTT_PREFIX}$t" -R -C 1 -W 6 2> /dev/null
}
mower() {
  local s rc state charging
  s=$(mqtt robot_state/json)
  rc=$?
  # (27: nothing came in time, the broker is there but OpenMower doesn't answer)
  if [ -z "$s" ]; then
    [ $rc -eq 27 ] && echo "0 unknown"
    return 0
  fi
  state=$(printf '%s' "$s" | sed -n 's/.*"current_state": *"\([A-Z_]*\)".*/\1/p')
  charging=$(printf '%s' "$s" | sed -n 's/.*"is_charging": *\([a-z0-9]*\).*/\1/p')
  if [ "$state" = IDLE ]; then
    case $charging in 1 | true) echo 1 && return 0 ;; esac
    # a full battery stops charging, the contacts' voltage still says it's in the dock
    awk -v v="$(mqtt sensors/om_v_charge/data)" 'BEGIN {exit !(v + 0 >= 20)}' && echo 1 && return 0
  fi
  echo "0 ${state:-unknown}"
}
docked() { [ "$(mower)" = 1 ]; }
# OpenMower doesn't drive the mower: idle, in the dock or not, or no answer from it at all. no broker: no telling, so not
quiet() { case $(mower) in 1 | "0 IDLE" | "0 unknown") return 0 ;; *) return 1 ;; esac; }
# OpenMowerOS 3: open_mower_ros is part of the os there, updated with it (openmower update-os)
new_os() { grep -qx 'ID=openmower-os' /host/os-release 2> /dev/null; }

# --- containers and images ---

image_of() { docker inspect -f '{{.Image}}' "$1" 2>/dev/null; }
ref_of() { docker inspect -f '{{.Config.Image}}' "$1" 2>/dev/null; }
id_of() { docker image inspect -f '{{.Id}}' "$1" 2>/dev/null; }
# (a container waiting for its next restart counts as running for docker, not here)
running() { [ "$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" = running ]; }
day_of() { docker image inspect -f '{{.Created}}' "$1" 2>/dev/null | cut -c1-10; }
# the commit an image was built from, as its labels say (ci's images have it), first 7
rev_of() { docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$1" 2>/dev/null | cut -c1-7; }
digests() { docker image inspect -f '{{join .RepoDigests " "}}' "$1" 2>/dev/null; }
# the digests the registry knows the image of a container by: its repo digests, and its id (with containerd's image
# store that is the registry's digest itself, and an image replaced under its tag has no repo digests any more)
known_as() { printf '%s @%s' "$(digests "$1")" "$1"; }
# the same content: the same layers and settings (built again, an image gets another id, its record of the build differs)
same() {
  local a
  [ "$1" = "$2" ] && return 0
  a=$(docker image inspect -f '{{json .RootFS.Layers}} {{json .Config}}' "$1" 2>/dev/null) || return 1
  [ -n "$a" ] && [ "$a" = "$(docker image inspect -f '{{json .RootFS.Layers}} {{json .Config}}' "$2" 2>/dev/null)" ]
}
# a registry's digest of image:tag, empty when it can't be had
remote_digest() { timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>/dev/null; }
# an image built or loaded here, one its registry doesn't have: it can't be downloaded again. (with containerd's image
# store a build here has a repo digest too, its own id.) no answer from the registry counts the same: not touched
built_here() {
  case $(docker image inspect -f '{{len .RepoDigests}}' "$1" 2>/dev/null) in "") return 1 ;; 0) return 0 ;; esac
  for d in $(digests "$1"); do
    timeout $T_REGISTRY docker buildx imagetools inspect "$d" --format '{{.Manifest.Digest}}' > /dev/null 2>&1 && return 1
  done
  return 0
}
# a text as a sed pattern
re() { printf '%s' "$1" | sed 's/[][\.*^$/|]/\\&/g'; }
# MB free where docker keeps its images: its own folder, the stacks and docker share a disk on OpenMowerOS
free_mb() { df -Pm "$STATE" 2>/dev/null | awk 'NR == 2 {print $4}'; }
room_for() {
  f=$(free_mb)
  [ -n "$f" ] && [ "$f" -ge "$1" ]
}
# the file of a container's stack that names its image
stackfile() {
  for f in $(label "$1" project.config_files | tr ',' ' '); do
    grep -q "^[[:space:]]*image:[[:space:]]*$(re "$2")[[:space:]]*\$" "$f" 2>/dev/null && echo "$f" && return
  done
}
# a build's context and its base image (a build argument with IMAGE in its name), from its stack's compose config
context_of() { compose $T_REGISTRY "$1" config "$(service "$1")" 2>/dev/null | sed -n 's/^ *context: *//p' | head -n1; }
base_of() { compose $T_REGISTRY "$1" config "$(service "$1")" 2>/dev/null | sed -n 's/^ *[A-Z_]*IMAGE[A-Z_]*: *//p' | tr -d '"' | head -n1; }
# owner/repo and the branch of a github context, empty for anything else
source_of() {
  printf '%s' "$(context_of "$1")" | sed -n 's|^https://github\.com/\([A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*\)\.git\(#\([A-Za-z0-9_./-]*\)\)\{0,1\}$|\1 \3|p'
}

# --- the parts ---

# what's there to look after, written to the status: "<id>:<container>:<kind> ...", the name of each (<id>_name).
# kind build: from a github context, local: built from a copy here (left as it is), image: from a registry
kind_of() {
  if [ -n "$(source_of "$1")" ]; then
    echo build
  # (a stack with image: and build: . both, like MowBite's, is from its registry as long as that has its tag)
  elif [ -n "$(context_of "$1")" ] && [ -z "$(remote_digest "$(ref_of "$1")")" ]; then
    echo local
  else
    echo image
  fi
}
# a running container it would look after but can't reach: "<container>@<its stack's folder>" (- when it wasn't
# started from a compose file), for its page to say why it's missing
away() { running "$1" && printf ' %s@%s' "$1" "$(label "$1" project.working_dir | grep . || echo -)"; }
# the folders it reaches, as mounted into it (the stacks' folder, by default /opt/stacks)
reach() { docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$ME" 2>/dev/null | tr ' ' '\n' | grep -vE '^(/var/run/docker\.sock|/etc/localtime|/host/.*|)$' | tr '\n' ' '; }
find_parts() {
  local out="" c x id far="" picked cand
  if exists "$OM" && in_compose "$OM"; then
    out="openmower:$OM:openmower"
  elif new_os; then
    out="openmower:-:os"
  elif exists "$OM"; then
    far="$far$(away "$OM")"
  fi
  status openmower_name OpenMower
  status openmower_gate mower
  # the apps of OpenMower's stack, by their images: xtech's app and the OpenMowerApp
  for c in $(docker ps -a --format '{{.Names}}'); do
    case $(repo_of "$(ref_of "$c")") in
    ghcr.io/xtech/openmower-app) id=xtechapp ;;
    ghcr.io/clemenselflein/openmowerapp) id=openmowerapp ;;
    *) continue ;;
    esac
    case " $out " in *" $id:"*) continue ;; esac
    in_compose "$c" || { far="$far$(away "$c")"; continue; }
    out="$out $id:$c:image"
    status "${id}_gate" mower
  done
  status xtechapp_name "OpenMower App (xtech)"
  status openmowerapp_name OpenMowerApp
  for c in "$APP" "$PLANNER"; do
    exists "$c" || continue
    in_compose "$c" || { far="$far$(away "$c")"; continue; }
    if [ "$c" = "$APP" ]; then id=mowbite; else id=planner; fi
    out="$out $id:$c:$(kind_of "$c")"
    status "${id}_gate" mower
  done
  status mowbite_name MowBite
  status planner_name "MowBite Planner"
  # the apps labelled mowbite.update=on, and the ones picked on its page (conf picked). (picked ones said anew each time)
  picked=" $(conf picked none | tr ',' ' ') "
  sed -n 's/^\(c_[a-z0-9_]*_picked\) .*/\1/p' "$STATUS" 2>/dev/null | while read -r x; do status "$x"; done
  for c in $({
    docker ps -a --filter "label=$L=on" --format '{{.Names}}'
    for x in $picked; do exists "$x" && echo "$x"; done
  } | awk '!seen[$0]++'); do
    case $c in "$OM" | "$APP" | "$PLANNER" | "$ME") continue ;; esac
    in_compose "$c" || { far="$far$(away "$c")"; continue; }
    id=c_$(echo "$c" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_' | cut -c1-30)_$(printf '%s' "$c" | md5sum | cut -c1-4)
    out="$out $id:$c:$(kind_of "$c")"
    status "${id}_name" "$(own "$c" name | tr -d '\n' | cut -c1-40 | grep . || echo "$c")"
    if [ "$(own "$c" gate)" = none ]; then status "${id}_gate" none; else status "${id}_gate" mower; fi
    # (picked, not labelled: it can be taken out on its page again)
    case $picked in *" $c "*) [ "$(docker inspect -f "{{index .Config.Labels \"$L\"}}" "$c" 2>/dev/null)" = on ] || status "${id}_picked" yes ;; *) status "${id}_picked" ;; esac
  done
  # what can be picked: the other running containers of the stacks it reaches
  cand=""
  for c in $(docker ps --format '{{.Names}}'); do
    case " $out " in *":$c:"*) continue ;; esac
    case $c in "$ME" | mowbite-updater-self) continue ;; esac
    in_compose "$c" && cand="$cand $c"
  done
  # shellcheck disable=SC2086
  status parts $out
  # shellcheck disable=SC2086
  status unreachable $far
  # shellcheck disable=SC2086
  status candidates $cand
  # shellcheck disable=SC2046
  status reach $(reach)
}
# only while the mower is idle in the dock (gate mower), or whenever (gate none: mowbite.update.gate=none)
gate() { [ "$(get "$1_gate")" = none ] && echo none || echo mower; }
# how a part shows it runs: mqtt (OpenMower: a fresh state from it), log:<line> (in its log since it started),
# http:<url> (answers, ":port/path" on the container), health (docker's own healthcheck), up (half a minute without
# a restart). from its labels, else what's known of it
check_of() {
  local c v
  [ "$(kind "$1")" = openmower ] && echo mqtt && return
  c=$(box "$1")
  v=$(own "$c" log | tr -d '\n')
  [ -n "$v" ] && echo "log:$v" && return
  v=$(own "$c" check)
  [ -n "$v" ] && echo "http:$v" && return
  case $1 in
  mowbite) echo "http::8080/cgi-bin/version" && return ;;
  planner) echo "log:MowBite Planner answers" && return ;;
  xtechapp) echo "http::3000/" && return ;;
  esac
  v=$(docker inspect -f '{{if .Config.Healthcheck}}{{index .Config.Healthcheck.Test 0}}{{end}}' "$c" 2>/dev/null)
  [ -n "$v" ] && [ "$v" != NONE ] && echo health && return
  echo up
}
# a check's address: ":port/path" on the container's own address (or here, on the host's network)
url_of() {
  case $2 in
  :*)
    if [ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$1" 2>/dev/null)" = host ]; then
      echo "http://127.0.0.1$2"
    else
      ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" 2>/dev/null | awk '{print $1}')
      # (no address of its own: nothing to ask, the check fails)
      [ -n "$ip" ] && echo "http://$ip$2"
    fi
    ;;
  *) echo "$2" ;;
  esac
}
# a part's stable channel: the newest github release that isn't a pre-release, as its image's tag
stable_source() {
  local v
  v=$(own "$(box "$1")" stable)
  [ -z "$v" ] && [ "$1" = mowbite ] && [ "$(ref_of "$(box "$1")" | sed 's/:[^:/]*$//')" = ghcr.io/mkaaaaaay/mowbite ] && v=github:mkaaaaaay/mowbite
  printf '%s' "$v" | sed -n 's|^github:\([A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*\)$|\1|p'
}
stable_tag() {
  local src v
  src=$(stable_source "$1")
  [ -n "$src" ] || return
  # (where github sends /releases/latest, not its api: no limit of 60 an hour)
  v=$(wget -S --spider -T 15 "https://github.com/$src/releases/latest" 2>&1 | sed -n 's|^ *Location: .*/releases/tag/v\{0,1\}\([^[:space:]?]*\).*|\1|p' | tail -n1)
  valid "$v" "$TAG" && echo "$v"
}
# the repository of an image reference (its tag off)
repo_of() { printf '%s' "$1" | sed 's/:[^:/]*$//'; }

# --- files of the stacks ---

# a file of a part's stack changed by a sed expression: kept once as it was (.before-update), written whole and moved in
# place, with the owner and the rights it had, never through a link. what it wrote is noted (changed_<part> <file>
# <md5>), so only that change is ever put back. 1: nothing changed
change_file() {
  local tmp
  [ -f "$2" ] && [ ! -L "$2" ] || return 1
  tmp=$(mktemp "$2.XXXXXX") || return 1
  if cp -p "$2" "$tmp" && mv "$tmp" "$2.before-update" && tmp=$(mktemp "$2.XXXXXX") && sed "$3" "$2" > "$tmp" &&
    chown "$(stat -c %u:%g "$2")" "$tmp" && chmod "$(stat -c %a "$2")" "$tmp" && mv "$tmp" "$2"; then
    status "changed_$1" "$2" "$(md5sum < "$2" | cut -d' ' -f1)"
    return 0
  fi
  rm -f "$tmp"
  return 1
}
# a part's change put back (the file as it was, moved in place whole), or kept for good. either way the copy goes
undo_change() {
  local tmp
  # shellcheck disable=SC2046
  set -- "$1" $(get "changed_$1")
  [ -n "$2" ] && [ -f "$2.before-update" ] && [ ! -L "$2" ] || return 0
  tmp=$(mktemp "$2.XXXXXX") || return 1
  if cp -p "$2.before-update" "$tmp" && mv "$tmp" "$2"; then
    log "$1: $2 back as it was"
    keep_change "$1"
    return 0
  fi
  rm -f "$tmp"
  return 1
}
keep_change() {
  # shellcheck disable=SC2046
  set -- "$1" $(get "changed_$1")
  [ -n "$2" ] && rm -f "$2.before-update"
  status "changed_$1"
}

# --- images kept to go back to ---

# the image a part ran before, kept under a tag of its own
keep_back() {
  t=$1:rb-$(now)-$(echo "$2" | sed 's/^sha256://' | cut -c1-8)
  docker tag "$2" "$t" && echo "$t"
}
# nothing changed after all: the tag back on the image kept, the rollback tag made for it gone
undo_back() {
  docker tag "$1" "$2" 2> /dev/null
  docker rmi "$1" > /dev/null 2>&1
}

# --- the progress, for the bars ---

# what it does right now: "<part> <step> <percent or -> <since> [<done> <of>]", the step's start kept while it lasts.
# steps: prepare, download, extract, build, restart, wait, back
progress() {
  local p since
  p=$(get progress)
  case $p in "$1 $2 "*) since=$(echo "$p" | cut -d' ' -f4) ;; *) since=$(now) ;; esac
  # shellcheck disable=SC2086
  status progress "$1" "$2" "${3:--}" "$since" $4 $5
  alive
}
# compose's progress as json (docker pull shows none off a terminal), a step and its percent a line when they change:
# a pull's bytes of the layers it fetches (their sizes from the file "sizes" when known), then the layers unpacked, a
# build's steps. what compose says besides goes to the log, of a failed build the end of its output too. last
# "@exit <compose's exit code>"
progress_awk='
BEGIN { while ((getline l < sizes) > 0) { split(l, f, " "); size[f[1]] = f[2] + 0 } close(sizes) }
function val(k) { if (!match($0, "\"" k "\":\"[^\"]*\"")) return ""; return substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5) }
function num(k) { if (!match($0, "\"" k "\":[0-9]+")) return 0; return substr($0, RSTART + length(k) + 3, RLENGTH - length(k) - 3) + 0 }
function say(line) { if (line != last) { print line; fflush(); last = line } }
/^@exit / { rc = $2; next }
!/^\{/ { if ($0 != "") print >> logf; next }
/"error":true/ { m = $0; sub(/.*"message":"/, "", m); sub(/"\}[[:space:]]*$/, "", m); gsub(/\\n/, "\n", m); gsub(/\\"/, "\"", m); gsub(/\\u0026/, "\\&", m); gsub(/\\u003c/, "<", m); gsub(/\\u003e/, ">", m); print m >> logf; next }
/"status":"Error"/ { print val("id") ": " val("text") " " val("details") >> logf; next }
/"parent_id":"/ {
  id = val("id"); t = val("text"); seen[id] = 1
  if (t == "Already exists") had[id] = 1
  else if (t == "Downloading") { got[id] = num("current"); if (!size[id]) size[id] = num("total") }
  else if (t == "Download complete" || t == "Verifying Checksum" || t == "Extracting") fetched[id] = 1
  else if (t == "Pull complete") { fetched[id] = 1; unpacked[id] = 1 }
  n = 0; f = 0; u = 0; all = 0; have = 0; ub = 0
  for (l in seen) {
    if (had[l]) continue
    n++; all += size[l]
    if (fetched[l]) { f++; have += size[l] } else have += got[l] < size[l] ? got[l] : size[l]
    if (unpacked[l]) { u++; ub += size[l] }
  }
  if (!n) next
  if (f < n) say("download " (all ? int(100 * have / all) : "-"))
  else say("extract " (all ? int(100 * ub / all) : int(100 * u / n)) " " u " " n)
  next
}
/"vertexes"/ {
  k = split($0, v, /\{"digest":"/)
  for (i = 2; i <= k; i++) {
    d = substr(v[i], 1, index(v[i], "\"") - 1)
    if (v[i] ~ /"name":"\[[^]]* [0-9]+\/[0-9]+\]/) step[d] = 1
    if (v[i] ~ /"completed":"/ || v[i] ~ /"cached":true/) done[d] = 1
  }
  s = 0; c = 0
  for (d in step) { s++; if (done[d]) c++ }
  if (s) say("build " int(100 * c / s) " " c " " s)
  next
}
/"logs"/ { k = split($0, v, /"data":"/); for (i = 2; i <= k; i++) { out++; tail[out % 40] = substr(v[i], 1, index(v[i], "\"") - 1) } next }
END {
  if (rc != 0) for (i = (out > 40 ? out - 39 : 1); i <= out; i++) { cmd = "base64 -d >> \"" logf "\" 2>/dev/null"; print tail[i % 40] | cmd; close(cmd) }
  print "@exit " (rc + 0)
}'
# a compose pull or build ($3...) with the progress of part $1: compose's exit code, 2 when the mower left the dock
# meanwhile, for a part that waits for the dock (compose is stopped then: a build takes the mower's cpu)
with_progress() {
  local part="$1" g="$2" watch rc
  shift 2
  rm -f "$STATE/left"
  if [ "$g" = mower ]; then
    (while sleep 30; do docked || { : > "$STATE/left"; pkill -f -- '--progress json'; exit 0; }; done) &
    watch=$!
  fi
  { "$@" 2>&1; echo "@exit $?"; } | awk -v sizes="$STATE/layers" -v logf="$LOG" "$progress_awk" | (
    rc=1
    while read -r w a b c; do
      if [ "$w" = @exit ]; then rc=$a; else progress "$part" "$w" "$a" "$b" "$c"; fi
    done
    exit "$rc"
  )
  rc=$?
  [ -n "$watch" ] && kill "$watch" 2> /dev/null
  if [ -f "$STATE/left" ]; then
    rm -f "$STATE/left"
    log "$part: stopped, the mower left the dock"
    return 2
  fi
  return $rc
}
# an image pulled through compose, for its progress: a project of its own that only names it, nothing is created
pull_image() {
  printf 'services:\n  pull:\n    image: "%s"\n' "$1" | timeout $T_PULL docker compose -p mowbite-updater-pull --project-directory "$STATE" -f - --progress json pull
}

arch() { case $(uname -m) in aarch64 | arm64) echo arm64 ;; *) echo amd64 ;; esac; }
# the layers of the newest image of ref for this machine, as compose's progress names them: "<first 12 of the digest>
# <packed bytes>" a line, in the image's order. nothing when it can't be had
layers() {
  dg=$(timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format "{{range .Manifest.Manifests}}{{if and (eq .Platform.Architecture \"$(arch)\") (eq .Platform.OS \"linux\")}}{{.Digest}}{{end}}{{end}}" 2>/dev/null)
  # (an image for one platform only has no list to pick from: its own manifest)
  timeout $T_REGISTRY docker buildx imagetools inspect --raw "$(repo_of "$1")@${dg:-$(remote_digest "$1")}" 2>/dev/null | awk '
    BEGIN { RS = "{" }
    /"mediaType" *: *"[^"]*(layer|rootfs)/ && match($0, /"digest" *: *"sha256:[0-9a-f]+"/) {
      d = substr($0, RSTART, RLENGTH); sub(/.*sha256:/, "", d)
      if (match($0, /"size" *: *[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); print substr(d, 1, 12), s }
    }'
}

# the MB the newest image of ref needs that the local image doesn't have yet: its missing layers, packed size x5.
# nothing when any of it can't be had: then there's no telling, and that's no room. its layers from the file $3 when
# they were just looked up
need_mb() {
  have=$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$2" 2>/dev/null)
  ids=$(mktemp)
  sizes=$(mktemp)
  # (an image for one platform only has no list of platforms to pick from)
  { timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format "{{json (index .Image \"linux/$(arch)\").RootFS.DiffIDs}}" 2>/dev/null ||
    timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{json .Image.RootFS.DiffIDs}}' 2>/dev/null; } | tr -d '[]" ' | tr ',' '\n' | grep . > "$ids"
  if [ -s "${3:-}" ]; then cut -d' ' -f2 "$3"; else layers "$1" | cut -d' ' -f2; fi > "$sizes"
  if [ -s "$ids" ] && [ "$(wc -l < "$ids")" -eq "$(wc -l < "$sizes")" ]; then
    paste -d' ' "$ids" "$sizes" | awk -v have=" $have " '{ if (index(have, " " $1 " ") == 0) s += $2 } END { printf "%d\n", s * 5 / 1048576 }'
  fi
  rm -f "$ids" "$sizes"
}

# whether there's something new for a part's container: no, yes, switch (another channel picked), failed (the new one
# didn't start before, left out), local (an image built here, not from the registry: only updated when asked) or unknown
available() {
  cur=$(ref_of "$2")
  img=$(image_of "$2")
  remote=$(remote_digest "$3")
  if built_here "$img"; then
    s=local
  elif [ -z "$remote" ]; then
    s=unknown
  elif known_as "$img" | grep -q "@$remote"; then
    s=no
  elif [ "$remote" = "$(get "$1_failed")" ]; then
    s=failed
  elif [ "$cur" != "$3" ]; then
    s=switch
  else
    s=yes
  fi
  status "$1_available" "$s" "$3"
}

# --- starting a part and seeing it run ---

# a part started on what its tag says now, then seen running on the image $2 and answering (check_of), within two
# minutes, a built one within five, OpenMower within six. 1 when compose can't start it or it doesn't answer. never
# built here: the image is there already (pulled, built or the one before), a planner with pull_policy: build would
# be built once more and run on an image nobody checked
restart() {
  local force=
  progress "$1" restart
  # (one that runs an image that isn't there any more is made anew: compose takes it for the same and leaves it)
  docker image inspect "$(image_of "$(box "$1")")" > /dev/null 2>&1 || force=1
  compose $T_UP "$(box "$1")" up -d --no-deps --no-build ${force:+--force-recreate} "$(service "$(box "$1")")" >> "$LOG" 2>&1 || { log "$1: compose couldn't start it"; return 1; }
  seen "$1" "$2"
}
seen() {
  local c end ok how started s
  c=$(box "$1")
  how=$(check_of "$1")
  # (a healthcheck may take a while between its tries)
  case $(kind "$1"):$how in openmower:*) end=360 ;; build:* | *:health) end=300 ;; *) end=120 ;; esac
  end=$(($(now) + end))
  ok=0
  started=
  while [ "$(now)" -lt "$end" ]; do
    sleep 10
    progress "$1" wait
    if [ "$(image_of "$c")" = "$2" ] && running "$c"; then
      case $how in
      mqtt) case $(mower) in 1 | "0 "[A-Z]*) ok=$((ok + 1)) ;; *) ok=0 ;; esac ;;
      log:*) docker logs --since "$(docker inspect -f '{{.State.StartedAt}}' "$c")" "$c" 2>&1 | grep -qF -- "${how#log:}" && return 0 ;;
      http:*) wget -q -T 5 -O /dev/null "$(url_of "$c" "${how#http:}")" 2> /dev/null && return 0 ;;
      health) [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)" = healthy ] && return 0 ;;
      up)
        s=$(docker inspect -f '{{.State.StartedAt}} {{.RestartCount}}' "$c")
        if [ "$s" = "$started" ]; then ok=$((ok + 1)); else started=$s; ok=0; fi
        [ $ok -ge 3 ] && return 0
        ;;
      esac
      [ "$how" = mqtt ] && [ $ok -ge 2 ] && return 0
    else
      ok=0
    fi
  done
  return 1
}

# the new version of a part didn't run: back to the one before ($2, a rollback tag) under its tag ($3), the file it
# changed put back, started again. OpenMower and builds only while OpenMower doesn't drive the mower, else left for
# the next run to look at (1). the version left out from now on ($4)
# whatever the mower does, it may be started again: an app only to look at, or one set to update with the mower out
harmless() { case $1 in mowbite | xtechapp | openmowerapp) return 0 ;; esac; [ "$(gate "$1")" = none ]; }
go_back() {
  if ! harmless "$1" && ! quiet; then
    log "$1: didn't run as it should, but the mower isn't idle (or there's no broker): nothing restarted, looked at again next time"
    status "$1" unconfirmed
    return 1
  fi
  log "$1: didn't run as it should, back to $2"
  progress "$1" back
  [ -n "$4" ] && status "$1_failed" "$4"
  docker tag "$2" "$3"
  undo_change "$1"
  if restart "$1" "$(id_of "$2")"; then status "$1" rolled_back; else status "$1" error rollback; fi
  status "pending_$1"
  return 0
}

# the parts restarted on a new version and not seen running yet (a run stopped right then, or the mower wasn't idle):
# started if a restart was cut off, then seen running, or back to the one before
settle() {
  for p in $(part_ids); do
    # (pending: the rollback tag, the tag it goes back under, the image it has to run on, what's left out when it doesn't)
    # shellcheck disable=SC2046
    set -- $(get "pending_$p")
    [ -n "$1" ] || continue
    if ! harmless "$p" && ! quiet; then
      log "$p: still to be seen running, the mower isn't idle, later"
      continue
    fi
    log "$p: was restarted on a new version and not seen running, looking now"
    if restart "$p" "${3:-$(id_of "$2")}"; then
      log "$p: runs"
      keep_change "$p"
      status "pending_$p"
      status "$p" updated "$(now)"
    else
      go_back "$p" "$1" "$2" "${4:-$(id_of "$2")}"
    fi
  done
  status progress
}

# --- an image from a registry ---

# whether version $1 is older than $2 (1.3.0 before 1.4.0-beta.14 before 1.4.0): part by part, a pre-release before its
# release. no when either isn't a version like that
older() {
  awk -v a="$1" -v b="$2" '
    function cmp(x, y,   xa, ya, xp, yp, nx, ny, n, i) {
      xp = index(x, "-") ? substr(x, index(x, "-") + 1) : ""; yp = index(y, "-") ? substr(y, index(y, "-") + 1) : ""
      sub(/-.*/, "", x); sub(/-.*/, "", y)
      nx = split(x, xa, "."); ny = split(y, ya, "."); n = nx > ny ? nx : ny
      for (i = 1; i <= n; i++) if (xa[i] + 0 != ya[i] + 0) return xa[i] + 0 < ya[i] + 0 ? -1 : 1
      if (xp == yp) return 0
      if (xp == "") return 1
      if (yp == "") return -1
      nx = split(xp, xa, "."); ny = split(yp, ya, "."); n = nx > ny ? nx : ny
      for (i = 1; i <= n; i++) {
        if (xa[i] == ya[i]) continue
        if (xa[i] ~ /^[0-9]+$/ && ya[i] ~ /^[0-9]+$/) return xa[i] + 0 < ya[i] + 0 ? -1 : 1
        return xa[i] < ya[i] ? -1 : 1
      }
      return 0
    }
    BEGIN {
      v = "^[0-9]+([.][0-9]+)*(-[0-9A-Za-z.-]+)?$"
      exit !(a ~ v && b ~ v && cmp(a, b) < 0)
    }'
}

check_image() {
  local c repo target st
  c=$(box "$1")
  repo=$(repo_of "$(ref_of "$c")")
  status "$1_running" "$(version_of "$1")" "$(day_of "$(image_of "$c")")"
  if [ -n "$(stable_source "$1")" ]; then
    st=$(stable_tag "$1")
    if [ -n "$st" ]; then status "$1_stable" yes; else status "$1_stable" no; fi
  else
    status "$1_stable"
  fi
  if [ -n "$(newest_back "$repo" "$(image_of "$c")")" ]; then status "$1_back" yes; else status "$1_back" no; fi
  target=$(image_target "$1")
  # stable older than what runs (a beta after the last release): nothing to go to, it stays until a newer stable
  if [ "$(channel "$1")" = stable ] && [ -n "$st" ] && older "$st" "$(version_of "$1")"; then
    status "$1_available" no "$target"
    status "$1_stable_older" "$st"
    return
  fi
  status "$1_stable_older"
  if [ -n "$target" ]; then available "$1" "$c" "$target"; else status "$1_available" unknown none; fi
}
# what a part runs in words: MowBite's own version, else its image's tag
version_of() {
  local v
  if [ "$1" = mowbite ]; then
    v=$(wget -q -T 5 -O - "$(url_of "$(box "$1")" :8080/cgi-bin/version)" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    [ -n "$v" ] && echo "$v" && return
  fi
  ref_of "$(box "$1")" | sed 's/.*://'
}
# the tag it goes to: on stable the newest release, on beta its own tag (the one it had before stable, MowBite's is
# :latest), without releases the one it has
image_target() {
  local c ref v
  c=$(box "$1")
  ref=$(ref_of "$c")
  if [ -z "$(stable_source "$1")" ]; then
    echo "$ref"
  elif [ "$(channel "$1")" = stable ]; then
    v=$(stable_tag "$1")
    [ -n "$v" ] && echo "$(repo_of "$ref"):$v"
  elif [ "$1" = mowbite ]; then
    echo "$(repo_of "$ref"):latest"
  else
    v=$(get "$1_beta")
    echo "${v:-$ref}"
  fi
}
# a part's newest rollback tag on another image than the one that runs ($2), to go back to by hand
newest_back() {
  docker images --no-trunc --format '{{.Tag}} {{.ID}}' "$1" | grep '^rb-[0-9]*-' | sort -t- -k2,2nr | while read -r t id; do
    [ "$id" = "$2" ] || { echo "$t"; break; }
  done
}

update_image() {
  local p="$1" c current repo before target back pulled file v need
  c=$(box "$p")
  progress "$p" prepare
  running "$c" || { log "$p: not running, left as it is"; status "$p" stopped; return 0; }
  current=$(ref_of "$c")
  repo=$(repo_of "$current")
  before=$(image_of "$c")
  # (asked for, it's the same either way: no need to ask the registry)
  if [ -z "$MANUAL" ] && built_here "$before"; then
    log "$p: runs an image built here, left as it is (only updated when asked)"
    status "$p" local
    return 0
  fi
  target=$(image_target "$p")
  [ -n "$target" ] || { log "$p: no stable release"; status "$p" error no_stable; return 1; }
  # never back to an older version by picking stable: that one stays until a newer stable is out
  if [ "$(channel "$p")" = stable ] && older "${target##*:}" "$(version_of "$p")"; then
    log "$p: stable ${target##*:} is older than $(version_of "$p") that runs, it stays as it is"
    status "$p" stable_older "${target##*:}"
    return 0
  fi
  # room for what it has to download (its missing layers x5, else as much as the image that runs) and some to spare.
  # (the layers looked up once: for the room and the bar)
  layers "$target" > "$STATE/layers"
  need=$(need_mb "$target" "$before" "$STATE/layers")
  [ -n "$need" ] || need=$(($(docker image inspect -f '{{.Size}}' "$before" 2>/dev/null || echo 0) / 1048576))
  room_for $((need + ROOM_APP)) || { log "$p: not enough room (needs $need MB and $ROOM_APP to spare, $(free_mb) MB free), nothing changed"; status "$p" nospace "$need" "$(free_mb)"; return 1; }
  # kept before anything moves its tag (an image only built here is gone once its tag is on another one)
  back=$(keep_back "$repo" "$before")
  [ -n "$back" ] || { log "$p: the version before can't be kept, nothing changed"; status "$p" error keep; return 1; }
  with_progress "$p" "$(gate "$p")" pull_image "$target"
  case $? in
  0) ;;
  2) undo_back "$back" "$current" && return 2 ;;
  *) log "$p: pull of $target failed"; undo_back "$back" "$current"; status "$p" error pull; return 1 ;;
  esac
  pulled=$(id_of "$target")
  if [ "$pulled" = "$before" ] && [ "$target" = "$current" ]; then
    undo_back "$back" "$current"
    status "$p" current
    # (its card right away, not only after the next look)
    status "${p}_available" no "$target"
    return 0
  fi
  if [ "$pulled" = "$(get "${p}_failed")" ]; then
    log "$p: not again, $target didn't start before"
    undo_back "$back" "$current"
    status "$p" skipped_failed
    return 0
  fi
  log "$p: kept the version before as $back"
  if [ "$target" != "$current" ]; then
    # (the tag it had before stable, to come back to on beta)
    [ "$(channel "$p")" = stable ] && [ -z "$(get "${p}_beta")" ] && status "${p}_beta" "$current"
    [ "$(channel "$p")" = beta ] && status "${p}_beta"
    file=$(stackfile "$c" "$current")
    if [ -z "$file" ] || ! change_file "$p" "$file" "s|^\([[:space:]]*image:[[:space:]]*\)$(re "$current")[[:space:]]*\$|\1$target|"; then
      log "$p: the compose file can't be changed, nothing changed"
      undo_back "$back" "$current"
      status "$p" error compose
      return 1
    fi
    if ! grep -q "^[[:space:]]*image:[[:space:]]*$(re "$target")[[:space:]]*\$" "$file"; then
      log "$p: the compose file didn't take the new image, nothing changed"
      undo_change "$p"
      undo_back "$back" "$current"
      status "$p" error compose
      return 1
    fi
  fi
  # the last word before it restarts
  if [ "$(gate "$p")" = mower ] && ! docked; then
    log "$p: the mower left the dock, nothing changed"
    undo_change "$p"
    undo_back "$back" "$current"
    return 2
  fi
  log "$p: $current -> $target"
  status "pending_$p" "$back" "$current" "$pulled" "$pulled"
  if restart "$p" "$pulled"; then
    v=$(version_of "$p")
    log "$p: updated to $v"
    keep_change "$p"
    status "pending_$p"
    status "$p" updated "$(now)" "$v"
    status "${p}_available" no "$target"
    return 0
  fi
  go_back "$p" "$back" "$current" "$pulled"
  # a version picked that didn't start: its image isn't kept for nothing
  [ "$target" = "$current" ] || docker rmi "$target" > /dev/null 2>&1
  return 1
}

# back to the version before, by hand: the newest rollback tag on another image, under the tag that runs now. what ran
# is kept the same way and left out of the automatic updates. it comes back when the one before doesn't answer
back_image() {
  local p="$1" c current repo before to now_back
  c=$(box "$p")
  current=$(ref_of "$c")
  repo=$(repo_of "$current")
  before=$(image_of "$c")
  to=$(newest_back "$repo" "$before")
  [ -n "$to" ] || { log "$p: no version before to go back to"; status "$p" error no_back; return 1; }
  progress "$p" back
  now_back=$(keep_back "$repo" "$before")
  [ -n "$now_back" ] || { status "$p" error keep; return 1; }
  log "$p: kept the version that ran as $now_back, back to $to"
  docker tag "$repo:$to" "$current"
  if restart "$p" "$(id_of "$repo:$to")"; then
    docker rmi "$repo:$to" > /dev/null 2>&1
    status "${p}_failed" "$before"
    status "$p" back "$(now)" "$(version_of "$p")"
    return 0
  fi
  log "$p: the version before didn't answer, again the one that ran"
  docker tag "$now_back" "$current"
  if restart "$p" "$before"; then
    docker rmi "$now_back" > /dev/null 2>&1
    status "$p" error back
  else
    status "$p" error rollback
  fi
  return 1
}

# --- OpenMower ---

# VERSION in its .env set to a tag, checked afterwards (and put back when it didn't take)
set_om_version() {
  change_file openmower "$(om_env)" "s/^\([[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}VERSION=\).*/\1\"$1\"/" || return 1
  [ "$(om_version)" = "$1" ] && return 0
  undo_change openmower
  return 1
}

check_openmower() {
  local cur
  if [ "$(kind openmower)" = os ]; then
    status openmower_running os
    status openmower_available os
    return
  fi
  cur=$(ref_of "$OM")
  status openmower_running "${cur##*:}" "$(day_of "$(image_of "$OM")")"
  status openmower_env "$(om_version)"
  available openmower "$OM" "$(repo_of "$cur"):$(om_channel)"
}

update_openmower() {
  local ref repo before old_version want target remote need free back rc base
  [ "$(kind openmower)" = openmower ] || return 0
  progress openmower prepare
  running "$OM" || { log "openmower: not running, left as it is"; status openmower stopped; return 0; }
  ref=$(ref_of "$OM")
  repo=$(repo_of "$ref")
  before=$(image_of "$OM")
  # a build of its own can't be downloaded again: never replaced by itself
  if [ -z "$MANUAL" ] && built_here "$before"; then
    log "openmower: runs an image built here, left as it is (only updated when asked)"
    status openmower local
    return 0
  fi
  old_version=$(om_version)
  [ -n "$old_version" ] || { log "openmower: VERSION in $(om_env) can't be read, nothing changed"; status openmower error env; return 1; }
  want=$(om_channel)
  target=$repo:$want
  remote=$(remote_digest "$target")
  [ -n "$remote" ] || { log "openmower: can't reach the registry for $target"; status openmower error registry; return 1; }
  if [ "$target" = "$ref" ] && known_as "$before" | grep -q "@$remote"; then
    status openmower current
    status openmower_available no "$target"
    return 0
  fi
  [ "$remote" = "$(get openmower_failed)" ] && { log "openmower: not again, $target didn't come up before"; status openmower skipped_failed; return 0; }
  [ "$want" != edge ] && exists "$PLANNER" && log "openmower: $want has no OM_PLANNER=external, the MowBite Planner won't work with it"
  # (the layers looked up once: for the room and the bar)
  layers "$target" > "$STATE/layers"
  need=$(need_mb "$target" "$before" "$STATE/layers")
  free=$(free_mb)
  if [ -z "$need" ] || [ -z "$free" ] || [ $((need + 1024)) -gt "$free" ]; then
    log "openmower: not enough room for $target (needs ${need:-?} MB and 1 GB to spare, ${free:-?} MB free), it stays as it is"
    status openmower nospace "${need:-?}" "${free:-?}"
    return 1
  fi
  back=$(keep_back "$repo" "$before")
  [ -n "$back" ] || { log "openmower: the version before can't be kept, nothing changed"; status openmower error keep; return 1; }
  log "openmower: kept the version before as $back"
  if [ "$want" != "$old_version" ] && ! set_om_version "$want"; then
    log "openmower: VERSION in $(om_env) can't be changed, nothing changed"
    undo_back "$back" "$ref"
    status openmower error env
    return 1
  fi
  log "openmower: $ref -> $target (needs $need MB, $free MB free)"
  # only OpenMower itself: the stack's other containers (its app, the broker) stay as they are
  with_progress openmower mower compose $T_PULL "$OM" --progress json pull "$(service "$OM")"
  rc=$?
  # the last word before it restarts
  if [ $rc -eq 0 ] && ! docked; then
    log "openmower: the mower left the dock, it stays as it is"
    rc=2
  fi
  if [ $rc -ne 0 ]; then
    [ $rc -eq 2 ] || log "openmower: pull failed, it stays as it is"
    undo_change openmower
    undo_back "$back" "$ref"
    # a version picked that didn't come: its image isn't kept for nothing
    [ "$target" = "$ref" ] || docker rmi "$target" > /dev/null 2>&1
    [ $rc -eq 2 ] && return 2
    status openmower error pull
    return 1
  fi
  status pending_openmower "$back" "$ref" "$(id_of "$target")" "$remote"
  if restart openmower "$(id_of "$target")"; then
    log "openmower: updated to $target"
    keep_change openmower
    status pending_openmower
    status openmower updated "$(now)" "$want"
    status openmower_available no "$target"
    # what's built on OpenMower's image: again on the new one
    rc=0
    for p in $(part_ids); do
      [ "$(kind "$p")" = build ] || continue
      base=$(base_of "$(box "$p")")
      if [ "$base" = "$target" ]; then
        build "$p" after_openmower
        [ $? -eq 2 ] && rc=2
      else
        [ -n "$base" ] && log "$p: built on $base, not on $target, left as it is"
      fi
    done
    return $rc
  fi
  go_back openmower "$back" "$ref" "$remote" || return 1
  [ "$target" = "$ref" ] || docker rmi "$target" > /dev/null 2>&1
  return 1
}

# --- a container built from github ---

# the newest commit of its branch
commit_of() {
  local src v
  src=$(source_of "$(box "$1")")
  [ -n "$src" ] || return
  # shellcheck disable=SC2086
  set -- $src
  # (git's own answer, not github's api: no limit of 60 an hour)
  v=$(wget -q -T 15 -O - "https://github.com/$1.git/info/refs?service=git-upload-pack" 2>/dev/null | tr '\000' ' ' |
    sed -n "s/^[0-9a-f]\{4\}\([0-9a-f]\{40\}\) refs\/heads\/$(re "${2:-main}")\( .*\)\{0,1\}\$/\1/p" | head -n1)
  valid "$v" '[0-9a-f]{40}' && echo "$v"
}
# the commit it was last built from here, while it still runs that image
built_of() { [ "$(get "$1_image")" = "$(image_of "$(box "$1")")" ] && get "$1_built"; }
# the image it was built on is still the one its base tag names
base_same() {
  local base
  base=$(base_of "$(box "$1")")
  [ -z "$base" ] || [ "$(get "$1_base_id")" = "$(id_of "$base")" ]
}

# built again from its own context and started. never --pull, and only when the image it's built on is here (for the
# planner: OpenMower's, it has to be built on the one that runs, a missing one would come down whole)
build() {
  local p="$1" c base commit img before ran back rc built
  c=$(box "$p")
  progress "$p" prepare
  base=$(base_of "$c")
  if [ -n "$base" ] && ! docker image inspect "$base" > /dev/null 2>&1; then
    log "$p: its base $base isn't here, not built (it would download it whole)"
    status "$p" error base_missing
    return 1
  fi
  room_for $ROOM_BUILD || { log "$p: less than $ROOM_BUILD MB free, not built"; status "$p" nospace $ROOM_BUILD "$(free_mb)"; return 1; }
  commit=$(commit_of "$p")
  img=$(ref_of "$c")
  before=$(image_of "$c")
  ran=$before
  # an image that ran and isn't there any more (built again with the same content, its tag went on and docker dropped
  # it while it ran): the one its tag names is the way back, the same a restart would run
  if ! docker image inspect "$before" > /dev/null 2>&1; then
    before=$(id_of "$img")
    [ -n "$before" ] && log "$p: the image it runs isn't there any more, the one its tag names is the way back"
  fi
  back=$(keep_back "$(repo_of "$img")" "$before")
  [ -n "$back" ] || { log "$p: the version before can't be kept, not built"; status "$p" error keep; return 1; }
  log "$p: kept the version before as $back, building ($2)"
  : > "$STATE/layers"
  with_progress "$p" "$(gate "$p")" compose $T_BUILD "$c" --progress json build "$(service "$c")"
  rc=$?
  [ $rc -eq 0 ] || [ $rc -eq 2 ] || log "$p: the build failed, the one before keeps running"
  if [ $rc -eq 0 ] && [ "$(gate "$p")" = mower ] && ! docked; then
    log "$p: the mower left the dock, the one before keeps running"
    rc=2
  fi
  if [ $rc -ne 0 ]; then
    undo_back "$back" "$img"
    [ $rc -eq 2 ] && return 2
    status "$p" error build
    return 1
  fi
  built=$(id_of "$img")
  if [ "$before" = "$ran" ] && same "$built" "$before"; then
    # the same image again (built again it only has another record of its build): nothing to restart, compose would
    # leave it anyway. the tag stays on the one that runs, so that one stays there
    log "$p: the same image as before, it keeps running"
    docker tag "$before" "$img"
    docker rmi "$back" > /dev/null 2>&1
  else
    status "pending_$p" "$back" "$img" "$built" "$commit"
    restart "$p" "$built" || { go_back "$p" "$back" "$img" "$commit"; return 1; }
    status "pending_$p"
    log "$p: running again"
  fi
  status "$1_image" "$(image_of "$c")"
  status "$1_built" "$commit"
  [ -n "$base" ] && status "$1_base_id" "$(id_of "$base")"
  status "$p" updated "$(now)" "$(echo "$commit" | cut -c1-7)"
  [ -n "$commit" ] && status "${p}_available" no main
  return 0
}

check_build() {
  local c built want
  c=$(box "$1")
  built=$(built_of "$1")
  status "$1_running" "${built:-?}" "$(day_of "$(image_of "$c")")"
  status "$1_source" github
  want=$(commit_of "$1")
  if [ -z "$want" ] || [ -z "$built" ]; then
    status "$1_available" unknown main
  elif [ "$want" = "$built" ] && base_same "$1"; then
    status "$1_available" no main
  elif [ "$want" = "$(get "$1_failed")" ]; then
    status "$1_available" failed main
  else
    status "$1_available" yes main
  fi
}

update_build() {
  local want
  progress "$1" prepare
  running "$(box "$1")" || { log "$1: not running, left as it is"; status "$1" stopped; return 0; }
  want=$(commit_of "$1")
  [ -n "$want" ] || { status "$1" error github; return 1; }
  if [ "$want" = "$(built_of "$1")" ] && base_same "$1"; then
    status "$1" current
    return 0
  fi
  if [ "$want" = "$(get "$1_failed")" ] && base_same "$1"; then
    log "$1: not again, $(echo "$want" | cut -c1-7) didn't start before"
    status "$1" skipped_failed
    return 0
  fi
  build "$1" "$(echo "$want" | cut -c1-7)"
}

# a part built from a copy here: shown, left as it is
check_local() {
  status "$1_running" "?" "$(day_of "$(image_of "$(box "$1")")")"
  status "$1_source" local
  status "$1_available" no local
}

check_part() {
  case $(kind "$1") in
  openmower | os) check_openmower ;;
  image) check_image "$1" ;;
  build) check_build "$1" ;;
  local) check_local "$1" ;;
  esac
}
update_part() {
  case $(kind "$1") in
  openmower) update_openmower ;;
  image) update_image "$1" ;;
  build) update_build "$1" ;;
  local) status "$1" local ;;
  os) status openmower os ;;
  esac
}

# --- stopped halfway ---

# a run that didn't end (the power gone, the container stopped): a file it changed for a part it hadn't restarted yet
# goes back, if nobody changed it since; a tag moved to an image that never started goes back on the one that runs; a
# part it had restarted is looked at again (settle). nothing starts later on something nobody saw come up
recover() {
  [ "$(get result)" = running ] || return 0
  log "the last run was stopped halfway, putting back what didn't run yet"
  for p in $(part_ids); do
    # shellcheck disable=SC2046
    set -- $(get "changed_$p")
    [ -n "$1" ] || continue
    if [ -n "$(get "pending_$p")" ]; then
      :
    elif [ "$(md5sum < "$1" 2>/dev/null | cut -d' ' -f1)" = "$2" ]; then
      undo_change "$p"
    else
      log "$p: $1 was changed since, left as it is"
      keep_change "$p"
    fi
  done
  for p in $(part_ids); do
    c=$(box "$p")
    [ "$c" != - ] && exists "$c" || continue
    [ -n "$(get "pending_$p")" ] && continue
    ref=$(ref_of "$c")
    img=$(image_of "$c")
    tagged=$(id_of "$ref")
    if [ -n "$tagged" ] && [ "$tagged" != "$img" ] && docker image inspect "$img" > /dev/null 2>&1; then
      docker tag "$img" "$ref" && log "$ref back on the image that runs"
    fi
  done
  status run_parts
  settle
  status result interrupted
}

# --- room ---

# what's on the disk that nothing needs: images no container uses (not even a stopped one) and no compose file names
# with its tag or builds on, with the room each frees for real (its own layers), and the build cache. only listed here,
# deleted only when asked (room_free), never on its own
stacks_root() { dirname "$(label "$ME" project.working_dir)"; }
# the images the stacks' compose files name or build on, their .env filled in (${VERSION:-edge} and the like)
compose_refs() {
  for f in "$(stacks_root)"/*/compose.yaml "$(stacks_root)"/*/compose.yml "$(stacks_root)"/*/docker-compose.yaml "$(stacks_root)"/*/docker-compose.yml; do
    [ -f "$f" ] || continue
    {
      [ -f "$(dirname "$f")/.env" ] && tr -d '\r' < "$(dirname "$f")/.env"
      echo '@@images'
      # the images, and the ones a build starts from (OPENMOWER_IMAGE: ... for the planner)
      sed -n 's/^[[:space:]]*image:[[:space:]]*//p; s/^[[:space:]]*[A-Za-z_]*IMAGE[A-Za-z_]*:[[:space:]]*//p' "$f"
    } | awk '
      $0 == "@@images" { images = 1; next }
      !images {
        line = $0
        sub(/^[[:space:]]*export[[:space:]]+/, "", line)
        if (match(line, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          k = substr(line, 1, RLENGTH - 1); v = substr(line, RLENGTH + 1)
          sub(/[[:space:]]+#.*$/, "", v); gsub(/^["\047]|["\047][[:space:]]*$/, "", v); env[k] = v
        }
        next
      }
      {
        ref = $0; sub(/[[:space:]]+#.*$/, "", ref); gsub(/["\047[:space:]]/, "", ref)
        while (match(ref, /\$\{[^}]*\}/)) {
          s = RSTART; l = RLENGTH; inner = substr(ref, s + 2, l - 3); name = inner; def = ""
          p = index(inner, ":-")
          if (p) { name = substr(inner, 1, p - 1); def = substr(inner, p + 2) }
          else if ((p = index(inner, "-"))) { name = substr(inner, 1, p - 1); def = substr(inner, p + 1) }
          ref = substr(ref, 1, s - 1) ((name in env && env[name] != "") ? env[name] : def) substr(ref, s + l)
        }
        sub(/^docker\.io\/library\//, "", ref); sub(/^docker\.io\//, "", ref)
        n = split(ref, part, "/"); if (!index(part[n], ":")) ref = ref ":latest"
        print ref
      }'
  done
}
# bytes from docker's sizes: 512B, 4.1kB, 12.3MB, 1.2GB
bytes_awk='function bytes(s, n, u) { n = s + 0; u = s; sub(/^[0-9.]+/, "", u); if (u == "kB") n *= 1e3; else if (u == "MB") n *= 1e6; else if (u == "GB") n *= 1e9; else if (u == "TB") n *= 1e12; return int(n) }'
# one line per image: img <id> <bytes> <its tags, comma separated, or -> <kind>, then: cache <bytes>
check_room() {
  used=" $(docker ps -aq | xargs -r docker inspect -f '{{.Image}}' 2>/dev/null | tr '\n' ' ') "
  named=" $(compose_refs | tr '\n' ' ') "
  out=$(mktemp)
  timeout $T_UP docker system df -v --format '{{json .Images}}' 2>/dev/null | sed 's/^\[//; s/\]$//; s/},{/}\n{/g' | awk -v used="$used" -v named="$named" "$bytes_awk"'
    function field(k,    v) {
      if (!match($0, "\"" k "\":\"[^\"]*\"")) return ""
      v = substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5); gsub(/\\u003c/, "<", v); gsub(/\\u003e/, ">", v)
      return v
    }
    {
      id = field("ID"); repo = field("Repository"); tag = field("Tag"); ref = repo ":" tag
      if (id == "") next
      if (field("Containers") != "0" || index(used, " " id " ") || (repo != "<none>" && index(named, " " ref " "))) { keep[id] = 1; next }
      size[id] = bytes(field("UniqueSize"))
      if (repo != "<none>") refs[id] = refs[id] (refs[id] == "" ? "" : ",") ref
      k = repo == "<none>" ? "dangling" : tag ~ /^rb-|^previous$/ ? "rollback" : tag ~ /^before-/ ? "planner" : tag ~ /^prev-/ ? "old" : "unused"
      if (kind[id] == "" || kind[id] == "unused") kind[id] = k
    }
    END { for (id in size) if (!keep[id]) print "img", substr(id, 8, 12), size[id], (refs[id] == "" ? "-" : refs[id]), kind[id] }' > "$out"
  echo "cache $(timeout $T_UP docker system df --format '{{.Type}}|{{.Size}}' 2>/dev/null | sed -n 's/^Build Cache|//p' | awk "$bytes_awk"'{ print bytes($0) }')" >> "$out"
  mv "$out" "$STATE/room"
}

# what was asked to delete: one image from the list (all its tags, never forced), all of them, or the build cache.
# the list is made again first: only what still nothing needs goes
room_free() {
  before=$(free_mb)
  check_room
  case $1 in
  cache)
    timeout $T_UP docker builder prune -af > /dev/null 2>&1
    log "room: build cache cleared"
    ;;
  img | all)
    grep '^img ' "$STATE/room" 2>/dev/null | while read -r _ id _ refs _; do
      [ "$1" = all ] || [ "$id" = "$2" ] || continue
      if [ "$refs" = - ]; then
        docker rmi "$id" > /dev/null 2>&1 && log "room: removed image $id"
      else
        for r in $(echo "$refs" | tr ',' ' '); do docker rmi "$r" > /dev/null 2>&1 && log "room: removed $r"; done
      fi
    done
    ;;
  esac
  check_room
  status disk_free "$(free_mb)"
  log "room: $(($(free_mb) - before)) MB more free, $(free_mb) MB free"
}

# --- leftovers ---

# its own older rollback tags: of each part the newest few on other images than the one that runs (an app's: two, the
# big ones: none), newest first by the time in the tag. not while a part waits to be seen running, and never one on an
# image built here that can't be had again (a build's can: it's built from its source). tags it didn't make stay.
# then what nothing uses and the build cache nothing points to
tidy() {
  local p keep name repo run kept n seen_before
  for p in $(part_ids); do
    name=$(box "$p")
    exists "$name" || continue
    case $(kind "$p") in
    # (a big app, like xtech's with its 300 MB, keeps none: the mower's disk is small)
    image) if [ "$(docker image inspect -f '{{.Size}}' "$(image_of "$name")" 2>/dev/null || echo 0)" -lt 104857600 ]; then keep=$KEEP; else keep=$KEEP_BIG; fi ;;
    openmower | build) keep=$KEEP_BIG ;;
    *) continue ;;
    esac
    [ -n "$(get "pending_$p")" ] && continue
    repo=$(repo_of "$(ref_of "$name")")
    run=$(image_of "$name")
    docker images --no-trunc --format '{{.Tag}} {{.ID}}' "$repo" | grep '^rb-[0-9]*-' | sort -t- -k2,2nr | {
      kept=" "
      n=0
      while read -r t id; do
        case $kept in *" $id "*) seen_before=1 ;; *) seen_before= ;; esac
        if [ "$id" != "$run" ] && [ -z "$seen_before" ] && [ $n -lt "$keep" ]; then
          kept="$kept$id "
          n=$((n + 1))
        elif [ "$(kind "$p")" != build ] && [ "$id" != "$run" ] && [ -z "$seen_before" ] && built_here "$id"; then
          kept="$kept$id "
        else
          docker rmi "$repo:$t" > /dev/null 2>&1 && log "removed $repo:$t"
        fi
      done
    }
  done
  # (a test on a pc with images and builds of its own: PRUNE=0)
  if [ "${PRUNE:-1}" != 0 ]; then
    freed=$(timeout $T_UP docker image prune -f 2>/dev/null | sed -n 's/^Total reclaimed space: //p')
    cache=$(timeout $T_UP docker builder prune -f 2>/dev/null | sed -n 's/^Total: *//p')
  fi
  log "tidied up: images ${freed:-0B}, build cache ${cache:-0B}, $(free_mb) MB free"
}

# itself, for its card: the commit it runs and from when, whether its registry has a newer one
check_self() {
  local img rev
  img=$(image_of "$ME")
  rev=$(rev_of "$img")
  status updater_running "${rev:-?}" "$(day_of "$img")"
  if in_compose "$ME"; then
    available updater "$ME" "$(ref_of "$ME")"
    status updater_away
  else
    status updater_available unknown none
    # (its own compose file out of reach: no settings kept, no update of itself)
    status updater_away "$(label "$ME" project.working_dir | grep . || echo -)"
  fi
}

# itself: a helper container on the image that runs now (self.sh) recreates it on the new one, from inside compose
# would stop this container before the new one starts. the helper sees it come up, else puts this one back. asked for
# ($1 manual): with the download on the bar and a word on its card when there's nothing new. at night: quiet, and an
# image built here stays
update_self() {
  local me prev new root need rc was
  if ! in_compose "$ME"; then
    [ -n "$1" ] && log "the updater doesn't run from a compose file, it can't update itself" && status updater error compose
    return
  fi
  me=$(ref_of "$ME")
  [ -z "$1" ] && built_here "$(image_of "$ME")" && return
  # (asked for after the apps: its card shows it's on it)
  [ -n "$1" ] && [ -z "$(get taken)" ] && status taken "$(now)" self
  # the helper of its update a moment ago may still see it come up, with :previous as its way back: that one first.
  # (one that ended and stayed is cleared away, a running one can't be)
  if docker container inspect mowbite-updater-self > /dev/null 2>&1; then
    timeout 300 docker wait mowbite-updater-self > /dev/null 2>&1
    docker rm mowbite-updater-self > /dev/null 2>&1
  fi
  # (the layers looked up once: for the room and the bar)
  layers "$me" > "$STATE/layers"
  need=$(need_mb "$me" "$(image_of "$ME")" "$STATE/layers")
  [ -n "$need" ] || need=$(($(docker image inspect -f '{{.Size}}' "$(image_of "$ME")" 2>/dev/null || echo 0) / 1048576))
  if ! room_for $((need + ROOM_APP)); then
    log "the updater: not enough room (needs $need MB and $ROOM_APP to spare, $(free_mb) MB free), it stays as it is"
    status updater nospace "$need" "$(free_mb)"
    return
  fi
  # the image it runs now, kept first under a tag of its own: the helper runs on it, and it's the way back
  prev=$(repo_of "$me"):previous
  docker tag "$(image_of "$ME")" "$prev" 2>/dev/null || { log "the updater's own image can't be kept, it doesn't update itself"; status updater error keep; return; }
  if [ -n "$1" ]; then
    # (on its bar like a part, the run before keeps what it said: waiting for the dock)
    was=$(get result)
    status run_parts updater
    status result running
    status taken
    progress updater prepare
    with_progress updater none pull_image "$me"
    rc=$?
    status progress
    status run_parts
    status result "${was:-done}"
  else
    timeout $T_PULL docker pull -q "$me" > /dev/null 2>&1
    rc=$?
  fi
  if [ $rc -ne 0 ]; then
    [ -n "$1" ] && log "the updater: its new version can't be downloaded, it stays as it is" && status updater error pull
    return
  fi
  new=$(id_of "$me")
  if [ "$new" = "$(id_of "$prev")" ]; then
    [ -n "$1" ] && log "the updater is up to date" && status updater current
    check_self
    return
  fi
  if [ "$new" = "$(get updater_failed)" ]; then
    docker tag "$prev" "$me"
    [ -n "$1" ] && log "the updater: not again, this version didn't start before" && status updater skipped_failed
    return
  fi
  # (all stacks: dockge may give each one a global.env next to them)
  root=$(dirname "$(label "$ME" project.working_dir)")
  log "updating the updater"
  # (what came of it, the next start says: a new version, or this one back)
  status updater restarting "$(now)"
  docker run -d --rm --name mowbite-updater-self -v /var/run/docker.sock:/var/run/docker.sock -v "$root:$root" -v /etc/localtime:/etc/localtime:ro \
    -e "STATE_DIR=$STATE" -e "UPDATER_CONTAINER=$ME" --entrypoint sh "$prev" /self.sh "$me" "$prev" > /dev/null 2>&1 ||
    { log "the updater's helper didn't start, it stays as it is"; docker tag "$prev" "$me"; status updater error helper; }
}

# (a request from its page or MowBite is waiting)
asked() { [ -s "$REQ" ]; }
# the look whether there's something new, for its page while it lasts (looking). a request that comes in meanwhile
# goes first: the look stops before its next step and is done again after it (half)
check_all() {
  half=1
  asked && return 0
  status looking "$(now)"
  find_parts
  for p in $(part_ids); do
    asked && break
    check_part "$p"
  done
  asked || check_self
  if ! asked; then
    check_room
    status disk_free "$(free_mb)"
    status checked "$(now)"
    half=
  fi
  status looking
}

# the parts asked for (all: every one), OpenMower first (builds start from it), the rest in their order. the ones that
# wait for the dock only with the mower idle there, asked before each again. 2 when one had to wait for that
run() {
  local why="$1" parts="" p waited was
  shift
  find_parts
  for p in $(part_ids); do
    case " $* " in *" $p "* | *" all "*) parts="$parts $p" ;; esac
  done
  # shellcheck disable=SC2086
  status run_parts $parts
  status result running
  # (from here its page shows the run)
  status taken
  # (one restarted before and not seen running yet comes first)
  docked && settle
  MANUAL=
  [ "$why" = request ] && MANUAL=1
  waited=
  for p in $parts; do
    # (asked for: a part left as it was says why on its card)
    if [ "$(gate "$p")" = mower ] && ! docked; then
      waited=1
      [ -n "$MANUAL" ] && status "$p" error not_docked
      continue
    fi
    was=$(get "$p")
    update_part "$p"
    if [ $? -eq 2 ]; then
      waited=1
      [ -n "$MANUAL" ] && [ "$(get "$p")" = "$was" ] && status "$p" error not_docked
    fi
  done
  status progress
  status run_parts
  # (for its page the run ends here: the leftovers and the look afterwards are no part of it)
  if [ -n "$waited" ]; then
    log "waiting ($why): the mower isn't idle in the dock, the rest another time"
    status result waiting
  else
    status result "done"
  fi
  tidy
  check_all
  [ -z "$waited" ] || return 2
}

# the parts set to update by themselves
auto_parts() {
  for p in $(part_ids); do auto "$p" && printf '%s ' "$p"; done
}
# the days it may run: daily or the weekdays 1-7 (monday 1), the day its window started ($1, unix time)
day_ok() {
  days=$(conf days daily)
  [ "$days" = daily ] && return 0
  case ",$days," in *",$(date -d "@$1" +%u),"*) return 0 ;; esac
  return 1
}
# minutes since midnight of now, and of the time set (without a leading 0, sh would read 08 as octal)
num() { echo "$1" | sed 's/^0//'; }
minute() { echo $(($(num "$(date +%H)") * 60 + $(num "$(date +%M)"))); }
at_minute() {
  at=$(conf at 03:00)
  valid "$at" '([01][0-9]|2[0-3]):[0-5][0-9]' || at=03:00
  echo $(($(num "${at%:*}") * 60 + $(num "${at#*:}")))
}
# its page and its interface (on the host's network: on the mower's address)
serve() { pidof httpd > /dev/null || httpd -p "${PORT:-8083}" -h /www; }

# (sourced by a test for its functions)
[ -n "$UPDATER_NO_LOOP" ] && return 0
trap 'exit 0' TERM INT
# (a request from its page or MowBite wakes it up at once, see the sleep at the end)
trap ':' USR1
if [ -z "$STATE_DIR" ] && [ -z "$(label "$ME" project.working_dir)" ]; then
  echo "MowBite Updater: it has to run from a compose file (its settings and log go next to it), see its readme" >&2
  while sleep 3600; do :; done
fi
mkdir -p "$STATE"
chmod 700 "$STATE"
# (for its interface, so it needs no docker to find its folder)
printf '%s\n' "$STATE" > /tmp/updater-state
serve
log "started"
# a new version of itself since it last started (its own update, or one by hand in dockge), or the one before back
# when the new one didn't come up: said on its card
# shellcheck disable=SC2046
set -- $(get started)
case $(get updater) in restarting*) asked_self=1 ;; *) asked_self= ;; esac
if [ -n "$2" ] && [ "$2" != "$(image_of "$ME")" ] && [ "$2" != "$(get updater_failed)" ]; then
  log "the updater runs its new version"
  status updater updated "$(now)" "$(rev_of "$(image_of "$ME")")"
  # (its card right away, not only after its first look)
  status updater_available no "$(ref_of "$ME")"
elif [ -n "$asked_self" ] || { [ -n "$2" ] && [ "$2" != "$(image_of "$ME")" ]; }; then
  status updater rolled_back "$(now)"
fi
status started "$(now)" "$(image_of "$ME")"
# (its page can be embedded, in MowBite's settings)
status embed 1
# (what a stop halfway left of a request or a look)
status taken
status looking
alive
find_parts
recover
check_all
done_day=""
next=0
while :; do
  serve
  alive
  taken=
  if asked; then
    # taken away first: what comes in meanwhile waits for the next round. its page knows at once that it's on it
    if mv "$REQ" "$REQ.$$"; then
      taken=1
      stuck=
      # shellcheck disable=SC2046
      status taken "$(now)" $(cut -d' ' -f1,2 "$REQ.$$" | tr ' ' ':')
    else
      stuck=1
    fi
  fi
  # the mower right now, for its page
  status mower "$(mower)"
  if [ -n "$taken" ]; then
    parts=""
    check=""
    self=""
    while read -r w a b; do
      case $w in
      check) check=1 ;;
      # (all: itself too, last)
      now)
        parts="$parts $a"
        [ "$a" = all ] && self=1
        ;;
      self) self=1 ;;
      back)
        if [ "$(kind "$a")" != image ]; then
          :
        elif [ "$(gate "$a")" = none ] || docked; then
          status run_parts "$a"
          status result running
          status taken
          back_image "$a"
          status progress
          status run_parts
          status result "done"
          check_all
        else
          log "$a: not back to the version before, the mower isn't idle in the dock"
          status "$a" error not_docked
        fi
        ;;
      room) check_room ;;
      free) room_free "$a" "$b" ;;
      esac
    done < "$REQ.$$"
    rm -f "$REQ.$$"
    if [ -n "$parts" ]; then
      # shellcheck disable=SC2086
      run request $parts
    elif [ -n "$check" ]; then
      check_all
    fi
    [ -n "$self" ] && update_self manual
    status taken
  fi
  # a request that came in while it was busy: at once, before the night's run or a look, its wake-up came while
  # nothing slept (one it can't take: next round, as before)
  [ -z "$stuck" ] && asked && continue
  # the night's run: once in its window (also past midnight, it counts as the night it started), again every 10 minutes
  # while the mower isn't in the dock
  parts=$(auto_parts)
  since=$((($(minute) - $(at_minute) + 1440) % 1440))
  start=$(($(now) - since * 60))
  if [ -n "$parts" ] && [ $since -lt $WINDOW ] && [ "$done_day" != "$(date -d "@$start" +%F)" ] && day_ok "$start" && [ "$(now)" -ge "$next" ]; then
    # shellcheck disable=SC2086
    run night $parts
    if [ $? -eq 2 ]; then
      next=$(($(now) + 600))
    else
      done_day=$(date -d "@$start" +%F)
      update_self
    fi
  elif [ -n "$half" ] || [ $(($(now) - $(get checked | grep -x '[0-9]*' || echo 0))) -ge $CHECK_EVERY ]; then
    check_all
  fi
  # (and one that came in during those)
  [ -z "$stuck" ] && asked && continue
  sleep 60 &
  nap=$!
  wait $nap
  kill $nap 2> /dev/null
done
