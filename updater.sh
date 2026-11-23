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
# it goes back to what ran before and leaves that version out (OpenMower also when the new version keeps the motors off
# for the firmware); restarted again only while OpenMower doesn't drive the mower. OpenMower and builds restart with
# MowBite's schedule held (mowbite/hold), OpenMower not in the 30 minutes before the schedule may start the mower
# (mowbite/schedule/next). only with room to spare. all through
# the stacks' own compose files, so dockge shows the same, files changed keep owner and rights, only its own change is
# ever put back. stopped halfway (power gone), it puts back what it changed and looks again at what it had restarted, at
# its next start. images built here aren't replaced or deleted by itself. last the leftovers go: its older rollback
# tags, images nothing uses, the build cache. what it does right now goes to the status as progress, for the bars on its
# page
# on a tap and with the OS's image set, it puts MowBite OS in OpenMower's place and back (see "MowBite OS instead of
# OpenMower")
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
# OpenMower updated without a copy and not there or not seen running: looked at again every 10 minutes, a download 6 times
NOKEEP_EVERY=600
NOKEEP_TRIES=6
# seconds anything over the network or with docker may take, so nothing hangs for good
T_REGISTRY=60
T_PULL=1800
T_UP=300
T_BUILD=900

alive() { status alive "$(now)"; }
# what came of a part, for its card, and when (<part>_at)
outcome() {
  status "$@"
  status "${1}_at" "$(now)"
}
# seconds since the machine started: a wait that a clock set by ntp meanwhile doesn't cut short or stretch

# --- the mower ---

# the broker's user and password in mosquitto_sub's and mosquitto_pub's own options files, written at its start: not on
# their command line, where ps shows them (an empty password can only go there)
MQTT_OPTS=${XDG_CONFIG_HOME:-$HOME/.config}/mosquitto_sub
MQTT_PUB_OPTS=${XDG_CONFIG_HOME:-$HOME/.config}/mosquitto_pub
# the mower as OpenMower says it right now over mqtt (nothing the broker kept from before): "1" idle in the dock, else
# "0 <state>" (MOWING, IDLE out of the dock or with the dock's power gone, unknown while OpenMower doesn't answer),
# nothing when there's no broker to ask
mqtt() {
  local t="$1"
  set -- -h "${MQTT_HOST:-127.0.0.1}" -p "${MQTT_PORT:-1883}"
  [ -n "$MQTT_USER" ] && [ ! -s "$MQTT_OPTS" ] && set -- "$@" -u "$MQTT_USER" -P "$MQTT_PASSWORD"
  timeout 10 mosquitto_sub "$@" -t "$t" -R -C 1 -W 6 2> /dev/null
}
mower() {
  local s rc state charging sub
  s=$(mqtt robot_state/json)
  rc=$?
  # (27: nothing came in time, the broker is there but OpenMower doesn't answer)
  if [ -z "$s" ]; then
    [ $rc -eq 27 ] && echo "0 unknown"
    return 0
  fi
  state=$(printf '%s' "$s" | sed -n 's/.*"current_state": *"\([A-Z_]*\)".*/\1/p')
  charging=$(printf '%s' "$s" | sed -n 's/.*"is_charging": *\([a-z0-9]*\).*/\1/p')
  # (idle but driven by hand, calibrating or in its setup on MowBite OS: busy like mowing)
  sub=$(printf '%s' "$s" | sed -n 's/.*"current_sub_state": *"\([A-Z_]*\)".*/\1/p')
  if [ "$state" = IDLE ]; then
    case $sub in DRIVING | CALIBRATING | SETUP) echo "0 $sub" && return 0 ;; esac
  fi
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
# nothing drives the mower and nothing can send it out: idle in the dock, OpenMower removed for its update without a
# copy, or OpenMower not answering while a build removed with it is missing (with OM_PLANNER=external it doesn't come up
# without the planner)
still() {
  local m
  gone "$OM" && return 0
  m=$(mower)
  [ "$m" = 1 ] || { [ "$m" = "0 unknown" ] && [ -n "$(gone_builds)" ]; }
}
# a value of OpenMower's parameters as rosparam gives them, one "key: value" a line, without the quotes round it
pval() {
  local v
  v=$(printf '%s\n' "$1" | sed -n "s/^$2: *//p" | head -n1)
  case $v in
  \'*\')
    v=${v#\'}
    v=$(printf '%s' "${v%\'}" | sed "s/''/'/g")
    ;;
  \"*\")
    v=${v#\"}
    v=${v%\"}
    ;;
  esac
  printf '%s' "$v"
}
own_broker() { echo "${MQTT_HOST:-127.0.0.1}|${MQTT_PORT:-1883}||own|"; }
# the places MowBite works at, OpenMower's brokers: the one on the mower (no prefix, xbot_monitoring has it fixed) and
# the external one while OpenMower sends there too, as OpenMower runs with it (xbot_monitoring/external_mqtt_*, from
# mower_params.yaml or OM_MQTT_* in a legacy config): the prefix with a / after it and a port given as text taken as
# 1883, like xbot_monitoring does. "host|port|prefix|login|user" a line, login the folder of the external one's mosquitto
# options files with its password, user one without a password. parameters that don't come: the one on the mower alone,
# 1 while OpenMower answers (whether it sends to an external one isn't known), 2 while it doesn't (none of its brokers
# takes a start to the mower then but the one on it)
om_brokers() {
  local p host port prefix user pass login
  own_broker
  if ! p=$(timeout 20 docker exec "$OM" bash -lc '. /opt/open_mower_ros/devel/setup.bash && rosparam get /xbot_monitoring' 2> /dev/null); then
    # (removed for its update without a copy: it sends nowhere)
    gone "$OM" && return 2
    case $(mower) in "" | "0 unknown") return 2 ;; *) return 1 ;; esac
  fi
  case $(pval "$p" external_mqtt_enable) in true | True | 1) ;; *) return 0 ;; esac
  host=$(pval "$p" external_mqtt_hostname)
  [ -n "$host" ] || return 0
  port=$(printf '%s\n' "$p" | sed -n 's/^external_mqtt_port: *//p' | head -n1)
  case $port in "" | *[!0-9]*) port=1883 ;; esac
  prefix=$(pval "$p" external_mqtt_topic_prefix)
  case $prefix in "" | */) ;; *) prefix=$prefix/ ;; esac
  user=$(pval "$p" external_mqtt_username)
  pass=$(pval "$p" external_mqtt_password)
  login=${MQTT_OPTS%/*}/external
  (umask 077 && mkdir -p "$login" && rm -f "$login/mosquitto_sub" "$login/mosquitto_pub") || return 0
  if [ -n "$user" ] && [ -n "$pass" ]; then
    (umask 077 && printf -- '-u %s\n-P %s\n' "$user" "$pass" > "$login/mosquitto_sub" && cp "$login/mosquitto_sub" "$login/mosquitto_pub")
    user=
  fi
  echo "$host|$port|$prefix|$login|$user"
}
# mosquitto_sub or mosquitto_pub ($1) on a broker of om_brokers() ($2) with a topic of MowBite's ($3, after its prefix)
# and the rest of the options
on_broker() {
  local tool="$1" t="$3" host port prefix login user
  IFS='|' read -r host port prefix login user << EOF
$2
EOF
  shift 3
  set -- -h "$host" -p "$port" -t "$prefix$t" "$@"
  if [ "$login" = own ]; then
    [ -n "$MQTT_USER" ] && [ ! -s "${MQTT_OPTS%/*}/$tool" ] && set -- "$@" -u "$MQTT_USER" -P "$MQTT_PASSWORD"
    timeout 10 "$tool" "$@" 2> /dev/null
  else
    [ -n "$user" ] && set -- "$@" -u "$user"
    XDG_CONFIG_HOME=$login timeout 10 "$tool" "$@" 2> /dev/null
  fi
}
# MowBite's schedule starts nothing while it holds it: {"until":<unix s>}, set before OpenMower or a build restarts
# (what the schedule started then would stand in the garden), gone once that's done. one left by an updater stopped
# halfway runs out by itself: HOLD_FOR covers a restart, its look and the way back. a start sent just before shows in
# the mower's state after HOLD_WAIT. on each of OpenMower's brokers, MowBite is on one of them
HOLD_FOR=1500
HOLD_WAIT=${UPDATER_HOLD_WAIT:-10}
# how long a calibration waits for the mower idle in the dock (s)
CALIB_WAIT=${UPDATER_CALIB_WAIT:-1800}
held=
held_m=
hold() {
  local b list
  # (a MowBite OS host keeps its schedule itself: nothing retained on its broker from here)
  if os_host; then
    log "$1: a MowBite OS host, MowBite's schedule isn't held from here"
    return 1
  fi
  list=$(om_brokers)
  case $? in
  1)
    log "$1: OpenMower runs but its parameters didn't come (whether it sends to an external broker too), not restarted"
    return 1
    ;;
  2) log "$1: OpenMower doesn't answer, MowBite's schedule held on its broker on the mower only" ;;
  esac
  held_m="{\"until\":$(($(now) + HOLD_FOR))}"
  for b in $list; do
    if ! on_broker mosquitto_pub "$b" mowbite/hold -r -m "$held_m"; then
      log "$1: MowBite's schedule can't be held (mqtt ${b%%|*}), not restarted"
      unhold
      return 1
    fi
    held="$held $b"
  done
  sleep "$HOLD_WAIT"
}
# a broker in OpenMower's container (its legacy image, without persistence) forgets the hold when it restarts: set
# again as soon as it takes it, before anything looks at the mower
rehold() {
  local b end
  [ -n "$held" ] || return 0
  end=$(($(up) + 60))
  for b in $held; do
    until on_broker mosquitto_pub "$b" mowbite/hold -r -m "$held_m"; do
      [ "$(up)" -lt "$end" ] || { log "MowBite's schedule couldn't be held again (mqtt ${b%%|*})"; break; }
      sleep 1
    done
  done
}
unhold() {
  local b were="$held"
  [ -n "$were" ] || return 0
  held=
  for b in $were; do
    on_broker mosquitto_pub "$b" mowbite/hold -r -n || log "MowBite's schedule still held (mqtt ${b%%|*}), it runs out by itself"
  done
}
# when MowBite's schedule may start the mower within 30 minutes or right now (it says from when to when, retained
# {"from":<unix s>,"to":<unix s>}, on the broker it's on): the earliest from when. nothing said, nothing soon
soon() {
  local b n from to at=
  for b in $(om_brokers); do
    n=$(on_broker mosquitto_sub "$b" mowbite/schedule/next -C 1 -W 3)
    from=$(printf '%s' "$n" | sed -n 's/.*"from": *\([0-9]*\).*/\1/p')
    to=$(printf '%s' "$n" | sed -n 's/.*"to": *\([0-9]*\).*/\1/p')
    if [ -n "$from" ] && [ -n "$to" ] && [ $(($(now) + 1800)) -ge "$from" ] && [ "$(now)" -le "$to" ]; then
      [ -z "$at" ] || [ "$from" -lt "$at" ] && at=$from
    fi
  done
  [ -n "$at" ] && echo "$at"
}
# OpenMowerOS 3: open_mower_ros is part of the os there, updated with it (openmower update-os)
new_os() { grep -qx 'ID=openmower-os' /host/os-release 2> /dev/null; }
# whether OpenMower keeps the motors off for a firmware that doesn't fit it (FIRMWARE_INCOMPATIBLE in its emergency's
# reason, set by OpenMower itself: robot_state doesn't say it). 1 not, 2 no telling (an image without rostopic)
fw_blocked() {
  local r
  r=$(timeout 20 docker exec "$OM" bash -lc '. /opt/open_mower_ros/devel/setup.bash && rostopic echo -n1 /ll/emergency/reason' 2> /dev/null) || return 2
  case $r in *FIRMWARE_INCOMPATIBLE*) return 0 ;; *---*) return 1 ;; *) return 2 ;; esac
}

# --- containers and images ---

image_of() { docker inspect -f '{{.Image}}' "$1" 2>/dev/null; }
ref_of() {
  local r
  if r=$(docker inspect -f '{{.Config.Image}}' "$1" 2>/dev/null); then echo "$r"; else gone_of "$1" | cut -d' ' -f2; fi
}
id_of() { docker image inspect -f '{{.Id}}' "$1" 2>/dev/null; }
# an image's bytes on disk as docker lists them, 0 when it isn't there. (inspect's Size is only the packed layers with
# containerd's image store, as on OpenMowerOS)
image_bytes() {
  local i
  i=$(id_of "$1") || { echo 0; return; }
  docker image ls --no-trunc --format '{{.ID}} {{.Size}}' 2>/dev/null | awk -v i="$i" "$bytes_awk"'$1 == i {print bytes($2); f = 1; exit} END {if (!f) print 0}'
}
# (a container waiting for its next restart counts as running for docker, not here)
running() { [ "$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" = running ]; }
day_of() { docker image inspect -f '{{.Created}}' "$1" 2>/dev/null | cut -c1-10; }
# the commit an image was built from, as its labels say (ci's images have it), first 7
rev_of() { docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$1" 2>/dev/null | cut -c1-7; }
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
# whether the registry has image:tag or image@digest: 0 yes, 1 it says it hasn't (not found, not allowed), 2 no answer
# (no network, the registry down or slow)
in_registry() {
  local out
  out=$(timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>&1) && return 0
  case $out in *"not found"* | *denied* | *nauthorized* | *" 401 "* | *" 403 "* | *" 404 "*) return 1 ;; esac
  return 2
}
# an image built or loaded here, one its registry doesn't have: it can't be downloaded again (0). (with containerd's
# image store a build here has a repo digest too, its own id.) 2 when the registry didn't answer: no telling
built_here() {
  local d rc=0
  case $(docker image inspect -f '{{len .RepoDigests}}' "$1" 2>/dev/null) in "") return 1 ;; 0) return 0 ;; esac
  for d in $(digests "$1"); do
    in_registry "$d"
    case $? in 0) return 1 ;; 2) rc=2 ;; esac
  done
  return $rc
}
# the registry's digest an image came with from repository $2, empty for one built here
digest_of() { digests "$1" | tr ' ' '\n' | awk -F@ -v r="$2" '$1 == r {print $2; exit}'; }
# where an image can be had again from repository $2 by its digest: <repo>@<digest>
prev_of() {
  local d
  d=$(digest_of "$1" "$2")
  [ -n "$d" ] && echo "$2@$d"
}
# whether a version of a part is left out because it didn't start: an image id or a registry's digest, any of the words
# of <part>_failed (its image id and each digest it has in its repository, or only some of them)
failed_has() { [ -n "$2" ] && case " $(get "$1_failed") " in *" $2 "*) true ;; *) false ;; esac; }
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
# owner/repo and the branch of a github context (as context_of says it), empty for anything else
source_of() {
  printf '%s' "$1" | sed -n 's|^https://github\.com/\([A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*\)\.git\(#\([A-Za-z0-9_./-]*\)\)\{0,1\}$|\1 \3|p'
}

# --- the parts ---

# what's there to look after, written to the status: "<id>:<container>:<kind> ...", the name of each (<id>_name).
# kind build: from a github context, local: built from a copy here (left as it is), image: from a registry. ($2 its id:
# without an answer from its registry it stays what it was)
kind_of() {
  local ctx
  ctx=$(context_of "$1")
  [ -n "$(source_of "$ctx")" ] && echo build && return
  # (a stack with image: and build: . both, like MowBite's, is from its registry as long as that has its tag)
  if [ -n "$ctx" ]; then
    in_registry "$(ref_of "$1")"
    case $? in
    1) echo local && return ;;
    2) [ -n "$2" ] && kind "$2" | grep -xE 'image|local' && return ;;
    esac
  fi
  echo image
}
# a running container it would look after but can't reach: "<container>@<its stack's folder>" (- when it wasn't
# started from a compose file), for its page to say why it's missing
away() { running "$1" && printf ' %s@%s' "$1" "$(label "$1" project.working_dir | grep . || echo -)"; }
# the folders it reaches, as mounted into it (the stacks' folder, by default /opt/stacks)
reach() { docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$ME" 2>/dev/null | tr ' ' '\n' | grep -vE '^(/var/run/docker\.sock|/etc/localtime|/host/.*|)$' | tr '\n' ' '; }
find_parts() {
  local out="" c x id far="" picked cand mine
  # (itself, also by its image: under another name it isn't an app to update from inside)
  mine=$(repo_of "$(ref_of "$ME")")
  # (one removed for OpenMower's update without a copy that's there again: its note goes, not while they're removed, nor
  # on the way to MowBite OS or back)
  case $(get nokeep_openmower) in
  rm\ *) ;;
  *) [ -n "$(get switch_os)" ] || gone_list | while read -r x c; do exists "$c" && status "$x"; done ;;
  esac
  # (left by a stop right before such an update started)
  if ! nokeep_busy; then
    status nokeep_holders
    [ -n "$(get pending_openmower)" ] || status openmower_fw_check
  fi
  if { exists "$OM" || gone "$OM"; } && in_compose "$OM"; then
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
    exists "$c" || gone "$c" || continue
    in_compose "$c" || { far="$far$(away "$c")"; continue; }
    if [ "$c" = "$APP" ]; then id=mowbite; else id=planner; fi
    out="$out $id:$c:$(kind_of "$c" "$id")"
    status "${id}_gate" mower
  done
  status mowbite_name MowBite
  status planner_name "MowBite Planner"
  # the apps labelled mowbite.update=on, and the ones picked on its page (conf picked). (picked ones said anew each time)
  picked=" $(conf picked none | tr ',' ' ') "
  sed -n 's/^\(c_[a-z0-9_]*_picked\) .*/\1/p' "$STATUS" 2>/dev/null | while read -r x; do status "$x"; done
  for c in $({
    docker ps -a --filter "label=$L=on" --format '{{.Names}}'
    for x in $picked; do exists "$x" && case $(repo_of "$(ref_of "$x")") in *mosquitto*) ;; *) echo "$x" ;; esac; done
    gone_list | cut -d' ' -f2
  } | awk '!seen[$0]++'); do
    case $c in "$OM" | "$APP" | "$PLANNER" | "$ME") continue ;; esac
    [ -n "$mine" ] && [ "$(repo_of "$(ref_of "$c")")" = "$mine" ] && continue
    in_compose "$c" || { far="$far$(away "$c")"; continue; }
    id=c_$(echo "$c" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_' | cut -c1-30)_$(printf '%s' "$c" | md5sum | cut -c1-4)
    out="$out $id:$c:$(kind_of "$c" "$id")"
    status "${id}_name" "$(own "$c" name | tr -d '\n' | cut -c1-40 | grep . || echo "$c")"
    if [ "$(own "$c" gate)" = none ]; then status "${id}_gate" none; else status "${id}_gate" mower; fi
    # (picked, not labelled: it can be taken out on its page again)
    case $picked in *" $c "*) [ "$(docker inspect -f "{{index .Config.Labels \"$L\"}}" "$c" 2>/dev/null)" = on ] || status "${id}_picked" yes ;; *) status "${id}_picked" ;; esac
  done
  # what can be picked: the other running containers of the stacks it reaches, not the mqtt broker (it tells whether the
  # mower is idle in its dock)
  cand=""
  for c in $(docker ps --format '{{.Names}}'); do
    case " $out " in *":$c:"*) continue ;; esac
    case $c in "$ME" | "$SELF") continue ;; esac
    x=$(repo_of "$(ref_of "$c")")
    [ -n "$mine" ] && [ "$x" = "$mine" ] && continue
    case $x in *mosquitto*) continue ;; esac
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
# only while the mower is idle in the dock (gate mower), or whenever (gate none: mowbite.update.gate=none). a build
# removed with OpenMower's version before also while nothing can drive the mower (gate still)
gate() {
  if [ "$(get "$1_gate")" = none ]; then
    echo none
  elif [ "$(kind "$1")" = build ] && gone "$(box "$1")"; then
    echo still
  else
    echo mower
  fi
}
# whether a gate lets a part be built or restarted right now
gate_ok() { case $1 in none) return 0 ;; still) still ;; *) docked ;; esac; }
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

# --- files of the stacks ---

# a file of a part's stack changed by a sed expression: kept once as it was (.before-update), written whole and moved in
# place, with the owner and the rights it had, never through a link. what it wrote is noted (changed_<part> <file>
# <md5> and each line it changed, "<before>:<after>" in base64), so only that change is ever put back. 1: nothing changed
change_file() {
  local tmp lines
  [ -f "$2" ] && [ ! -L "$2" ] || return 1
  tmp=$(mktemp "$2.XXXXXX") || return 1
  if cp -p "$2" "$tmp" && mv "$tmp" "$2.before-update" && tmp=$(mktemp "$2.XXXXXX") && sed "$3" "$2" > "$tmp" &&
    chown "$(stat -c %u:%g "$2")" "$tmp" && chmod "$(stat -c %a "$2")" "$tmp" && mv "$tmp" "$2"; then
    lines=$(awk 'NR == FNR {a[FNR] = $0; next} a[FNR] != $0 {print a[FNR]; print}' "$2.before-update" "$2" |
      while IFS= read -r a && IFS= read -r b; do printf '%s:%s ' "$(printf '%s' "$a" | base64 -w 0)" "$(printf '%s' "$b" | base64 -w 0)"; done)
    # shellcheck disable=SC2086
    status "changed_$1" "$2" "$(md5sum < "$2" | cut -d' ' -f1)" $lines
    return 0
  fi
  rm -f "$tmp"
  return 1
}
# a part's change put back, or kept for good. either way the copy goes. the file as it wrote it: the copy back whole.
# changed since (in dockge meanwhile): only its own lines back, where they're still as it wrote them
undo_change() {
  local tmp map x
  # shellcheck disable=SC2046
  set -- "$1" $(get "changed_$1")
  [ -n "$2" ] && [ -f "$2.before-update" ] && [ ! -L "$2" ] || return 0
  tmp=$(mktemp "$2.XXXXXX") || return 1
  if [ "$(md5sum < "$2" | cut -d' ' -f1)" = "$3" ]; then
    if cp -p "$2.before-update" "$tmp" && mv "$tmp" "$2"; then
      log "$1: $2 back as it was"
      keep_change "$1"
      return 0
    fi
  elif [ $# -le 3 ]; then
    log "$1: $2 was changed since, left as it is"
    rm -f "$tmp"
    keep_change "$1"
    return 0
  else
    map=$(mktemp)
    for x in $(get "changed_$1" | cut -d' ' -f3-); do
      printf '%s\n%s\n' "$(printf '%s' "${x%%:*}" | base64 -d)" "$(printf '%s' "${x#*:}" | base64 -d)"
    done > "$map"
    if awk 'NR == FNR {if (FNR % 2) b = $0; else back[$0] = b; next} ($0 in back) {print back[$0]; next} {print}' "$map" "$2" > "$tmp" &&
      chown "$(stat -c %u:%g "$2")" "$tmp" && chmod "$(stat -c %a "$2")" "$tmp" && mv "$tmp" "$2"; then
      rm -f "$map"
      log "$1: $2 was changed since, only its own change put back"
      keep_change "$1"
      return 0
    fi
    rm -f "$map"
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

# the image part $3 ran before, kept under a tag of its own in its repository $1: rb-<part>-<time>-<image>
keep_back() {
  t=$1:rb-$3-$(now)-$(echo "$2" | sed 's/^sha256://' | cut -c1-8)
  docker tag "$2" "$t" && echo "$t"
}
# nothing changed after all: the tag back on the image kept, the rollback tag made for it gone
undo_back() {
  docker tag "$1" "$2" 2> /dev/null
  docker rmi "$1" > /dev/null 2>&1
}
# a part's rollback tags in its repository $2, newest first: "<tag> <image id>" a line. its own, and the ones without a
# part in them (rb-<time>-<image>) while no other part runs from that repository
backs() {
  local o old='|^rb-[0-9]'
  for o in $(part_ids); do
    [ "$o" != "$1" ] && [ "$(repo_of "$(ref_of "$(box "$o")")")" = "$2" ] && old=
  done
  docker images --no-trunc --format '{{.Tag}} {{.ID}}' "$2" | grep -E "^rb-$1-[0-9]$old" |
    awk '{t = $1; sub(/^rb-([a-z][a-z0-9_]*-)?/, "", t); print t + 0, $0}' | sort -k1,1nr | cut -d' ' -f2-
}
# a tag a part ran from before it moved to another one (a channel, a stable release), gone once nothing names it: no
# compose file of the stacks, no container. the image itself goes only with its last tag (its rollback tag keeps it)
drop_tag() {
  local r
  r=$(printf '%s\n' "$1" | awk '{sub(/^docker\.io\/library\//, ""); sub(/^docker\.io\//, ""); n = split($0, p, "/"); if (!index(p[n], ":")) $0 = $0 ":latest"; print}')
  case " $(compose_refs | tr '\n' ' ') $(docker ps -aq | xargs -r docker inspect -f '{{.Config.Image}}' 2>/dev/null | tr '\n' ' ') " in
  *" $1 "* | *" $r "*) return 0 ;;
  esac
  docker rmi "$1" > /dev/null 2>&1 && log "removed $1, nothing uses it any more"
}

# --- data kept before an update ---

# the newest copies of a part's data kept, on the mower only: mower_params.yaml has the ntrip login
KEEP_DATA=2
ROOM_DATA=100
# what a part mounts at $2: a volume's name or the host's path
mounts() { docker inspect -f '{{range .Mounts}}{{.Type}}|{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}|{{.Destination}}|{{.RW}}{{println}}{{end}}' "$1" 2> /dev/null; }
mount_at() { mounts "$1" | awk -F'|' -v d="$2" -v p="$3" '$3 == d && $2 != "" {print $2 "|" p; exit}'; }
# the data of part $1, "<what to mount>|<path in it>" a line: OpenMower its map and mower_params.yaml, MowBite its /data
data_of() {
  case $1 in
  openmower)
    mount_at "$OM" /data/ros map.json
    calib_where
    ;;
  mowbite) mount_at "$(box mowbite)" /data . ;;
  esac
}
# data.sh in a helper of its own image without network: $1 "<what to mount>|<piece>" at /s (read-only, but to put
# back), a kept copy's folder $4 to put back from or a new one's to keep in (an export to swap in). what it says
data_run() {
  local w="$1" what="$2" n="$3" dir="$4" mode=ro at=/o
  case $what in put | swap) mode=rw at=/b:ro ;; esac
  # shellcheck disable=SC2086
  docker run --rm --network none --pull never -v "${w%|*}:/s:$mode" ${dir:+-v "$dir:$at"} --entrypoint sh "$(image_of "$ME")" \
    /data.sh "$what" "$n" "${w##*|}"
}
# part $1's data before an update or before data is put back ($2: update or put): each piece as a tar read by a helper
# of its own image that sees it read-only, with what it holds and the sha256 of all of it. the folder gets its name
# only once all of it is there ($kept then). of each part the newest two stay, and the one about to be put back ($3).
# 1 when it has data that can't be kept
keep_data() {
  local list dir tmp i=0 w bad=
  kept=
  list=$(data_of "$1")
  [ -n "$list" ] || return 0
  room_for "$ROOM_DATA" || { log "$1: not enough room to keep its data ($(free_mb) MB free)"; return 1; }
  # (a second one within the same second)
  while dir=$DATA/$1-$(now) && [ -e "$dir" ]; do sleep 1; done
  tmp=$dir.new
  rm -rf "$DATA/$1-"*.new
  mkdir -p "$DATA" && chmod 700 "$DATA" && mkdir -m 700 "$tmp" && echo "$2" > "$tmp/why" || return 1
  # (a path that isn't there, a map not saved yet: nothing to keep of it)
  while IFS= read -r w; do
    i=$((i + 1))
    data_run "$w" keep "$i" "$tmp" > /dev/null 2>> "$LOG"
    case $? in
    0) printf '%s %s\n' "$i" "$w" >> "$tmp/what" ;;
    3) ;;
    *) bad=1 && break ;;
    esac
  done << EOF
$list
EOF
  [ -z "$bad" ] && [ -s "$tmp/what" ] && { (cd "$tmp" && sha256sum -- *.tar > sha256) && sync && mv "$tmp" "$dir" && kept=$dir || bad=1; }
  rm -rf "$tmp"
  [ -z "$bad" ] || { log "$1: its data can't be kept"; return 1; }
  [ -z "$kept" ] || log "$1: its data kept in $dir"
  data_dirs "$1" | awk -v k=$KEEP_DATA -v s="$3" 'NR > k && $0 != s' | while IFS= read -r w; do rm -rf "$w"; done
  return 0
}
# part $1's data back from the folder $2: the copy checked against its sha256, the part stopped, what it has now kept
# first (nothing goes without a copy), then each piece unpacked next to it and moved over it and read again against
# what was kept. the part isn't started again here. a stop halfway is done again at the next start (data_put). 1 when
# it can't: before anything changed, or the log says what went wrong
put_data() {
  local p="$1" dir="$2" n w mounted
  [ -s "$dir/what" ] && (cd "$dir" && sha256sum -c -s sha256) || { log "$p: the data kept in $dir doesn't match its sha256, nothing put back"; return 1; }
  # (only where it was kept from: the part still mounts it there)
  mounted=$(data_of "$p")
  while read -r n w; do
    printf '%s\n' "$mounted" | grep -qxF -- "$w" || { log "$p: it doesn't mount ${w%|*} any more, nothing put back"; return 1; }
  done < "$dir/what"
  room_for $(($(du -sm "$dir" | cut -f1) + ROOM_DATA)) || { log "$p: not enough room to put its data back ($(free_mb) MB free)"; return 1; }
  status data_put "$p" "$dir"
  docker stop "$(box "$p")" > /dev/null 2>&1
  if ! keep_data "$p" put "$dir"; then
    status data_put
    log "$p: what it has now can't be kept, nothing put back"
    return 1
  fi
  status data_put "$p" "$dir" "${kept:--}"
  data_back "$p" "$dir"
}
# the putting back itself, also again after a stop halfway
data_back() {
  local n w bad=
  progress "$1" data
  if [ -s "$2/what" ]; then
    while read -r n w; do
      data_run "$w" put "$n" "$2" > /dev/null 2>> "$LOG" || bad=1
    done < "$2/what"
  else
    bad=1
  fi
  status data_put
  [ -z "$bad" ] || { log "$1: its data couldn't all be put back from $2"; return 1; }
  log "$1: its data put back from $2"
}
# the newest data of part $1 kept before an update, when a schema it has is higher now than then: the new version
# changed its format, the version before may not read it
newer_data() {
  local d n w was is
  d=$(data_dirs "$1" update | head -n1)
  [ -n "$d" ] || return 1
  while read -r n w; do
    was=$(grep -x '[0-9][0-9]*' "$d/$n.schema" 2> /dev/null) || continue
    is=$(data_run "$w" schema "$n" 2> /dev/null | grep -x '[0-9][0-9]*')
    if [ -n "$is" ] && [ "$is" -gt "$was" ]; then
      log "$1: the format of its data went from $was to $is"
      echo "$d"
      return 0
    fi
  done < "$d/what"
  return 1
}
# a part started again on the image it has
restart_same() { restart "$1" "$(image_of "$(box "$1")")"; }
# by hand from its page: part $1's data kept at $2 back, idle in the dock with MowBite's schedule held (not in the 30
# minutes before it may start the mower), the part started again on what it ran
put_by_hand() {
  local p="$1" dir="$DATA/$1-$2" at ran=
  [ -d "$dir" ] || { log "$p: no data kept at $2"; outcome "$p" error no_data; return 1; }
  if at=$(soon); then
    log "$p: MowBite's schedule may start the mower at $(date -d "@$at" '+%F %T'), its data isn't put back until then"
    outcome "$p" error schedule "$at"
    return 1
  fi
  hold "$p" || { outcome "$p" error hold; return 1; }
  if ! docked; then
    unhold
    log "$p: the mower left the dock, its data isn't put back"
    outcome "$p" error not_docked
    return 1
  fi
  # (one that was stopped stays so)
  running "$(box "$p")" && ran=1
  if put_data "$p" "$dir"; then
    [ -z "$ran" ] || restart_same "$p" || log "$p: doesn't answer after its data was put back"
    outcome "$p" data_back "$(now)" "$2"
  else
    [ -z "$ran" ] || running "$(box "$p")" || restart_same "$p"
    outcome "$p" error data_put
  fi
  unhold
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
# meanwhile, for a part that waits for it (its gate $2; compose is stopped then: a build takes the mower's cpu)
with_progress() {
  local part="$1" g="$2" watch rc
  shift 2
  rm -f "$STATE/left"
  if [ "$g" != none ]; then
    (while sleep 30; do gate_ok "$g" || { : > "$STATE/left"; pkill -f -- '--progress json'; exit 0; }; done) &
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
# MB the layers of file $1 take packed and what pulling them needs: x5 and 1 GB more
layers_mb() { awk '{s += $2} END {printf "%d\n", s / 1048576}' "$1"; }
pull_mb() { awk '{s += $2} END {printf "%d\n", s * 5 / 1048576 + 1024}' "$1"; }

# the layers of the newest image of ref for this machine as docker keeps them (its diff ids), one a line. (an image for
# one platform only has no list of platforms to pick from)
diff_ids() {
  { timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format "{{json (index .Image \"linux/$(arch)\").RootFS.DiffIDs}}" 2>/dev/null ||
    timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{json .Image.RootFS.DiffIDs}}' 2>/dev/null; } | tr -d '[]" ' | tr ',' '\n' | grep .
}
# the MB the newest image of ref needs that the local image doesn't have yet: its missing layers, packed size x5.
# nothing when any of it can't be had: then there's no telling, and that's no room. its layers from the file $3 when
# they were just looked up
need_mb() {
  have=$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$2" 2>/dev/null)
  ids=$(mktemp)
  sizes=$(mktemp)
  diff_ids "$1" > "$ids"
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
  elif failed_has "$1" "$remote"; then
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
# minutes, a built one within five, OpenMower within six. OpenMower after its update (openmower_fw_check on) also with
# the motors not kept off for the firmware, at least not for longer than a minute after it answers (fw_failed then). 1
# when compose can't start it or it doesn't answer. never built or pulled here: the image is there already (pulled,
# built or the one before), a planner with pull_policy: build would be built once more and run on an image nobody
# checked, one with pull_policy: always would get the new one back
restart() { start_part "$1" && seen "$1" "$2"; }
# started, without a look whether it runs
start_part() {
  local force=
  progress "$1" restart
  # (one that runs an image that isn't there any more is made anew: compose takes it for the same and leaves it)
  docker image inspect "$(image_of "$(box "$1")")" > /dev/null 2>&1 || force=1
  compose $T_UP "$(box "$1")" up -d --no-deps --no-build --pull never ${force:+--force-recreate} "$(service "$(box "$1")")" >> "$LOG" 2>&1 || { log "$1: compose couldn't start it"; return 1; }
  rehold
}
seen() {
  local c end ok how started s fw=
  fw_failed=
  c=$(box "$1")
  how=$(check_of "$1")
  # (a healthcheck may take a while between its tries)
  case $(kind "$1"):$how in openmower:*) end=360 ;; build:* | *:health) end=300 ;; *) end=120 ;; esac
  end=$(($(up) + end))
  ok=0
  started=
  while [ "$(up)" -lt "$end" ]; do
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
      if [ "$how" = mqtt ] && [ $ok -ge 2 ]; then
        [ "$(get openmower_fw_check)" = on ] && fw_blocked || return 0
        [ -n "$fw" ] || fw=$(up)
        [ $(($(up) - fw)) -lt 60 ] || break
      fi
    else
      ok=0
    fi
  done
  if [ -n "$fw" ]; then
    fw_failed=1
    log "$1: the motors stay off, it needs newer firmware (openmower update-firmware)"
  fi
  return 1
}

# the new version of a part didn't run: back to the one before ($2, a rollback tag) under its tag ($3), the file it
# changed put back, its data too when the new version raised its schema, started again. OpenMower and builds only while
# OpenMower doesn't drive the mower, else left for the next run to look at (1). the version left out from now on ($4)
# whatever the mower does, it may be started again: an app only to look at, the mqtt broker (the mower drives on without
# it, and without it nothing says the mower is idle), or one set to update with the mower out
harmless() {
  case $1 in mowbite | xtechapp | openmowerapp) return 0 ;; esac
  case $(repo_of "$(ref_of "$(box "$1")")") in *mosquitto*) return 0 ;; esac
  [ "$(gate "$1")" = none ]
}
go_back() {
  local fw="$fw_failed" d data=
  if ! harmless "$1" && ! quiet; then
    log "$1: didn't run as it should, but the mower isn't idle (or there's no broker): nothing restarted, looked at again next time"
    outcome "$1" unconfirmed
    return 1
  fi
  log "$1: didn't run as it should, back to $2"
  progress "$1" back
  [ -n "$4" ] && status "$1_failed" "$4"
  # (OpenMower: left out for the firmware, tried again when asked. the one before isn't checked for it, it ran so)
  if [ "$1" = openmower ]; then
    status openmower_fw_check
    if [ -n "$fw" ]; then status openmower_fw "${4##* }"; else status openmower_fw; fi
  fi
  docker tag "$2" "$3"
  undo_change "$1"
  # (its data in a format the new version raised: back as it was before the update, what it has now kept too)
  d=$(newer_data "$1") && if put_data "$1" "$d"; then data=data; else data=failed; fi
  if ! restart "$1" "$(id_of "$2")"; then
    outcome "$1" error rollback
  elif [ "$data" = failed ]; then
    outcome "$1" error data_put
  else
    outcome "$1" rolled_back ${fw:+"firmware"} ${data:+"$data"}
  fi
  status "pending_$1"
  return 0
}

# the parts restarted on a new version and not seen running yet (a run stopped right then, or the mower wasn't idle):
# started if a restart was cut off, then seen running, or back to the one before
settle() {
  local p x left
  for p in $(part_ids); do
    # (pending: the rollback tag, the tag it goes back under, the image it has to run on, what's left out when it doesn't:
    # an image id and its digest, or a commit and the id of its base)
    # shellcheck disable=SC2046
    set -- $(get "pending_$p")
    [ -n "$1" ] || continue
    left=$(get "pending_$p" | cut -d' ' -f4-)
    # (OpenMower and builds: with the schedule held)
    case $(kind "$p") in openmower | build) hold "$p" || continue ;; esac
    if ! harmless "$p" && ! quiet; then
      unhold
      log "$p: still to be seen running, the mower isn't idle, later"
      continue
    fi
    log "$p: was restarted on a new version and not seen running, looking now"
    if restart "$p" "${3:-$(id_of "$2")}"; then
      log "$p: runs"
      keep_change "$p"
      status "pending_$p"
      outcome "$p" updated "$(now)"
      if [ "$p" = openmower ]; then
        status openmower_fw_check
        status openmower_fw
        x=$(prev_of "$1" "$(repo_of "$2")")
        status openmower_prev ${x:+"$x"}
        rebuild_on_om "$(ref_of "$OM")"
      fi
      # (another tag than before, a channel or a stable release: the one before goes once nothing names it)
      [ "$(ref_of "$(box "$p")")" = "$2" ] || drop_tag "$2"
    else
      go_back "$p" "$1" "$2" "${left:-$(id_of "$2")}"
    fi
    unhold
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
  if [ -n "$(newest_back "$1" "$repo" "$(image_of "$c")")" ]; then status "$1_back" yes; else status "$1_back" no; fi
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
# what a part runs in words: MowBite's own version, else its image's tag. MowBite without an answer right now: the
# version it said last on the same image (mowbite_version <image> <version>), the tag only for one that never says it
version_of() {
  local v img
  if [ "$1" = mowbite ]; then
    img=$(image_of "$(box "$1")")
    v=$(wget -q -T 5 -O - "$(url_of "$(box "$1")" :8080/cgi-bin/version)" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    if [ -n "$v" ]; then
      [ "$(get mowbite_version)" = "$img $v" ] || status mowbite_version "$img" "$v"
    else
      v=$(get mowbite_version | sed -n "s/^$img //p")
    fi
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
# the newest rollback tag of part $1 (in its repository $2) on another image than the one that runs ($3), to go back to
# by hand
newest_back() {
  backs "$1" "$2" | while read -r t id; do
    [ "$id" = "$3" ] || { echo "$t"; break; }
  done
}

update_image() {
  local p="$1" c current repo before target back pulled file v need remote d
  c=$(box "$p")
  progress "$p" prepare
  running "$c" || { log "$p: not running, left as it is"; outcome "$p" stopped; return 0; }
  current=$(ref_of "$c")
  repo=$(repo_of "$current")
  before=$(image_of "$c")
  # (asked for, it's the same either way: no need to ask the registry)
  if [ -z "$MANUAL" ]; then
    built_here "$before"
    case $? in
    0)
      log "$p: runs an image built here, left as it is (only updated when asked)"
      outcome "$p" local
      return 0
      ;;
    2)
      log "$p: no answer from its registry, left as it is"
      outcome "$p" error registry
      return 1
      ;;
    esac
  fi
  target=$(image_target "$p")
  [ -n "$target" ] || { log "$p: no stable release"; outcome "$p" error no_stable; return 1; }
  # never back to an older version by picking stable: that one stays until a newer stable is out
  if [ "$(channel "$p")" = stable ] && older "${target##*:}" "$(version_of "$p")"; then
    log "$p: stable ${target##*:} is older than $(version_of "$p") that runs, it stays as it is"
    outcome "$p" stable_older "${target##*:}"
    return 0
  fi
  # nothing downloaded for what runs already, or for a version that didn't start before
  remote=$(remote_digest "$target")
  if [ -n "$remote" ] && [ "$target" = "$current" ] && known_as "$before" | grep -q "@$remote"; then
    outcome "$p" current
    # (its card right away, not only after the next look)
    status "${p}_available" no "$target"
    return 0
  fi
  if failed_has "$p" "$remote"; then
    log "$p: not again, $target didn't start before"
    outcome "$p" skipped_failed
    return 0
  fi
  # room for what it has to download (its missing layers x5, else as much as the image that runs) and some to spare.
  # (the layers looked up once: for the room and the bar)
  layers "$target" > "$STATE/layers"
  need=$(need_mb "$target" "$before" "$STATE/layers")
  [ -n "$need" ] || need=$(($(image_bytes "$before") / 1048576))
  room_for $((need + ROOM_APP)) || { log "$p: not enough room (needs $need MB and $ROOM_APP to spare, $(free_mb) MB free), nothing changed"; outcome "$p" nospace "$need" "$(free_mb)"; return 1; }
  # kept before anything moves its tag (an image only built here is gone once its tag is on another one)
  back=$(keep_back "$repo" "$before" "$p")
  [ -n "$back" ] || { log "$p: the version before can't be kept, nothing changed"; outcome "$p" error keep; return 1; }
  with_progress "$p" "$(gate "$p")" pull_image "$target"
  case $? in
  0) ;;
  2) undo_back "$back" "$current" && return 2 ;;
  *) log "$p: pull of $target failed"; undo_back "$back" "$current"; outcome "$p" error pull; return 1 ;;
  esac
  pulled=$(id_of "$target")
  if [ "$pulled" = "$before" ] && [ "$target" = "$current" ]; then
    undo_back "$back" "$current"
    outcome "$p" current
    status "${p}_available" no "$target"
    return 0
  fi
  if failed_has "$p" "$pulled"; then
    log "$p: not again, $target didn't start before"
    undo_back "$back" "$current"
    outcome "$p" skipped_failed
    return 0
  fi
  # (left out when it doesn't start: its id, and the digests the registry knows it by)
  d=$(digests_in "$pulled" "$(repo_of "$target")")
  log "$p: kept the version before as $back"
  if [ "$target" != "$current" ]; then
    # (the tag it had before stable, to come back to on beta)
    [ "$(channel "$p")" = stable ] && [ -z "$(get "${p}_beta")" ] && status "${p}_beta" "$current"
    [ "$(channel "$p")" = beta ] && status "${p}_beta"
    file=$(stackfile "$c" "$current")
    if [ -z "$file" ] || ! change_file "$p" "$file" "s|^\([[:space:]]*image:[[:space:]]*\)$(re "$current")[[:space:]]*\$|\1$target|"; then
      log "$p: the compose file can't be changed, nothing changed"
      undo_back "$back" "$current"
      outcome "$p" error compose
      return 1
    fi
    if ! grep -q "^[[:space:]]*image:[[:space:]]*$(re "$target")[[:space:]]*\$" "$file"; then
      log "$p: the compose file didn't take the new image, nothing changed"
      undo_change "$p"
      undo_back "$back" "$current"
      outcome "$p" error compose
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
  if ! keep_data "$p" update; then
    log "$p: nothing changed"
    undo_change "$p"
    undo_back "$back" "$current"
    outcome "$p" error data
    return 1
  fi
  log "$p: $current -> $target"
  status "pending_$p" "$back" "$current" "$pulled" "$pulled" ${d:+"$d"}
  if restart "$p" "$pulled"; then
    v=$(version_of "$p")
    log "$p: updated to $v"
    keep_change "$p"
    status "pending_$p"
    outcome "$p" updated "$(now)" "$v"
    status "${p}_available" no "$target"
    [ "$target" = "$current" ] || drop_tag "$current"
    return 0
  fi
  go_back "$p" "$back" "$current" "$pulled${d:+ $d}"
  # a version picked that didn't start: its image isn't kept for nothing
  [ "$target" = "$current" ] || docker rmi "$target" > /dev/null 2>&1
  return 1
}

# back to the version before, by hand: the newest rollback tag on another image, under the tag that runs now. what ran
# is kept the same way and left out of the automatic updates. it comes back when the one before doesn't answer
back_image() {
  local p="$1" c current repo before to now_back d
  c=$(box "$p")
  current=$(ref_of "$c")
  repo=$(repo_of "$current")
  before=$(image_of "$c")
  to=$(newest_back "$p" "$repo" "$before")
  [ -n "$to" ] || { log "$p: no version before to go back to"; outcome "$p" error no_back; return 1; }
  progress "$p" back
  now_back=$(keep_back "$repo" "$before" "$p")
  [ -n "$now_back" ] || { outcome "$p" error keep; return 1; }
  log "$p: kept the version that ran as $now_back, back to $to"
  docker tag "$repo:$to" "$current"
  if restart "$p" "$(id_of "$repo:$to")"; then
    docker rmi "$repo:$to" > /dev/null 2>&1
    d=$(digests_in "$before" "$repo")
    status "${p}_failed" "$before" ${d:+"$d"}
    outcome "$p" back "$(now)" "$(version_of "$p")"
    return 0
  fi
  log "$p: the version before didn't answer, again the one that ran"
  docker tag "$now_back" "$current"
  if restart "$p" "$before"; then
    docker rmi "$now_back" > /dev/null 2>&1
    outcome "$p" error back
  else
    outcome "$p" error rollback
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
# its .env saved with another version than the one that runs gets the one that runs first (update_openmower), noted as
# openmower_saved <saved> <the one that runs>: the saved one back when nothing was restarted after all, unless the .env
# was changed since (dockge meanwhile)
om_saved_back() {
  # shellcheck disable=SC2046
  set -- $(get openmower_saved)
  status openmower_saved
  [ -n "$2" ] && [ "$(om_version)" = "$2" ] || return 0
  set_om_version "$1" && keep_change openmower && log "openmower: VERSION in $(om_env) back to $1, as it was saved"
}

# when an image was made, to the second (utc, 2026-08-31T13:23:38: compared as text): one here, one in its registry
made_here() { docker image inspect -f '{{.Created}}' "$1" 2>/dev/null | cut -c1-19; }
made_there() { timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{json .Image}}' 2>/dev/null | sed -n 's/.*"created": *"\([^"]*\)".*/\1/p' | head -n1 | cut -c1-19; }
# OpenMower's last three version lines (major.minor) from its releases on github (their feed, no api limit; OM_RELEASES
# another), each with when the image of its first release was made: "<line> <time>" a line, oldest first
om_lines() {
  local feed="${OM_RELEASES:-}" line v t
  if [ -z "$feed" ]; then
    case $1 in ghcr.io/*/*) feed=https://github.com/${1#ghcr.io/}/releases.atom ;; *) return 0 ;; esac
  fi
  wget -q -T 15 -O - "$feed" 2>/dev/null | sed -n 's|.*/releases/tag/v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*|\1|p' |
    sort -u -t. -k1,1n -k2,2n -k3,3n | awk -F. '!seen[$1 "." $2]++ {print $1 "." $2, $0}' | tail -n 3 | while read -r line v; do
    t=$(made_there "$1:$v")
    [ -n "$t" ] || t=$(made_there "$1:v$v")
    [ -n "$t" ] && echo "$line $t"
  done
}
# the line an image made at $2 belongs to: the newest one whose first release was made by then, nothing before them all
line_of() { printf '%s\n' "$1" | awk -v t="$2" 'NF == 2 && $2 <= t {l = $1} END {print l}'; }
# an update to another version line of OpenMower (1.3 to 1.4), for a word on its card before it: openmower_line
# <the line that runs, - when older than the lines known> <the new one>
check_om_line() {
  local lines from to
  status openmower_line
  lines=$(om_lines "$(repo_of "$1")")
  [ -n "$lines" ] || return 0
  to=$(line_of "$lines" "$(made_there "$2")")
  from=$(line_of "$lines" "$(made_here "$(image_of "$OM")")")
  [ -n "$to" ] && [ "$from" != "$to" ] && status openmower_line "${from:--}" "$to"
  return 0
}

# what of OpenMower's new version (its id $1) is left out besides its id when it doesn't run: the digests it came with
# from $2, the tag may have moved on since it was looked at. the registry's own ($3) last, openmower_fw goes by it: the
# classic store lists an image's digests in no fixed order
om_digests() { digests_in "$1" "$2" | tr ' ' '\n' | awk -v r="$3" 'NF && $0 != r {printf "%s%s", s, $0; s = " "} END {if (r != "") printf "%s%s", s, r}'; }

check_openmower() {
  local cur x
  if [ "$(kind openmower)" = os ]; then
    status openmower_running os
    status openmower_available os
    return
  fi
  # (its update without a copy not done yet: there's something to do, nothing to go back to)
  if nokeep_busy; then
    if gone "$OM"; then
      status openmower_running missing
    else
      status openmower_running "$(ref_of "$OM" | sed 's/.*://')" "$(day_of "$(image_of "$OM")")"
    fi
    status openmower_available yes "$(get nokeep_openmower | cut -d' ' -f2)"
    status openmower_back no
    status openmower_line
    return
  fi
  cur=$(ref_of "$OM")
  status openmower_running "${cur##*:}" "$(day_of "$(image_of "$OM")")"
  status openmower_env "$(om_version)"
  available openmower "$OM" "$(repo_of "$cur"):$(om_channel)"
  # (a newer version came meanwhile: the one left out for the firmware isn't to be tried again)
  [ -n "$remote" ] && [ -n "$(get openmower_fw)" ] && [ "$(get openmower_fw)" != "$remote" ] && status openmower_fw
  case $(get openmower_available) in yes* | switch*) check_om_line "$cur" "$(repo_of "$cur"):$(om_channel)" ;; *) status openmower_line ;; esac
  # (the version before its last update, while its registry still has it)
  x=$(get openmower_prev)
  if [ -n "$x" ] && [ "$(repo_of "$x")" = "$(repo_of "$cur")" ] && ! known_as "$(image_of "$OM")" | grep -q "@${x#*@}" && in_registry "$x"; then
    status openmower_back yes
  else
    status openmower_back no
  fi
}

# what's built on OpenMower's image ($1, its tag), built again on the one it runs now: after its update ($2 new), and
# later for one that didn't get to it (stopped halfway, the mower out). without $2 only one this updater built before,
# or one that was due on that image (<part>_rebuild: its id, noted before it waits). never while the mower isn't idle
# in the dock (a build takes its cpu), one removed with OpenMower's version before also while it's still: 2 then
rebuild_on_om() {
  local p x base rc=0
  for p in $(part_ids); do
    [ "$(kind "$p")" = build ] && [ -z "$(get "pending_$p")" ] || continue
    # (not once more in the same run)
    case " $rebuilt " in *" $p "*) continue ;; esac
    base=$(base_of "$(box "$p")")
    if [ "$base" != "$1" ]; then
      [ -n "$base" ] && [ -n "$2" ] && log "$p: built on $base, not on $1, left as it is"
      continue
    fi
    # (one removed with OpenMower's version before: built again whatever its base)
    gone "$(box "$p")" || [ "$(get "${p}_base_id")" != "$(id_of "$1")" ] || continue
    [ -n "$2" ] || [ -n "$(get "${p}_base_id")" ] || [ "$(get "${p}_rebuild")" = "$(id_of "$1")" ] || continue
    status "${p}_rebuild" "$(id_of "$1")"
    if ! case $(gate "$p") in still) still ;; *) docked ;; esac; then
      log "$p: the mower isn't idle in the dock, built on OpenMower's new version later"
      for x in $(noted); do gone "$(box "$x")" && outcome "$x" error gone_dock; done
      return 2
    fi
    build "$p" after_openmower
    [ $? -eq 2 ] && rc=2
    rebuilt="$rebuilt $p"
  done
  return $rc
}

update_openmower() {
  local ref repo before old_version want target remote need free back rc prev d pd at
  [ "$(kind openmower)" = openmower ] || return 0
  # (its update without a copy: on from where it is)
  ! nokeep_busy || { nokeep_on; return; }
  status openmower_nokeep
  progress openmower prepare
  running "$OM" || { log "openmower: not running, left as it is"; outcome openmower stopped; return 0; }
  ref=$(ref_of "$OM")
  repo=$(repo_of "$ref")
  before=$(image_of "$OM")
  # a build of its own can't be downloaded again: never replaced by itself
  if [ -z "$MANUAL" ] && built_here "$before"; then
    log "openmower: runs an image built here, left as it is (only updated when asked)"
    outcome openmower local
    return 0
  fi
  old_version=$(om_version)
  [ -n "$old_version" ] || { log "openmower: VERSION in $(om_env) can't be read, nothing changed"; outcome openmower error env; return 1; }
  want=$(om_channel)
  target=$repo:$want
  remote=$(remote_digest "$target")
  [ -n "$remote" ] || { log "openmower: can't reach the registry for $target"; outcome openmower error registry; return 1; }
  if [ "$target" = "$ref" ] && known_as "$before" | grep -q "@$remote"; then
    outcome openmower current
    status openmower_available no "$target"
    # (what's built on it and didn't get to it after its update)
    rebuild_on_om "$target"
    return
  fi
  if failed_has openmower "$remote"; then
    # (left out for the firmware: again when asked, after openmower update-firmware)
    if [ -n "$MANUAL" ] && [ "$(get openmower_fw)" = "$remote" ]; then
      log "openmower: $target once more, it was left out for the firmware"
    else
      log "openmower: not again, $target didn't come up before"
      outcome openmower skipped_failed
      return 0
    fi
  fi
  # not in the 30 minutes before MowBite's schedule may start the mower: the restart would come in between. asked again
  # before the restart, after the download
  if at=$(soon); then
    log "openmower: MowBite's schedule may start the mower at $(date -d "@$at" '+%F %T'), it stays as it is until then"
    outcome openmower error schedule "$at"
    return 2
  fi
  [ "$want" != edge ] && exists "$PLANNER" && log "openmower: $want has no OM_PLANNER=external, the MowBite Planner won't work with it"
  # (the layers looked up once: for the room and the bar)
  layers "$target" > "$STATE/layers"
  need=$(need_mb "$target" "$before" "$STATE/layers")
  free=$(free_mb)
  if [ -z "$need" ] || [ -z "$free" ] || [ $((need + 1024)) -gt "$free" ]; then
    log "openmower: not enough room for $target (needs ${need:-?} MB and 1 GB to spare, ${free:-?} MB free), it stays as it is"
    outcome openmower nospace "${need:-?}" "${free:-?}"
    # (without a copy of the version that runs: offered on its card, done when asked for)
    [ -z "$NOKEEP" ] || { nokeep_openmower "$target" "$before" "$ref" "$repo" "$remote"; return; }
    nokeep_look "$target" "$before" "$ref" "$repo"
    return 1
  fi
  back=$(keep_back "$repo" "$before" openmower)
  [ -n "$back" ] || { log "openmower: the version before can't be kept, nothing changed"; outcome openmower error keep; return 1; }
  log "openmower: kept the version before as $back"
  # its .env saved with another version than the one that runs (not started since): first the one that runs, so that's
  # what a way back puts there. the saved one comes back when it isn't restarted (om_saved_back)
  if [ "${ref##*:}" != "$old_version" ] && [ "$repo:${ref##*:}" = "$ref" ]; then
    if ! set_om_version "${ref##*:}"; then
      log "openmower: VERSION in $(om_env) can't be changed, nothing changed"
      undo_back "$back" "$ref"
      outcome openmower error env
      return 1
    fi
    keep_change openmower
    status openmower_saved "$old_version" "${ref##*:}"
    old_version=${ref##*:}
  fi
  if [ "$want" != "$old_version" ] && ! set_om_version "$want"; then
    log "openmower: VERSION in $(om_env) can't be changed, nothing changed"
    om_saved_back
    undo_back "$back" "$ref"
    outcome openmower error env
    return 1
  fi
  log "openmower: $ref -> $target (needs $need MB, $free MB free)"
  # only OpenMower itself: the stack's other containers (its app, the broker) stay as they are
  with_progress openmower mower compose $T_PULL "$OM" --progress json pull "$(service "$OM")"
  rc=$?
  # the last word before it restarts: no start of the schedule soon, the schedule held, still in the dock, and its .env
  # still says that version (dockge meanwhile)
  if [ $rc -eq 0 ] && at=$(soon); then
    log "openmower: MowBite's schedule may start the mower at $(date -d "@$at" '+%F %T'), it stays as it is until then"
    rc=5
  elif [ $rc -eq 0 ] && ! hold openmower; then
    rc=4
  elif [ $rc -eq 0 ] && ! docked; then
    log "openmower: the mower left the dock, it stays as it is"
    rc=2
  elif [ $rc -eq 0 ] && [ "$(om_version)" != "$want" ]; then
    log "openmower: VERSION in $(om_env) was changed meanwhile, it stays as it is"
    rc=3
  elif [ $rc -eq 0 ] && ! keep_data openmower update; then
    rc=6
  fi
  if [ $rc -ne 0 ]; then
    unhold
    case $rc in 2 | 3 | 4 | 5 | 6) ;; *) log "openmower: pull failed, it stays as it is" ;; esac
    undo_change openmower
    om_saved_back
    undo_back "$back" "$ref"
    # a version picked that didn't come: its image isn't kept for nothing
    [ "$target" = "$ref" ] || docker rmi "$target" > /dev/null 2>&1
    case $rc in
    2) return 2 ;;
    3) outcome openmower error env ;;
    4) outcome openmower error hold ;;
    5) outcome openmower error schedule "$at" && return 2 ;;
    6) outcome openmower error data ;;
    *) outcome openmower error pull ;;
    esac
    return 1
  fi
  # (its way back by hand: the version before, from its registry again)
  prev=$(prev_of "$before" "$repo")
  d=$(id_of "$target")
  pd=$(om_digests "$d" "$repo" "$remote")
  # (the motors kept off for the firmware already: not the new version's doing)
  if fw_blocked; then
    log "openmower: the motors are off for the firmware already, the new version isn't checked for it"
    status openmower_fw_check off
  else
    status openmower_fw_check on
  fi
  # shellcheck disable=SC2086
  status pending_openmower "$back" "$ref" "$d" "$d" $pd
  # (from here its .env keeps the version that ran, for the way back)
  status openmower_saved
  if restart openmower "$d"; then
    unhold
    log "openmower: updated to $target"
    keep_change openmower
    status pending_openmower
    status openmower_fw_check
    status openmower_fw
    status openmower_prev ${prev:+"$prev"}
    outcome openmower updated "$(now)" "$want"
    status openmower_available no "$target"
    [ "$target" = "$ref" ] || drop_tag "$ref"
    # what's built on OpenMower's image: again on the new one
    rebuild_on_om "$target" new
    return
  fi
  go_back openmower "$back" "$ref" "$d $pd"
  rc=$?
  unhold
  [ $rc -eq 0 ] || return 1
  [ "$target" = "$ref" ] || docker rmi "$target" > /dev/null 2>&1
  return 1
}

# back to the version before its last update, by hand: no copy of it is kept (GBs), it comes from its registry again by
# its digest (openmower_prev) under the tag that runs, as long as the registry has it. the version that ran is left out
# of the automatic updates, it runs again when the one before doesn't answer
back_openmower() {
  local ref repo before prev need free back d
  if nokeep_busy; then
    log "openmower: its update without a copy isn't done, that goes on first"
    outcome openmower error nokeep
    return 1
  fi
  ref=$(ref_of "$OM")
  repo=$(repo_of "$ref")
  before=$(image_of "$OM")
  prev=$(get openmower_prev)
  if [ -z "$prev" ] || [ "$(repo_of "$prev")" != "$repo" ] || known_as "$before" | grep -q "@${prev#*@}" || ! in_registry "$prev"; then
    log "openmower: no version before to go back to"
    outcome openmower error no_back
    return 1
  fi
  progress openmower prepare
  layers "$prev" > "$STATE/layers"
  need=$(need_mb "$prev" "$before" "$STATE/layers")
  free=$(free_mb)
  if [ -z "$need" ] || [ -z "$free" ] || [ $((need + 1024)) -gt "$free" ]; then
    log "openmower: not enough room for the version before (needs ${need:-?} MB and 1 GB to spare, ${free:-?} MB free), it stays as it is"
    outcome openmower nospace "${need:-?}" "${free:-?}"
    return 1
  fi
  back=$(keep_back "$repo" "$before" openmower)
  [ -n "$back" ] || { outcome openmower error keep; return 1; }
  with_progress openmower mower pull_image "$prev"
  case $? in
  0) ;;
  2) undo_back "$back" "$ref" && return 2 ;;
  *) log "openmower: pull of $prev failed"; undo_back "$back" "$ref"; outcome openmower error pull; return 1 ;;
  esac
  hold openmower || { undo_back "$back" "$ref"; outcome openmower error hold; return 1; }
  docked || { unhold; log "openmower: the mower left the dock, it stays as it is"; undo_back "$back" "$ref"; return 2; }
  log "openmower: kept the version that ran as $back, back to $prev"
  d=$(digests_in "$before" "$repo")
  docker tag "$prev" "$ref"
  if restart openmower "$(id_of "$prev")"; then
    unhold
    # (the one it left is GBs, none is kept, as after an update)
    docker rmi "$back" > /dev/null 2>&1
    status openmower_failed "$before" ${d:+"$d"}
    status openmower_prev
    outcome openmower back "$(now)" "${ref##*:}"
    rebuild_on_om "$ref" new
    return 0
  fi
  log "openmower: the version before didn't answer, again the one that ran"
  docker tag "$back" "$ref"
  if restart openmower "$before"; then
    docker rmi "$back" > /dev/null 2>&1
    outcome openmower error back
  else
    outcome openmower error rollback
  fi
  unhold
  return 1
}

# --- OpenMower without a copy ---

# OpenMower's new version ($1) without room next to the one that runs ($2, under its tag $3 from repository $4): whether
# that one can go first, for its card. nk_prev its way back, nk_holders the images with a layer of it the new one hasn't,
# nk_parts and nk_wants the builds on them ("<part> <commit> <name> <how>" a line)
# form: status openmower_nokeep yes <MB downloaded> <parts built again, commas, or -> <tags back afterwards, commas, or -> <tags gone for good, commas, or ->
# form: status openmower_nokeep no prev|env|registry|holders|room <MB needed> <MB there>|box <container>|base <part>|github <part>
nokeep_look() {
  local target="$1" before="$2" ref="$3" repo="$4" new only has need c p w back='' all
  nk_holders=
  nk_parts=
  nk_wants=
  nk_prev=$(prev_of "$before" "$repo")
  if [ -z "$nk_prev" ] || ! in_registry "$nk_prev"; then status openmower_nokeep no prev; return 1; fi
  if [ "$repo:${ref##*:}" != "$ref" ] || [ "$(om_version)" != "${ref##*:}" ]; then status openmower_nokeep no env; return 1; fi
  layers "$target" > "$STATE/layers"
  new=" $(diff_ids "$target" | tr '\n' ' ')"
  if [ ! -s "$STATE/layers" ] || [ "$new" = " " ]; then status openmower_nokeep no registry; return 1; fi
  only=$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$before" 2>/dev/null |
    awk -v n="$new" '{for (i = 1; i <= NF; i++) if (!index(n, " " $i " ")) printf "%s ", $i}')
  # (what's free, the build cache and the image that runs against the new one's layers x5 and 1 GB more)
  has=$(free_mb)
  has=$((${has:-0} + $(sed -n 's/^cache //p' "$STATE/room" 2>/dev/null | grep -x '[0-9][0-9]*' || echo 0) / 1048576))
  [ -z "$only" ] || has=$((has + $(image_bytes "$before") / 1048576))
  need=$(pull_mb "$STATE/layers")
  if [ -z "$only" ] || [ "$has" -lt "$need" ]; then status openmower_nokeep no room "$need" "$has"; return 1; fi
  nk_holders=$(holders_of "$only")
  if ! printf '%s\n' "$nk_holders" | grep -qxF -- "$before"; then status openmower_nokeep no holders; return 1; fi
  [ "$target" != "$ref" ] || back=$ref
  for c in $(boxes_on "$nk_holders"); do
    [ "$c" != "$OM" ] || continue
    p=$(build_of "$c")
    if [ -z "$p" ] || [ "$(base_of "$c")" != "$ref" ]; then status openmower_nokeep no box "$c"; return 1; fi
    # (built again on the new version only when that comes under the same tag)
    [ "$target" = "$ref" ] || { status openmower_nokeep no base "$p"; return 1; }
    w=$(rebuild_want "$p") || { status openmower_nokeep no github "$p"; return 1; }
    nk_parts="$nk_parts $p"
    nk_wants="$nk_wants$p $w
"
    back="$back,$(ref_of "$c")"
  done
  all=$(for c in $nk_holders; do tags_of "$c"; done | tr ' ' '\n' | grep . | sort -u)
  status openmower_nokeep yes "$(layers_mb "$STATE/layers")" \
    "$(printf '%s' "$nk_parts" | sed 's/^ //; s/ /,/g' | grep . || echo -)" "${back:--}" \
    "$(printf '%s\n' "$all" | awk -v k=",$back," 'NF && !index(k, "," $0 ",")' | tr '\n' ',' | sed 's/,$//' | grep . || echo -)"
}
# the images with any of the layers $1 (ids)
holders_of() {
  docker images -aq --no-trunc 2>/dev/null | sort -u | xargs -r docker image inspect -f '{{.Id}} {{range .RootFS.Layers}}{{.}} {{end}}' 2>/dev/null |
    awk -v only=" $1" '{for (i = 2; i <= NF; i++) if (index(only, " " $i " ")) {print $1; next}}'
}
# the containers on any of the images $1, there or stopped
boxes_on() {
  docker ps -aq --no-trunc 2>/dev/null | xargs -r docker inspect -f '{{.Image}} {{.Name}}' 2>/dev/null |
    awk -v h=" $(printf '%s' "$1" | tr '\n' ' ') " 'index(h, " " $1 " ") {sub(/^\//, "", $2); print $2}'
}
# what a build on OpenMower's image is built from again once that's back, "<commit> <name> <how>": github's newest, else
# the release it runs
rebuild_want() {
  local w
  w=$(want_of "$1") || w=
  [ -n "$w" ] || [ -z "$(built_of "$1")" ] || [ -z "$(get "${1}_release")" ] || w="$(built_of "$1") $(get "${1}_release") release"
  [ -n "$w" ] && echo "$w"
}
# a part's container noted before it's removed (gone_<part>), with what's to be built of it ($2). 1 when it can't be
gone_note() {
  local c ref st l s
  c=$(box "$1")
  ref=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null) && st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null) &&
    l=$(docker inspect -f "$COMPOSE_LABELS" "$c" 2>/dev/null) && s=$(service "$c") || return 1
  [ -n "$ref" ] && [ -n "$s" ] && [ -n "${l%%|*}" ] || return 1
  [ "$st" = running ] || st=stopped
  # shellcheck disable=SC2086
  status "gone_$1" "$c" "$ref" "$st" "$l" "$s" $2
  [ -n "$(get "gone_$1")" ]
}
# the builds noted for it
noted() { sed -n 's/^gone_\([a-z0-9_]*\) .*/\1/p' "$STATUS" 2> /dev/null | grep -vx openmower; }
# the ones not there again
gone_builds() {
  local p
  for p in $(noted); do gone "$(box "$p")" && printf '%s ' "$p"; done
}
# a container stopped and removed through its stack, never its volumes (no -v)
box_rm() {
  compose $T_UP "$1" rm -s -f "$(service "$1")" >> "$LOG" 2>&1
  ! exists "$1"
}
tags_of() { docker image inspect -f '{{range .RepoTags}}{{.}} {{end}}' "$1" 2>/dev/null; }
# an image deleted, each of its tags and then itself, never forced: one a container still uses stays
drop_image() {
  local t
  for t in $(tags_of "$1"); do
    docker rmi "$t" > /dev/null 2>&1 && log "removed $t"
  done
  docker rmi "$1" > /dev/null 2>&1 && log "removed $1"
  return 0
}
# its notes gone, once OpenMower is there again ($1 all: the builds' too)
nokeep_off() {
  local p
  [ -z "${1:-}" ] || for p in $(noted); do status "gone_$p"; done
  exists "$OM" && status gone_openmower
  status nokeep_openmower
  status nokeep_holders
  status nokeep_lack
  status openmower_missing
  status openmower_fw_check
}
# OpenMower's update without a copy not done
nokeep_busy() { [ -n "$(get nokeep_openmower)" ]; }
nokeep_open() { [ "$1" = openmower ] && nokeep_busy; }

# asked for: the offer, the dock, the hold, its data and its way back checked once more, all it needs noted, then on
nokeep_openmower() {
  local target="$1" before="$2" ref="$3" repo="$4" remote="$5" p ok=1 fw=on
  check_room
  if ! nokeep_look "$target" "$before" "$ref" "$repo"; then
    log "openmower: not without a copy either ($(get openmower_nokeep | cut -d' ' -f2-)), it stays as it is"
    return 1
  fi
  hold openmower || { outcome openmower error hold; return 1; }
  if ! docked; then
    unhold
    log "openmower: the mower left the dock, it stays as it is"
    return 2
  fi
  if ! keep_data openmower update; then
    unhold
    outcome openmower error data
    return 1
  fi
  # (the motors kept off for the firmware already: not the new version's doing)
  fw_blocked && fw=off
  # the last word before anything goes: the version that runs still in its registry
  if ! in_registry "$nk_prev"; then
    unhold
    log "openmower: $nk_prev can't be had from its registry right now, nothing deleted"
    outcome openmower error registry
    return 1
  fi
  for p in $nk_parts openmower; do gone_note "$p" "$(printf '%s' "$nk_wants" | sed -n "s/^$p //p")" || ok=; done
  status openmower_fw_check "$fw"
  # shellcheck disable=SC2086
  status nokeep_holders $nk_holders
  status nokeep_openmower rm "$target" "$nk_prev" "$ref" "${remote:--}"
  if [ -z "$ok" ] || ! nokeep_busy || [ -z "$(get nokeep_holders)" ]; then
    nokeep_off all
    unhold
    log "openmower: what it needs to finish can't be noted, nothing deleted"
    outcome openmower error keep
    return 1
  fi
  status openmower_nokeep
  log "openmower: $ref -> $target without a copy, the version that runs and what's built on it deleted first"
  outcome openmower replacing
  nokeep_on
}
# form: status nokeep_openmower rm|drop|new|back <new tag> <the one before by digest> <its tag> <the new one's digest, or -> [<its image id, or -> <why back>]
# on from its step: containers removed, images deleted, the new version or the one before; not seen running: again later
nokeep_on() {
  local rc
  progress openmower prepare
  case $(get nokeep_openmower | cut -d' ' -f1) in
  rm) nokeep_rm && nokeep_drop && nokeep_go ;;
  drop) nokeep_drop && nokeep_go ;;
  *) nokeep_go ;;
  esac
  rc=$?
  if exists "$OM"; then
    status openmower_missing
    ! nokeep_busy || nk_next=$(($(now) + NOKEEP_EVERY))
  fi
  return $rc
}
# the containers noted removed, the builds' first, OpenMower's last while it doesn't drive the mower. one that can't be:
# the ones removed back as they were, nothing deleted
nokeep_rm() {
  local p c at why=
  if exists "$OM"; then
    if [ -z "$held" ] && ! hold openmower; then why=hold; elif ! docked; then why=not_docked; elif at=$(soon); then why="schedule $at"; fi
  fi
  [ -n "$why" ] || for p in $(noted) openmower; do
    c=$(get "gone_$p" | cut -d' ' -f1)
    [ -n "$c" ] && exists "$c" || continue
    box_rm "$c" || { log "$p: its container $c can't be removed"; why=remove; break; }
  done
  # (the last word before the images go, also when it goes on after a stop)
  [ -n "$why" ] || in_registry "$(get nokeep_openmower | cut -d' ' -f3)" || why=registry
  if [ -n "$why" ]; then
    log "openmower: stopped before anything was deleted ($why), the containers removed come back"
    nokeep_undo || return 1
    if [ -n "$(noted)$(get gone_openmower)" ]; then outcome openmower error undo; else outcome openmower error "$why"; fi
    return 1
  fi
  status nokeep_openmower drop "$(get nokeep_openmower | cut -d' ' -f2-)"
}
# the containers removed so far made again on the images they ran on, started when they ran, the notes gone
nokeep_undo() {
  local p c
  for p in openmower $(noted); do
    c=$(get "gone_$p" | cut -d' ' -f1)
    [ -n "$c" ] && ! exists "$c" || continue
    if [ "$(get "gone_$p" | cut -d' ' -f3)" = stopped ]; then
      compose $T_UP "$c" up --no-start --no-deps --no-build --pull never "$(service "$c")" >> "$LOG" 2>&1
    else
      { [ "$p" != openmower ] || [ -n "$held" ] || hold openmower; } && restart "$p" "$(id_of "$(ref_of "$c")")"
    fi || log "$p: $c couldn't be made again"
  done
  # (the note of one that isn't there stays: its card and its update know it by that)
  for p in $(noted); do exists "$(get "gone_$p" | cut -d' ' -f1)" && status "gone_$p"; done
  unhold
  # (OpenMower not there again: its update stays and is tried again, as one whose download failed)
  if [ -n "$(get gone_openmower)" ] && ! exists "$OM"; then
    nokeep_missing
    return 1
  fi
  nokeep_off
}
# the build cache cleared (a test on a pc with builds of its own: PRUNE=0)
prune_cache() { [ "${PRUNE:-1}" = 0 ] || timeout $T_UP docker builder prune -af > /dev/null 2>&1; }
# what holds the layers of the version before deleted (twice: an image built on another goes only after it), the build
# cache cleared
nokeep_drop() {
  local i x
  for i in 1 2; do for x in $(get nokeep_holders); do drop_image "$x"; done; done
  prune_cache
  log "openmower: the version before deleted, $(free_mb) MB free"
  status nokeep_openmower new "$(get nokeep_openmower | cut -d' ' -f2-)"
  status nokeep_holders
}
# downloaded, the builds that ran on it built again, all started and seen running, else the one before the same way.
# one already there only while it doesn't mow
nokeep_go() {
  local way target prev ref remote new why pull tag left d n fw='' data=''
  # shellcheck disable=SC2046
  set -- $(get nokeep_openmower)
  way=$1 target=$2 prev=$3 ref=$4 remote=$5 new=${6:--} why=${7:-}
  [ "$remote" != - ] || remote=
  if [ "$way" = back ]; then pull=$prev tag=$ref; else pull=$target tag=$target; fi
  if exists "$OM"; then
    [ -n "$held" ] || hold openmower || { outcome openmower error hold; return 1; }
    if ! quiet; then
      log "openmower: started on $tag and not seen running yet, the mower isn't idle: looked at again later"
      outcome openmower unconfirmed
      return 2
    fi
    if [ "$way" = back ] && [ "$(image_of "$OM")" = "$new" ] && ! { gone_note openmower && box_rm "$OM"; }; then
      log "openmower: the new version's container can't be removed"
      outcome openmower error rollback
      return 1
    fi
  fi
  if [ "$way" != new ] && [ "$new" != - ]; then
    nokeep_unbuild "$new"
    drop_image "$new"
  fi
  if ! exists "$OM"; then
    # (at night only the tries due, those come by themselves)
    if [ "$WHY" = night ] && [ -n "$(get openmower_missing)" ]; then
      log "openmower: isn't on the mower, left to its next try or a tap on its card"
      return 1
    fi
    # (by hand it's then only the download and a start)
    if [ "$(om_version)" != "${tag##*:}" ] && ! { set_om_version "${tag##*:}" && keep_change openmower; }; then
      log "openmower: VERSION in $(om_env) can't be changed"
      nokeep_missing
      return 1
    fi
    log "openmower: downloading $pull"
    if ! with_progress openmower none pull_image "$pull" || { [ "$way" = back ] && ! docker tag "$prev" "$ref"; }; then
      if [ "$way" = new ] && why=$(nokeep_never "$pull"); then
        log "openmower: $target can't be downloaded ($why), back to $prev from its registry"
        status nokeep_openmower back "$target" "$prev" "$ref" "${remote:--}" - "$why"
        progress openmower back
        nokeep_go
        return
      fi
      log "openmower: the download of $pull failed"
      nokeep_missing
      return 1
    fi
  fi
  nokeep_build "$tag"
  # (held anew right before its start where a broker answers, nothing drives the mower meanwhile)
  if ! exists "$OM"; then
    unhold
    hold openmower || log "openmower: MowBite's schedule isn't held, started all the same"
  fi
  if restart openmower "$(id_of "$tag")"; then
    nokeep_off
    # (the version before started by hand under the same tag)
    if [ "$way" = new ] && digests "$(image_of "$OM")" | tr ' ' '\n' | grep -qxF "$prev"; then
      way=back
      why=hand
    fi
    if [ "$way" = new ]; then
      status openmower_fw
      status openmower_prev "$prev"
      log "openmower: updated to $target, without a copy of the version before"
      outcome openmower updated "$(now)" "${target##*:}"
      status openmower_available no "$target"
      nokeep_seen
      rebuild_on_om "$target" new
      return
    fi
    [ -z "$(get openmower_fw)" ] || fw=1
    # (its data in a format the new version raised: back as it was before the update)
    if d=$(newer_data openmower); then
      if put_data openmower "$d" && restart_same openmower; then data=data; else data=failed; fi
    fi
    if [ "$data" = failed ]; then
      outcome openmower error data_put
    elif [ -n "$why" ]; then
      outcome openmower rolled_back "$why"
    else
      outcome openmower rolled_back ${fw:+"firmware"} ${data:+"$data"}
    fi
    nokeep_seen
    rebuild_on_om "$ref" new
    return 1
  fi
  if [ "$way" = back ]; then
    # (one compose couldn't make is tried again)
    exists "$OM" || { nokeep_missing; return 1; }
    log "openmower: the version before didn't run either"
    nokeep_off
    outcome openmower error rollback
    nokeep_seen
    rebuild_on_om "$ref" new
    return 1
  fi
  # (not seen while a build it started with couldn't be built: not the new version's doing, it stays and is looked at
  # again with the build tried once more, NOKEEP_TRIES times, then back to the version before)
  if [ -n "$nk_lack" ]; then
    n=$(($(get nokeep_lack | grep -x '[0-9]*' || echo 0) + 1))
    if [ $n -lt "$NOKEEP_TRIES" ]; then
      status nokeep_lack $n
      log "openmower: $target not seen running without$nk_lack, looked at again later"
      outcome openmower unconfirmed
      return 1
    fi
    log "openmower: $target not seen running without$nk_lack after $n looks"
  fi
  # the new version didn't run: left out as after any update, the one before from its registry again
  fw=$fw_failed
  new=$(id_of "$target")
  left=$new
  d=$(om_digests "$new" "$(repo_of "$target")" "$remote")
  [ -z "$d" ] || left="$left $d"
  status openmower_failed "$left"
  status openmower_fw_check
  if [ -n "$fw" ]; then status openmower_fw "${left##* }"; else status openmower_fw; fi
  status nokeep_openmower back "$target" "$prev" "$ref" "${remote:--}" "${new:--}"
  log "openmower: $target didn't run, back to $prev from its registry"
  progress openmower back
  nokeep_go
}
# the builds removed with it that ran, built again on its tag $1 before it starts and started without a look: they wait
# for its ROS master, and with OM_PLANNER=external it doesn't come up without the planner. nk_lack the ones that couldn't
# be. a stopped one waits for OpenMower to run (rebuild_on_om)
nokeep_build() {
  local p c
  nk_lack=
  for p in $(gone_builds); do
    c=$(box "$p")
    [ "$(base_of "$c")" = "$1" ] && [ "$(gone_of "$c" | cut -d' ' -f3)" = running ] || continue
    # (not once more in the same run)
    rebuilt="$rebuilt $p"
    # shellcheck disable=SC2046
    set -- "$1" $(gone_of "$c" | cut -d' ' -f6-)
    if ! still; then
      log "$p: the mower isn't idle in the dock, built later"
      outcome "$p" error gone_dock
    elif ! room_for $ROOM_BUILD; then
      log "$p: less than $ROOM_BUILD MB free, not built"
      outcome "$p" nospace $ROOM_BUILD "$(free_mb)"
    else
      log "$p: removed with OpenMower's version before, building ($(said_of "$2" "$3" "$4")) before it starts"
      build_image "$p" "$2" still && start_part "$p" && continue
      log "$p: not built again"
      outcome "$p" error gone
    fi
    nk_lack="$nk_lack $p"
  done
}
# the builds started with it, each seen running by its own look: noted as built, else removed again
nokeep_seen() {
  local p c
  for p in $(noted); do
    c=$(box "$p")
    exists "$c" || continue
    # shellcheck disable=SC2046
    set -- $(gone_of "$c" | cut -d' ' -f6-)
    if seen "$p" "$(id_of "$(ref_of "$c")")"; then
      build_done "$p" "${1:-}" "${2:-}" "${3:-}" "$(base_of "$c")"
      log "$p: running again"
    else
      box_rm "$c"
      log "$p: didn't run on its new build, removed again"
      outcome "$p" error gone
    fi
  done
}
# the builds made on its new version ($1, while that's here) removed again with it, their notes kept: they hold its
# layers
nokeep_unbuild() {
  local p c i
  docker image inspect "$1" > /dev/null 2>&1 || return 0
  for p in $(noted); do
    c=$(box "$p")
    exists "$c" || continue
    i=$(image_of "$c")
    if box_rm "$c"; then drop_image "$i"; else log "$p: its container $c can't be removed"; fi
  done
}
# why a download of the new version can never work as it is, from what compose said since "downloading <ref>" in the
# log: no room left (nospace), its registry doesn't have it or lets nobody have it (unknown)
nokeep_never() {
  case $(awk -v m="openmower: downloading $1" 'index($0, m) {t = ""; s = 1; next} s {t = t $0 "\n"} END {printf "%s", t}' "$LOG") in
  *"no space left"*) echo nospace ;;
  *"manifest unknown"* | *"not found"* | *denied*) echo unknown ;;
  *) return 1 ;;
  esac
}
# OpenMower's container missing: said on its card with the ways by hand, tried again at the updater's start and every
# NOKEEP_EVERY seconds up to NOKEEP_TRIES times by itself (a tap starts them anew)
# form: status openmower_missing <tries> <next try, unix s, or -> <new|back, what it downloads> <the new version> <the one before by its digest> <the tag it ran under> <its stack's folder, or ->
nokeep_missing() {
  local n next=-
  n=$(get openmower_missing | cut -d' ' -f1 | grep -x '[0-9][0-9]*' || echo 0)
  case $WHY in again) n=$((n + 1)) ;; request | nokeep) n=0 ;; esac
  [ "$n" -lt "$NOKEEP_TRIES" ] && next=$(($(now) + NOKEEP_EVERY))
  # shellcheck disable=SC2046
  status openmower_missing "$n" "$next" $(get nokeep_openmower | cut -d' ' -f1-4) "$(label "$OM" project.working_dir | grep . || echo -)"
  outcome openmower error missing
  if [ "$next" = - ]; then
    log "openmower: isn't on the mower, no more tries by itself, a tap on its card goes on"
  else
    log "openmower: isn't on the mower, tried again at $(date -d "@$next" '+%F %T') (try $((n + 1)) of $NOKEEP_TRIES by itself)"
  fi
}

# --- MowBite OS instead of OpenMower ---

# MowBite OS in OpenMower's place, on a tap on its card, offered once its image is set (conf os: a tag of OS_REPO).
# OpenMower's data kept, its containers stopped with MowBite's (the OS brings its own app), its image and what's built
# on it deleted first only when the OS has no room next to it, then the OS's stack made from the files in its image with
# OpenMower's map and mower_params.yaml for its import, and seen running, else OpenMower as it was. back the same way:
# the OS's map exported into OpenMower's map.json, the OS stopped, its data_dir left as it is. never both at the board,
# nothing written to the OS's broker
OS_REPO=${MOWBITE_OS_REPO:-ghcr.io/mkaaaaaay/mowbite-os}
OS_FILES=/usr/share/mowbite-os/mower
OS_STACK=mowbite-os
# (seconds: its start period and its checks, then how long a bit that keeps it stopped may stand)
OS_WAIT=${UPDATER_OS_WAIT:-300}
OS_CALM=${UPDATER_OS_CALM:-60}
# the emergency bits 1, 8 and 12
OS_BITS=4354
# the battery in percent it takes at least
OS_BATTERY=50
# the firmware major OpenMower runs with (mower_comms_v2 keeps the motors off for any other), and the label the OS's
# image says its own with
OM_FW_MAJOR=1
OS_FW_LABEL=mowbite.xcore.firmware.major

os_ref() {
  local v
  v=$(conf os "")
  valid "$v" "$TAG" && echo "$OS_REPO:$v"
}
os_dir() { echo "$(stacks_root)/$OS_STACK"; }
# OpenMower's battery at OS_BATTERY or more (its robot_state says 0 to 1)
os_charged() {
  awk -v v="$(mqtt robot_state/json | sed -n 's/.*"battery_percentage": *\([0-9.]*\).*/\1/p')" -v m="$OS_BATTERY" 'BEGIN {exit !(v != "" && v * 100 >= m)}'
}
# the firmware major the OS's image $1 expects, from its label here or in its registry
os_fw_major() {
  if id_of "$1" > /dev/null; then
    docker image inspect -f '{{json .Config.Labels}}' "$1" 2> /dev/null
  else
    timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format "{{json (index .Image \"linux/$(arch)\").Config.Labels}}" 2> /dev/null ||
      timeout $T_REGISTRY docker buildx imagetools inspect "$1" --format '{{json .Image.Config.Labels}}' 2> /dev/null
  fi | tr -d ' \n' | awk -v k="\"$OS_FW_LABEL\":\"" '(i = index($0, k)) {s = substr($0, i + length(k)); sub(/".*/, "", s); print s}' | grep -x '[0-9][0-9]*'
}
# the board's firmware fits the OS: OpenMower runs on it (no FIRMWARE_INCOMPATIBLE, so it's OM_FW_MAJOR) and the OS's
# image expects that one
os_fw_fits() {
  fw_blocked
  [ $? -eq 1 ] && [ "$(os_fw_major "$(os_ref)")" = "$OM_FW_MAJOR" ]
}
# on its way or on the OS: OpenMower's containers stopped or about to be
os_busy() { [ -n "$(get switch_os)$(get os_ran)" ]; }
# a part left alone meanwhile: OpenMower, what was stopped or removed with it
os_parked() {
  os_busy || return 1
  [ "$(kind "$1")" = openmower ] && return 0
  case " $(get os_ran) " in *" $(box "$1"):"*) return 0 ;; esac
  [ -n "$(get "gone_$1")" ]
}
# the host's folder OpenMower has at $1 (/data/ros, /data/params), a bind mount
os_src() { mounts "$OM" | awk -F'|' -v d="$1" '$1 == "bind" && $3 == d && $2 ~ /^\// {print $2; exit}'; }
# the datum of OpenMower's map as mower_params.yaml has it, "<lat> <long> <height>" (no height: 0, as OpenMower takes it)
os_datum() {
  calib_run read ll/services/gps/datum_lat ll/services/gps/datum_long ll/services/gps/datum_height | awk '
    { gsub(/["\047]/, "", $2) }
    $2 !~ /^-?[0-9]+(\.[0-9]+)?$/ { next }
    $1 == "ll/services/gps/datum_lat" { lat = $2 }
    $1 == "ll/services/gps/datum_long" { lon = $2 }
    $1 == "ll/services/gps/datum_height" { h = $2 }
    END { if (lat == "" || lon == "") exit 1; print lat, lon, (h == "" ? 0 : h) }'
}
# a value of an env file
env_val() { { tr -d '\r' < "$1"; } 2> /dev/null | sed -n "s/^$2=//p" | tail -n1 | sed "s/^[\"']//; s/[\"']\$//"; }
# compose on the OS's stack in folder $2 within $1 seconds, its .env from there, the OS's profile on
os_compose() {
  local t="$1" dir="$2"
  shift 2
  timeout "$t" docker compose --project-directory "$dir" -f "$dir/compose.yaml" --profile os "$@"
}
# the stack's files out of image $1 into folder $2 (compose.yaml, mosquitto.conf, env.example) and its .env: the
# example's values with this mower's, "$3" as os_env has them. 1 a file isn't there, 2 its compose file doesn't take
# OpenMower's data read-only or has no export
os_files() {
  local img="$1" dir="$2" f out t
  rm -rf "$dir" && mkdir -p "$dir/export" || return 1
  for f in nx60i.compose.yaml:compose.yaml mosquitto.conf:mosquitto.conf env.example:env.example; do
    timeout $T_REGISTRY docker run --rm --network none --pull never --entrypoint cat "$img" "$OS_FILES/${f%%:*}" > "$dir/${f#*:}" 2> /dev/null &&
      [ -s "$dir/${f#*:}" ] || return 1
  done
  # shellcheck disable=SC2086
  set -- "${img##*:}" $3
  # (what was changed by hand in the stack's .env from before stays: a line that differs from the env.example it came
  # from, not one of the updater's own)
  { awk -v old="$(os_dir)/.env" -v was="$(os_dir)/env.example" -v own='^(MOWBITE_OS_TAG|MOWBITE_DATUM_LAT|MOWBITE_DATUM_LONG|MOWBITE_DATUM_HEIGHT|MOWBITE_IMPORT_ROS|MOWBITE_IMPORT_PARAMS)=' '
      function key(l) { sub(/=.*/, "", l); return l }
      BEGIN {
        while ((getline l < was) > 0) { sub(/\r$/, "", l); ex[l] = 1 }
        while ((getline l < old) > 0) { sub(/\r$/, "", l); if (l ~ /^[A-Za-z_][A-Za-z0-9_]*=/ && l !~ own && !(l in ex)) set[key(l)] = l }
      }
      { sub(/\r$/, "") }
      $0 ~ own { next }
      /^[A-Za-z_][A-Za-z0-9_]*=/ && (key($0) in set) { print set[key($0)]; delete set[key($0)]; next }
      { print }
      END { for (k in set) print set[k] }' "$dir/env.example"
    printf 'MOWBITE_OS_TAG=%s\nMOWBITE_DATUM_LAT=%s\nMOWBITE_DATUM_LONG=%s\nMOWBITE_DATUM_HEIGHT=%s\nMOWBITE_IMPORT_ROS=%s\nMOWBITE_IMPORT_PARAMS=%s\n' "$@"
  } > "$dir/.env" || return 1
  out=$(os_compose $T_REGISTRY "$dir" config 2> /dev/null) || return 1
  printf '%s\n' "$out" | grep -q '^ *target: /export$' || return 2
  for t in /import/openmower/ros /import/openmower/params; do
    printf '%s\n' "$out" | awk -v t="$t" '$1 == "-" { on = 0 } $1 == "target:" { on = ($2 == t) } on && $1 == "read_only:" && $2 == "true" { ok = 1 } END { exit !ok }' || return 2
  done
}
# whether data_dir $1 has data of the OS from before (kept): it imports OpenMower's only into one without any (import),
# or once more after an import cut off. a folder that isn't there is empty
os_kept() {
  [ -n "$1" ] && docker run --rm --network none --pull never --mount "type=bind,src=$1,dst=/d,readonly" --entrypoint sh "$(image_of "$ME")" -c '
    cd /d || exit 3
    if [ -f migrate.json ]; then grep -q "\"state\": *\"pending\"" migrate.json && exit 3; exit 0; fi
    for f in * .[!.]* ..?*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      case $f in data_schema.json | .lock | hold.json | restart-hold.json | os-session.json) ;; *) exit 0 ;; esac
    done
    exit 3' > /dev/null 2>&1
}

# form: status os_switch yes <MB downloaded> keep|drop import|kept
# form: status os_switch no image|registry|data|datum|import|files|openmower|nokeep|pending|stack|prev|room <MB needed> <MB there>
# form: status os_switch on <since, unix s>
# whether MowBite OS can take OpenMower's place, for its card. keep: next to OpenMower's image, drop: that and what's
# built on it deleted first, downloaded and built again on the way back. import: the OS takes OpenMower's map and
# mower_params.yaml, kept: its data_dir has its own from before. for the way there os_way, os_need (MB free it needs),
# os_new, os_env_now, os_prev, os_holders (what goes with drop), os_parts and os_wants (the builds on it)
os_look() {
  local ref img mb have x c p w ros params dd=''
  if os_busy; then
    os_safety
    return 1
  fi
  ref=$(os_ref) || { status os_switch; return 1; }
  os_way='' os_need=0 os_prev='' os_holders='' os_parts='' os_wants=''
  if [ "$(kind openmower)" != openmower ] || ! running "$OM"; then status os_switch no openmower; return 1; fi
  if nokeep_busy; then status os_switch no nokeep; return 1; fi
  if grep -qE '^(pending_[a-z0-9_]+|gone_[a-z0-9_]+|data_put|calib_pending|openmower_missing) ' "$STATUS" 2> /dev/null; then
    status os_switch no pending
    return 1
  fi
  # (one there that the updater didn't make)
  if [ -z "$(get os_stack)" ] && { [ -e "$(os_dir)" ] || [ -n "$(docker ps -aq ${TEST_LABEL:+--filter "label=$TEST_LABEL"} --filter label=mowbite.os 2> /dev/null)" ]; }; then
    status os_switch no stack
    return 1
  fi
  ros=$(os_src /data/ros) params=$(os_src /data/params)
  if [ -z "$ros" ] || [ -z "$params" ]; then status os_switch no data; return 1; fi
  x=$(os_datum) || { status os_switch no datum; return 1; }
  os_env_now="$x $ros $params"
  if id_of "$ref" > /dev/null; then
    mb=0
    os_files "$ref" "$STATE/os.look" "$os_env_now"
    x=$?
    dd=$(env_val "$STATE/os.look/.env" MOWBITE_DATA_DIR)
    rm -rf "$STATE/os.look"
    case $x in 0) ;; 2) status os_switch no import; return 1 ;; *) status os_switch no files; return 1 ;; esac
  else
    in_registry "$ref"
    case $? in 0) ;; 1) status os_switch no image; return 1 ;; *) status os_switch no registry; return 1 ;; esac
    layers "$ref" > "$STATE/os.layers"
    [ -s "$STATE/os.layers" ] || { status os_switch no registry; return 1; }
    mb=$(layers_mb "$STATE/os.layers")
    os_need=$(pull_mb "$STATE/os.layers")
  fi
  # (what's free, the build cache and the images nothing needs, as check_room listed them)
  have=$(free_mb)
  have=$((${have:-0} + $(awk '$1 == "cache" || ($1 == "img" && ($5 == "dangling" || $5 == "unused")) {s += ($1 == "cache" ? $2 : $3)} END {printf "%d\n", s / 1048576}' "$STATE/room" 2> /dev/null || echo 0)))
  if [ "$os_need" -le "$have" ]; then
    os_way=keep
  else
    img=$(image_of "$OM")
    os_prev=$(prev_of "$img" "$(repo_of "$(ref_of "$OM")")")
    if [ -z "$os_prev" ] || ! in_registry "$os_prev"; then status os_switch no prev; return 1; fi
    have=$((have + $(image_bytes "$img") / 1048576))
    if [ "$have" -lt "$os_need" ]; then status os_switch no room "$os_need" "$have"; return 1; fi
    os_holders=$(holders_of "$(docker image inspect -f '{{range .RootFS.Layers}}{{.}} {{end}}' "$img" 2> /dev/null)")
    for c in $(boxes_on "$os_holders"); do
      [ "$c" != "$OM" ] || continue
      p=$(build_of "$c")
      [ -n "$p" ] && [ "$(base_of "$c")" = "$(ref_of "$OM")" ] && w=$(rebuild_want "$p") || { status os_switch no prev; return 1; }
      os_parts="$os_parts $p"
      os_wants="$os_wants$p $w
"
    done
    os_way=drop
  fi
  # (the image not here: its data_dir as the stack's .env from before says)
  [ -n "$dd" ] || dd=$(env_val "$(os_dir)/.env" MOWBITE_DATA_DIR)
  if os_kept "$dd"; then os_new=kept; else os_new=import; fi
  status os_switch yes "$mb" "$os_way" "$os_new"
}

# form: status os_safety check_failed
# on the OS: a safety check of its setup failed, its lock for driving on its own closed. OpenMower doesn't know that lock
# and drives without it, the way back warns then
os_safety() {
  if [ "$(get os_switch | cut -d' ' -f1)" = on ] && [ -z "$(get switch_os)" ] && os_rpc setup.get | grep -qF '"why":"CHECK_FAILED"'; then
    status os_safety check_failed
  else
    status os_safety
  fi
}

# form: status os switched <unix s> import|kept|rolled_back pull|files|import|start|health|halt|info|state|emergency|back <unix s> map|old [lost]
# form: status os error offer|schedule <unix s>|not_docked|battery <min %>|firmware|hold|keep|pull|files|import|stop|broker|registry|busy|back|interrupted
# a tap on its card: to MowBite OS (os) or back to OpenMower (openmower)
os_switch() {
  if [ "$1" = os ]; then os_there; else os_back; fi
  status progress
}
# form: status switch_os os pull|stop|drop|start|wait
# form: status switch_os os back rolled_back|error <why>
# form: status switch_os openmower export|stop|om|data|start [map|old [lost]]
# form: status os_ran <container>:<its restart policy>:running|stopped ...
# form: status os_image <image> <its id, or -> <MB free it needs> import|kept
# form: status os_env <datum lat> <long> <height> <OpenMower's ros folder> <its params folder>
# form: status os_drop <OpenMower by its digest> <its tag> <the images deleted> ...
# form: status os_data <the folder of OpenMower's data kept before>
# the way there: the offer once more, the schedule, the dock, OpenMower's data kept and what it needs noted, then on
os_there() {
  local at p ok=1
  progress os prepare
  check_room
  if ! os_look; then
    log "os: not offered ($(get os_switch | cut -d' ' -f2-)), OpenMower stays"
    outcome os error offer
    return 1
  fi
  if at=$(soon); then
    log "os: MowBite's schedule may start the mower at $(date -d "@$at" '+%F %T'), OpenMower stays"
    outcome os error schedule "$at"
    return 1
  fi
  if ! docked; then
    log "os: the mower isn't idle in the dock, OpenMower stays"
    outcome os error not_docked
    return 1
  fi
  if ! os_charged; then
    log "os: the battery is under $OS_BATTERY %, OpenMower stays"
    outcome os error battery "$OS_BATTERY"
    return 1
  fi
  if ! os_fw_fits; then
    log "os: the board's firmware major isn't known to fit MowBite OS ($(os_ref)), OpenMower stays"
    outcome os error firmware
    return 1
  fi
  keep_data openmower update || { outcome os error keep; return 1; }
  status os_data ${kept:+"$kept"}
  # shellcheck disable=SC2086
  status os_env $os_env_now
  status os_image "$(os_ref)" - "$os_need" "$os_new"
  if [ "$os_way" = drop ]; then
    for p in $os_parts openmower; do gone_note "$p" "$(printf '%s' "$os_wants" | sed -n "s/^$p //p")" || ok=; done
    # shellcheck disable=SC2086
    status os_drop "$os_prev" "$(ref_of "$OM")" $os_holders
    if [ -z "$ok" ]; then
      os_off
      log "os: what it needs to bring OpenMower back can't be noted, OpenMower stays"
      outcome os error keep
      return 1
    fi
    status switch_os os stop
  else
    status switch_os os pull
  fi
  log "os: OpenMower -> MowBite OS ($(os_ref)), OpenMower's image $([ "$os_way" = drop ] && echo "deleted first" || echo kept)"
  os_on
}
# the way back: on the OS idle in the dock or not running, or on from where it stopped
os_back() {
  local c
  case $(get switch_os) in
  "")
    if [ -z "$(get os_ran)" ]; then
      outcome os error offer
      return 1
    fi
    c=$(os_box os)
    if [ -n "$c" ] && running "$c" && ! docked; then
      log "os: the mower isn't idle in the dock, MowBite OS stays"
      outcome os error not_docked
      return 1
    fi
    if [ -n "$(get os_drop)" ] && ! in_registry "$(get os_drop | cut -d' ' -f1)"; then
      log "os: OpenMower's version can't be had from its registry right now, MowBite OS stays"
      outcome os error registry
      return 1
    fi
    log "os: MowBite OS -> OpenMower"
    status switch_os openmower export
    ;;
  openmower\ *) log "os: back to OpenMower, on from $(get switch_os | cut -d' ' -f2)" ;;
  *) return 1 ;;
  esac
  os_on
}
# on from its step, after a stop halfway too. each step notes the next or ends it, one that can't be noted (a full
# disk) stops it. the OS still running at the stop of the way back (on after a stop halfway): idle in the dock asked
# again and its map exported anew first
os_on() {
  local c was fresh=
  while :; do
    was=$(get switch_os)
    # shellcheck disable=SC2086
    set -- $was
    case $1:$2 in
    os:pull) os_pull ;;
    os:stop) os_stop ;;
    os:drop) os_drop ;;
    os:start) os_start ;;
    os:wait) os_wait ;;
    os:back) os_undo "$3" "$(get switch_os | cut -d' ' -f4-)" ;;
    openmower:export) fresh=1 && os_export ;;
    openmower:stop)
      c=$(os_box os)
      if [ -z "$fresh" ] && [ -n "$c" ] && running "$c"; then
        if ! docked; then
          log "os: the mower isn't idle in the dock, MowBite OS stays"
          outcome os error not_docked
          return 1
        fi
        status switch_os openmower export
      else
        os_down && ! os_broker_left && status switch_os openmower om ${3:+"$3"} ${4:+"$4"} || { outcome os error stop; false; }
      fi
      ;;
    openmower:om) os_om_make && status switch_os openmower data ${3:+"$3"} ${4:+"$4"} || { outcome os error back; false; } ;;
    openmower:data) os_data ;;
    openmower:start) os_om_back ;;
    *) return 0 ;;
    esac || return 1
    if [ "$(get switch_os)" = "$was" ]; then
      log "os: its next step can't be noted, it stops at $was"
      outcome os error keep
      return 1
    fi
  done
}
# a stop halfway: before anything stopped the way there is given up, else on from its step
os_resume() {
  if [ "$(get switch_os)" = "os pull" ] && [ -z "$(get os_ran)" ]; then
    os_off
    log "os: stopped before anything changed, OpenMower stays"
    outcome os error interrupted
    return 1
  fi
  log "os: stopped halfway, on from $(get switch_os)"
  os_on
}

# the OS's image downloaded with its progress (not when it's there), the stack's files taken out of it and checked, its
# broker's image downloaded. keep: before anything stops, nothing changed when it fails. drop: OpenMower back then
os_pull() {
  local ref why=
  # shellcheck disable=SC2046
  set -- $(get os_image)
  ref=$1
  if ! id_of "$ref" > /dev/null; then
    [ "$(free_mb | grep . || echo 0)" -ge "${3:-0}" ] || os_clear
    log "os: downloading $ref"
    with_progress os none pull_image "$ref" || why=pull
  fi
  if [ -z "$why" ]; then
    os_files "$ref" "$STATE/os.new" "$(get os_env)"
    case $? in 0) ;; 2) why=import ;; *) why=files ;; esac
  fi
  [ -n "$why" ] || for ref in $(os_compose $T_REGISTRY "$STATE/os.new" config --images 2> /dev/null | grep -vxF "$1"); do
    id_of "$ref" > /dev/null || with_progress os none pull_image "$ref" || why=pull
  done
  if [ -n "$why" ]; then
    rm -rf "$STATE/os.new"
    if [ -n "$(get os_ran)" ]; then
      os_undo rolled_back "$why"
    else
      os_off
      log "os: $1 can't be had as it should ($why), OpenMower stays"
      outcome os error "$why"
    fi
    return 1
  fi
  # (import or kept once more, by the .env it starts with)
  if os_kept "$(env_val "$STATE/os.new/.env" MOWBITE_DATA_DIR)"; then set -- "$1" "$2" "$3" kept; else set -- "$1" "$2" "$3" import; fi
  status os_image "$1" "$(id_of "$1")" "$3" "$4"
  if [ -n "$(get os_ran)" ]; then status switch_os os start; else status switch_os os stop; fi
}
# what nothing needs cleared first: the build cache, images no container uses and no compose file names
os_clear() {
  local id refs r
  check_room
  prune_cache
  awk '$1 == "img" && ($5 == "dangling" || $5 == "unused") {print $2, $4}' "$STATE/room" | while read -r id refs; do
    if [ "$refs" = - ]; then
      docker rmi "$id" > /dev/null 2>&1
    else
      for r in $(echo "$refs" | tr ',' ' '); do docker rmi "$r" > /dev/null 2>&1; done
    fi
  done
  log "os: cleared what nothing needs, $(free_mb) MB free"
}
# what stops for the OS: OpenMower's stack (its broker, its apps), the builds on an image of its (also one built on a
# version before), MowBite
os_boxes() {
  local p repo
  repo=$(repo_of "$(ref_of "$OM")")
  {
    docker ps -a --filter "label=com.docker.compose.project=$(label "$OM" project)" --format '{{.Names}}' 2> /dev/null
    for p in $(part_ids); do
      [ "$(kind "$p")" = build ] && [ "$(repo_of "$(base_of "$(box "$p")")")" = "$repo" ] && box "$p"
    done
    exists "$APP" && echo "$APP"
  } | awk -v me="$ME" -v self="$SELF" 'NF && $0 != me && $0 != self && !seen[$0]++'
}
# a broker answers where OpenMower's does
os_broker() {
  mqtt mowbite/updater > /dev/null
  case $? in 0 | 27) return 0 ;; esac
  return 1
}
os_broker_left() {
  os_broker || return 1
  log "os: a broker still answers at ${MQTT_HOST:-127.0.0.1}:${MQTT_PORT:-1883}"
}
# OpenMower's containers stopped, each one's restart policy and whether it ran noted first, set to no, the brokers
# last. right before, while OpenMower runs: the hold, the dock, the schedule. afterwards no broker may answer there
os_stop() {
  local list c x at why=
  progress os stop
  if running "$OM"; then
    if [ -z "$held" ] && ! hold openmower; then
      why=hold
    elif ! docked; then
      why=not_docked
    elif ! os_charged; then
      why="battery $OS_BATTERY"
    elif ! os_fw_fits; then
      why=firmware
    elif at=$(soon); then
      why="schedule $at"
    fi
  fi
  if [ -n "$why" ]; then
    unhold
    if [ -n "$(get os_ran)" ]; then
      os_undo error "$why"
    else
      os_off
      log "os: OpenMower stays ($why)"
      # shellcheck disable=SC2086
      outcome os error $why
    fi
    return 1
  fi
  list=$(get os_ran)
  if [ -z "$list" ]; then
    for c in $(os_boxes); do
      list="$list $c:$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c" 2> /dev/null | grep . || echo no):$(running "$c" && echo running || echo stopped)"
    done
    # shellcheck disable=SC2086
    status os_ran $list
  fi
  # (the brokers last)
  for c in $(for x in $list; do case $(ref_of "${x%%:*}") in *mosquitto*) echo "1 ${x%%:*}" ;; *) echo "0 ${x%%:*}" ;; esac; done | sort -s -k1,1 | cut -d' ' -f2); do
    exists "$c" || continue
    docker update --restart=no "$c" > /dev/null 2>&1 && timeout $T_UP docker stop "$c" > /dev/null 2>&1 && ! running "$c" ||
      { log "os: $c can't be stopped"; why=stop; break; }
  done
  # (OpenMower's broker is gone, its hold with it: nothing to take back on the OS's)
  held=
  [ -n "$why" ] || ! os_broker_left || why=broker
  if [ -n "$why" ]; then
    os_undo error "$why"
    return 1
  fi
  log "os: OpenMower stopped"
  if [ -n "$(get os_drop)" ]; then status switch_os os drop; else status switch_os os start; fi
}
# drop: OpenMower's container and the builds on it removed (noted before), its image and what's built on it deleted,
# the build cache and what nothing uses cleared. its way back looked at once more while it's still there
os_drop() {
  local p c i x
  progress os drop
  # shellcheck disable=SC2046
  set -- $(get os_drop)
  if exists "$OM" && ! in_registry "$1"; then
    log "os: $1 can't be had from its registry right now, nothing deleted"
    os_undo error registry
    return 1
  fi
  for p in $(noted) openmower; do
    c=$(get "gone_$p" | cut -d' ' -f1)
    [ -n "$c" ] && exists "$c" || continue
    box_rm "$c" || { log "os: $c can't be removed"; os_undo error stop; return 1; }
  done
  shift 2
  for i in 1 2; do for x in "$@"; do drop_image "$x"; done; done
  os_clear
  status switch_os os pull
}
# the OS's stack in its folder next to the others, with their owner, started with its profile: its broker and the OS,
# their containers made anew (a stopped one keeps its log and its health's log from the time before)
os_start() {
  local dir f own
  progress os start
  dir=$(os_dir)
  if [ -d "$STATE/os.new" ]; then
    own=$(stat -c %u:%g "$(stacks_root)")
    mkdir -p "$dir/export" && chown "$own" "$dir" "$dir/export" || { os_undo rolled_back start; return 1; }
    for f in compose.yaml mosquitto.conf env.example .env; do
      cp "$STATE/os.new/$f" "$dir/.$f.new" && chown "$own" "$dir/.$f.new" && mv "$dir/.$f.new" "$dir/$f" ||
        { rm -f "$dir/.$f.new"; os_undo rolled_back start; return 1; }
    done
    rm -rf "$STATE/os.new"
  fi
  status os_stack "$(os_compose $T_REGISTRY "$dir" config 2> /dev/null | sed -n 's/^name: *//p' | head -n1)"
  if [ -z "$(get os_stack)" ] || ! os_compose $T_UP "$dir" up -d --pull never --no-build --force-recreate >> "$LOG" 2>&1; then
    log "os: compose couldn't start MowBite OS"
    os_undo rolled_back start
    return 1
  fi
  status switch_os os wait
}
# a container of the OS's stack by its service
os_box() { docker ps -a --filter "label=com.docker.compose.project=$(get os_stack)" --filter "label=com.docker.compose.service=$1" --format '{{.Names}}' 2> /dev/null | head -n1; }
# the answer to method $1 of the OS's rpc, without blanks, or nothing within 10 s
os_rpc() {
  local m="$1" id out pid n=0
  id="mowbite-updater-$$-$(now)"
  out=$(mktemp)
  set -- -h "${MQTT_HOST:-127.0.0.1}" -p "${MQTT_PORT:-1883}"
  [ -n "$MQTT_USER" ] && [ ! -s "$MQTT_OPTS" ] && set -- "$@" -u "$MQTT_USER" -P "$MQTT_PASSWORD"
  timeout 15 mosquitto_sub "$@" -t rpc/response -t rpc/error -W 12 > "$out" 2> /dev/null &
  pid=$!
  sleep 1
  timeout 10 mosquitto_pub "$@" -t rpc/request -m "{\"jsonrpc\":\"2.0\",\"method\":\"$m\",\"params\":{},\"id\":\"$id\"}" 2> /dev/null
  while [ $n -lt 10 ] && ! grep -qF "\"$id\"" "$out"; do
    sleep 1
    n=$((n + 1))
  done
  kill "$pid" 2> /dev/null
  wait "$pid" 2> /dev/null
  grep -F "\"$id\"" "$out" | tr -d ' \t' | head -n1
  rm -f "$out"
}
# system.info over its rpc says MowBite OS on the NX60i
os_info() { os_rpc system.info | grep '"name":"mowbite-os"' | grep -q '"platform":"nx60i"'; }
# the OS seen running: its container on its image, healthy (unhealthy or a halt in its health's or its own log: not),
# system.info answering, a fresh robot_state from it, and OS_CALM seconds after the first one none of the bits that keep
# it stopped. os_why what it didn't do
os_seen() {
  local c img end s first='' info='' bits h
  img=$(get os_image | cut -d' ' -f2)
  end=$(($(up) + OS_WAIT))
  os_why=start
  while [ "$(up)" -lt "$end" ] || { [ -n "$first" ] && [ "$(up)" -lt $((first + OS_CALM + 20)) ]; }; do
    sleep 10
    progress os wait
    c=$(os_box os)
    [ -n "$c" ] && [ "$(image_of "$c")" = "$img" ] && running "$c" || continue
    if { docker inspect -f '{{if .State.Health}}{{range .State.Health.Log}}{{.Output}}{{end}}{{end}}' "$c"; docker logs --tail 200 "$c"; } 2>&1 | grep -q MOWBITE_OS_HALT; then
      os_why=halt
      return 1
    fi
    h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2> /dev/null)
    [ "$h" != unhealthy ] || { os_why=health; return 1; }
    [ "$h" = healthy ] || { os_why=health; continue; }
    [ -n "$info" ] || { os_info && info=1; } || { os_why=info; continue; }
    s=$(mqtt robot_state/json)
    [ -n "$s" ] || { os_why=state; continue; }
    [ -n "$first" ] || first=$(up)
    [ $(($(up) - first)) -ge "$OS_CALM" ] || continue
    bits=$(printf '%s' "$s" | sed -n 's/.*"emergency_reason": *\([0-9]*\).*/\1/p')
    [ $((${bits:-0} & OS_BITS)) -eq 0 ] && return 0
    os_why=emergency
    return 1
  done
  return 1
}
os_wait() {
  if os_seen; then
    status os_switch on "$(now)"
    status switch_os
    log "os: MowBite OS runs on the mower ($(get os_image | cut -d' ' -f1)), OpenMower stopped"
    outcome os switched "$(now)" "$(get os_image | cut -d' ' -f4)"
    return 0
  fi
  log "os: MowBite OS didn't run as it should ($os_why)"
  os_undo rolled_back "$os_why"
}
# the way there given up: the OS stopped where it started, OpenMower's containers back as they were. $1 rolled_back (it
# had come up) or error, $2 why. OpenMower not back: noted as the way back's from the step it got to, a tap on its card
# goes on
os_undo() {
  local at=stop
  status switch_os os back "$1" "$2"
  log "os: back to OpenMower ($2)"
  progress os back
  if os_down && at=om && os_om_make && at=start && os_om_up; then
    os_off
    outcome os "$1" "$2"
    return 0
  fi
  status switch_os openmower "$at" old
  status os_switch
  log "os: OpenMower didn't come back, a tap on its card goes on"
  outcome os error back
  return 1
}
# the OS's stack stopped, not its data_dir, its restart policy as it is (stopped it stays so, compose starts it on the
# next way there). 1 while one of its containers runs
os_down() {
  local name
  name=$(get os_stack)
  [ -n "$name" ] || return 0
  progress os stop
  [ ! -f "$(os_dir)/compose.yaml" ] || os_compose $T_UP "$(os_dir)" stop >> "$LOG" 2>&1
  if [ -n "$(docker ps -q --filter "label=com.docker.compose.project=$name" 2> /dev/null)" ]; then
    log "os: MowBite OS can't be stopped"
    return 1
  fi
}
# with drop: the OS's containers and its image deleted (both don't fit), its data_dir kept, then OpenMower's container
# made again, not started, on its version from its registry by its digest under its tag
os_om_make() {
  local img
  # shellcheck disable=SC2046
  set -- $(get os_drop)
  [ -n "$1" ] && ! exists "$OM" || return 0
  progress os back
  [ ! -f "$(os_dir)/compose.yaml" ] || os_compose $T_UP "$(os_dir)" rm -s -f >> "$LOG" 2>&1
  img=$(get os_image | cut -d' ' -f1)
  [ -z "$img" ] || ! id_of "$img" > /dev/null || docker rmi "$img" > /dev/null 2>&1 || log "os: $img can't be deleted"
  os_clear
  log "os: downloading OpenMower's version again ($1)"
  if with_progress os none pull_image "$1" && docker tag "$1" "$2" &&
    compose $T_UP "$OM" up --no-start --no-deps --no-build --pull never "$(service "$OM")" >> "$LOG" 2>&1 && exists "$OM"; then
    return 0
  fi
  log "os: OpenMower can't be made again"
  return 1
}
# OpenMower's containers as they were before: their restart policies back, the ones that ran started, the brokers
# first, OpenMower last with MowBite's schedule held and with drop the builds on it built first. seen running, else 1
os_om_up() {
  local pass p x c w pol st rc n=0
  progress os back
  # (never two hosts on the board)
  if os_host; then
    log "os: MowBite OS runs again, OpenMower not started"
    return 1
  fi
  for pass in broker app openmower; do
    if [ "$pass" = app ]; then
      # (its broker up before anything asks it)
      until os_broker || [ $n -ge 20 ]; do
        sleep 1
        n=$((n + 1))
      done
    elif [ "$pass" = openmower ]; then
      # (a build still there wasn't removed: given up before the delete, not built again)
      for p in $(noted); do exists "$(box "$p")" && status "gone_$p"; done
      [ -z "$(get os_drop)" ] || nokeep_build "$(get os_drop | cut -d' ' -f2)"
      hold openmower || log "os: MowBite's schedule isn't held, OpenMower started all the same"
    fi
    for x in $(get os_ran); do
      c=${x%%:*}
      pol=${x#*:}
      st=${pol#*:}
      pol=${pol%%:*}
      if [ "$c" = "$OM" ]; then w=openmower; else case $(ref_of "$c") in *mosquitto*) w=broker ;; *) w=app ;; esac; fi
      [ "$w" = "$pass" ] && exists "$c" || continue
      docker update --restart="$pol" "$c" > /dev/null 2>&1 || log "os: $c keeps the restart policy no"
      [ "$st" = running ] || continue
      docker start "$c" > /dev/null 2>&1 || log "os: $c can't be started"
    done
  done
  seen openmower "$(image_of "$OM")"
  rc=$?
  [ -z "$(get os_drop)" ] || nokeep_seen
  unhold
  [ $rc -eq 0 ] || log "os: OpenMower doesn't answer"
  return $rc
}
# its notes gone, OpenMower there again (the stack's name stays: it's the updater's). a build not there again keeps its
# note, built when the mower is still
os_off() {
  local p
  for p in $(noted); do exists "$(box "$p")" && status "gone_$p"; done
  exists "$OM" && status gone_openmower
  for p in switch_os os_ran os_drop os_image os_env os_data os_safety; do status "$p"; done
  rm -rf "$STATE/os.new"
}

# the OS's map for OpenMower: exported into the stack's export folder (map.json, report.json with what OpenMower can't
# take: lost), map then. 2 from it (the mower isn't idle): nothing changed. else (the OS doesn't run, its export fails)
# OpenMower's data as before the way there, old
os_export() {
  local dir c rc how=old
  progress os export
  dir=$(os_dir)/export
  rm -f "$dir/map.json" "$dir/report.json"
  c=$(os_box os)
  if [ -n "$c" ] && running "$c"; then
    timeout 60 docker exec "$c" mowbite-migrate export /export >> "$LOG" 2>&1
    rc=$?
    case $rc in
    0)
      if head -c 64 "$dir/map.json" 2> /dev/null | tr -d ' \t\r\n' | grep -q '^{'; then
        how=map
        tr -d ' \t\r\n' < "$dir/report.json" 2> /dev/null | grep -qF '"lost":[]' || how="map lost"
      else
        log "os: its export has no map"
      fi
      ;;
    2)
      log "os: MowBite OS isn't idle, it stays"
      status switch_os
      outcome os error busy
      return 1
      ;;
    *) log "os: its export failed ($rc), OpenMower keeps its map from before" ;;
    esac
  else
    log "os: MowBite OS doesn't run, OpenMower keeps its map from before"
  fi
  # shellcheck disable=SC2086
  status switch_os openmower stop $how
}
# map: OpenMower's map.json from the OS's export, what it has now kept first. old: as it was before the way there (the
# OS had it read-only)
os_data() {
  local how
  how=$(get switch_os | cut -d' ' -f3-)
  progress os back
  if [ "${how%% *}" = map ]; then
    if keep_data openmower put "$(get os_data)" && data_run "$(mount_at "$OM" /data/ros map.json)" swap 1 "$(os_dir)/export" > /dev/null 2>> "$LOG"; then
      log "os: OpenMower's map.json from MowBite OS's export"
    else
      log "os: OpenMower's map.json can't take MowBite OS's export, it stays as before the switch"
      how=old
    fi
  fi
  # shellcheck disable=SC2086
  status switch_os openmower start $how
}
os_om_back() {
  local how
  how=$(get switch_os | cut -d' ' -f3-)
  if ! os_om_up; then
    outcome os error back
    return 1
  fi
  os_off
  log "os: back on OpenMower"
  # shellcheck disable=SC2086
  outcome os back "$(now)" ${how:-old}
}

# --- a calibration: values measured on the mower written into OpenMower's mower_params.yaml ---

# where the file lies, "<what to mount>|<file>": the mount of OpenMower's container at /data/params (a folder, or a
# volume by its name), else a mower_params.yaml mounted on its own (its folder then). nothing when there's none, or
# it's read-only
calib_where() {
  [ "$(kind openmower)" = openmower ] && exists "$OM" || return 1
  mounts "$OM" |
    awk -F'|' '
      $4 != "true" { next }
      $3 == "/data/params" { print $2 "|mower_params.yaml"; found = 1; exit }
      $1 == "bind" && $3 ~ /\/mower_params\.yaml$/ { d = $2; sub(/\/[^\/]*$/, "", d); f = $2; sub(/.*\//, "", f); one = d "|" f }
      END { if (!found && one != "") print one }
    ' | grep .
}
# calib.sh in a helper of its own image with that folder alone and no network: what it says
calib_run() {
  local w what="$1"
  shift
  w=$(calib_where) || return 1
  docker run --rm --network none --pull never -v "${w%%|*}:/p" --entrypoint sh "$(image_of "$ME")" /calib.sh "$what" "${w#*|}" "$@" 2>&1
}
# for apps: calib_paths "<name>:<path>:<unit>:<min>:<max>:<value>" each, only for the paths the file has, and
# calib_backup <unix> of the newest copy before. neither when the file can't be found or read
calib_look() {
  local out
  # shellcheck disable=SC2046
  if ! out=$(calib_run read $(printf '%s\n' "$CALIB" | cut -d' ' -f2)); then
    status calib_paths
    status calib_backup
    return 0
  fi
  # shellcheck disable=SC2046
  status calib_paths $(printf '%s\n' "$out" | awk -v list="$CALIB" '
    BEGIN { n = split(list, l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, " "); row[f[2]] = f[1] ":" f[2] ":" f[3] ":" f[4] ":" f[5] } }
    NF == 2 && ($1 in row) { print row[$1] ":" $2 }
  ')
  # shellcheck disable=SC2046
  status calib_backup $(printf '%s\n' "$out" | sed -n 's/^backup .*\.mowbite-\([0-9]*\)$/\1/p')
}
# a calibration's pairs "<path> <value>" written (checked against CALIB before), or "back" to the copy before the last
# one: only idle in the dock with MowBite's schedule held, OpenMower started again on it and seen answering, else the
# file as it was and OpenMower started on that. not in the dock it waits for it (calib_pending, the newest request,
# tried each round for CALIB_WAIT)
calib() {
  local out img since
  # (OpenMower stopped isn't started from here, nor next to MowBite OS)
  if ! running "$OM" || os_host; then
    out=os_host
    running "$OM" || out=stopped
    status calib_pending
    status calib refused "$(now)" "$out"
    log "calibration: nothing written, $([ "$out" = stopped ] && echo "OpenMower doesn't run" || echo "MowBite OS runs on the mower")"
    return 1
  fi
  # (still in the dock once the schedule is held: a start sent just before shows by then)
  if docked && img=$(image_of "$OM") && hold openmower; then
    docked || unhold
  elif docked; then
    status calib_pending
    status calib error "$(now)" hold
    return 1
  fi
  if [ -z "$held" ]; then
    # (the same request keeps waiting since it came)
    since=$(get calib_pending)
    [ "${since#* }" = "$1" ] && since=${since%% *} || { since=$(now) && log "calibration: waits for the mower idle in the dock"; }
    status calib_pending "$since" "$1"
    status calib waiting "$(now)"
    return 2
  fi
  status calib_pending
  # shellcheck disable=SC2086
  if [ "$1" = back ]; then out=$(calib_run back); else out=$(calib_run write $1); fi
  case $out in
  ok* | back*) ;;
  *)
    unhold
    out=$(printf '%s\n' "$out" | sed -n 's/^refused //p' | head -n1 | tr ' ' '_')
    status calib refused "$(now)" "${out:-no_params}"
    log "calibration: nothing written (${out:-no mower_params.yaml found that it can write})"
    calib_look
    return 1
    ;;
  esac
  printf '%s\n' "$out" | while read -r w a b c; do
    case $w in
    ok) log "calibration: $a $b -> $c in mower_params.yaml" ;;
    back) log "calibration: mower_params.yaml back to $a" ;;
    esac
  done
  # (what it wrote, old and new, for apps: "<unix> <path> <old> <new> ...")
  # shellcheck disable=SC2046
  [ "$1" = back ] || status calib_last "$(now)" $(printf '%s\n' "$out" | awk '$1 == "ok" { print $2, $3, $4 }')
  progress openmower restart
  # (the list and the copy before as they are now, before apps see what came of it)
  if docker restart "$OM" > /dev/null 2>&1 && rehold && seen openmower "$img"; then
    calib_look
    if [ "$1" = back ]; then status calib back "$(now)"; else status calib written "$(now)"; fi
  else
    log "calibration: OpenMower didn't answer on it, back to the file before"
    [ "$1" = back ] || calib_run back > /dev/null
    docker restart "$OM" > /dev/null 2>&1 && rehold && seen openmower "$img"
    calib_look
    status calib error "$(now)" not_running
  fi
  status progress
  unhold
}

# --- a container built from github ---

# where its branches and releases are read: github, for the planner PLANNER_GITHUB when it's set (a test's)
github_of() { if [ "$1" = planner ]; then echo "${PLANNER_GITHUB:-https://github.com}"; else echo https://github.com; fi; }
# its repository's branches and tags: "<commit> <ref>" a line, an annotated tag's commit under <ref>^{}. git's own
# answer, not github's api (no limit of 60 an hour). 1 without one
refs_of() {
  local src r
  src=$(source_of "$(context_of "$(box "$1")")")
  [ -n "$src" ] || return 1
  r=$(wget -q -T 15 -O - "$(github_of "$1")/${src%% *}.git/info/refs?service=git-upload-pack" 2>/dev/null | tr '\000' ' ' |
    sed -n 's/^[0-9a-f]\{4\}\([0-9a-f]\{40\}\) \(refs\/[^ ]*\).*/\1 \2/p')
  [ -n "$r" ] && echo "$r"
}
# the planner is built from its releases from 0.2.0 on (the ones before were its first tries): on stable the newest
# without a dash, where /releases/latest sends, on beta the highest version in its feed (the newest ten). "-" when
# github answered and there's none in its channel: built from its branch then. 1 without an answer: nothing changes
FIRST_RELEASE=0.2.0
release_of() {
  local f x best=
  [ "$1" = planner ] || { echo -; return 0; }
  [ "$(channel "$1")" = stable ] && { stable_release_of "$1"; return; }
  f=$(wget -q -T 15 -O - "$(releases_url "$1").atom" 2>/dev/null) || return 1
  case $f in *"<feed"*) ;; *) return 1 ;; esac
  for x in $(printf '%s\n' "$f" | sed -n 's|.*/releases/tag/v\([^"/?#]*\)".*|\1|p'); do
    valid "$x" "$VERSION_RE" && ! older "$x" $FIRST_RELEASE || continue
    { [ -z "$best" ] || older "$best" "$x"; } && best=$x
  done
  echo "${best:--}"
}
releases_url() { echo "$(github_of "$1")/$(source_of "$(context_of "$(box "$1")")" | cut -d' ' -f1)/releases"; }
# its newest release without a dash from 0.2.0 on, where /releases/latest sends: "-" when that's the list of releases
# (there's none), 1 without an answer
stable_release_of() {
  local l
  l=$(wget -S --spider -T 15 "$(releases_url "$1")/latest" 2>&1 | sed -n 's/^ *Location: *//p' | tr -d '\r' | head -n1)
  case $l in
  */releases/tag/v*)
    l=${l##*/releases/tag/v}
    l=${l%%[?#]*}
    if valid "$l" "$VERSION_RE" && ! older "$l" $FIRST_RELEASE; then echo "$l"; else echo -; fi
    ;;
  */releases | */releases/) echo - ;;
  *) return 1 ;;
  esac
}
# what to build: "<commit> <name> release|branch", its channel's release (its tag) or else its branch. 1 when github
# didn't answer, then it stays as it is: never its branch for a failed look
want_of() {
  local refs rel src c name how=release
  refs=$(refs_of "$1") || return 1
  rel=$(release_of "$1") || return 1
  if [ "$rel" = - ]; then
    src=$(source_of "$(context_of "$(box "$1")")")
    name=${src#* }
    name=${name:-main}
    how=branch
    c=$(printf '%s\n' "$refs" | awk -v r="refs/heads/$name" '$2 == r {print $1; exit}')
  else
    name=v$rel
    c=$(printf '%s\n' "$refs" | awk -v r="refs/tags/$name" '$2 == r "^{}" {p = $1} $2 == r {t = $1} END {print p ? p : t}')
  fi
  valid "$c" '[0-9a-f]{40}' && echo "$c $name $how"
}
# the release a build runs, also only a new name on the commit it runs
# form: status <part>_release <its tag, v0.2.0>, none for its branch
release_name() {
  status "$1_release"
  [ "$3" != release ] || status "$1_release" "$2"
}
# what a build says it went to: a release's tag, else its commit
said_of() { if [ "$3" = release ]; then echo "$2"; else echo "$1" | cut -c1-7; fi; }
# its build's context at exactly that commit, for compose besides its stack's files (those stay as they are)
context_file() {
  local src f="$STATE/build-$1.yaml"
  src=$(source_of "$(context_of "$(box "$1")")")
  printf 'services:\n  %s:\n    build:\n      context: https://github.com/%s.git#%s\n' \
    "$(service "$(box "$1")")" "${src%% *}" "$2" > "$f" && echo "$f"
}
# the commit it was last built from here, while it still runs that image
built_of() { [ "$(get "$1_image")" = "$(image_of "$(box "$1")")" ] && get "$1_built"; }
# the image it was built on is still the one its base tag ($2) names
base_same() { [ -z "$2" ] || [ "$(get "$1_base_id")" = "$(id_of "$2")" ]; }

# what of a build is left out when it doesn't start: the commit with the id of the image it's built on (that one changed,
# OpenMower's new version, it's another build), as <part>_failed says it
build_key() { echo "$1${2:+ $(id_of "$2")}"; }

# built again from its own context and started, at the commit want_of says ($3, "<commit> <name> release|branch"; on
# OpenMower's new version without it: what it says now, else the commit it runs). never --pull, and only when the image
# it's built on is here (for the planner: OpenMower's, it has to be built on the one that runs, a missing one would come
# down whole). one stopped by hand is made anew on it and stays stopped. one removed with OpenMower's version before
# (gone_<part>) is built anew from what was noted then, nothing to go back to: not started it stays removed
build() {
  local p="$1" c g base commit name how img before ran back rc built fail stopped='' new=''
  c=$(box "$p")
  gone "$c" && new=1
  g=$(gate "$p")
  progress "$p" prepare
  base=$(base_of "$c")
  if [ -n "$base" ] && ! docker image inspect "$base" > /dev/null 2>&1; then
    log "$p: its base $base isn't here, not built (it would download it whole)"
    outcome "$p" error base_missing
    return 1
  fi
  room_for $ROOM_BUILD || { log "$p: less than $ROOM_BUILD MB free, not built"; outcome "$p" nospace $ROOM_BUILD "$(free_mb)"; return 1; }
  [ -n "${3:-}" ] || [ -z "$new" ] || set -- "$1" "$2" "$(gone_of "$c" | cut -d' ' -f6-)"
  # shellcheck disable=SC2046,SC2086
  set -- "$1" "$2" ${3:-$(want_of "$p")}
  commit=$3 name=${4:-} how=${5:-}
  if [ -z "$commit" ] && [ -n "$(built_of "$p")" ]; then
    commit=$(built_of "$p") name=$(get "${p}_release") how=release
    [ -n "$name" ] || { name=$(source_of "$(context_of "$c")" | cut -d' ' -f2); name=${name:-main} how=branch; }
    log "$p: github didn't answer, built again at the commit it runs"
  fi
  # (the planner never from its branch for a failed look, that may be older than its release)
  if [ -z "$commit" ] && [ "$p" = planner ]; then
    log "$p: github didn't answer and the commit it runs isn't known, not built"
    outcome "$p" error github
    return 1
  fi
  fail=
  [ -n "$commit" ] && fail=$(build_key "$commit" "$base")
  # (also the one after OpenMower's update: the same commit on the same base didn't start before)
  if [ -z "$new" ] && [ -n "$fail" ] && [ "$fail" = "$(get "${p}_failed")" ]; then
    log "$p: not again, $(echo "$commit" | cut -c1-7) didn't start before on this base"
    outcome "$p" skipped_failed
    return 0
  fi
  img=$(ref_of "$c")
  if [ -n "$new" ]; then
    [ "$(gone_of "$c" | cut -d' ' -f3)" = stopped ] && stopped=1
    back=
    log "$p: removed with OpenMower's version before, building ($2)"
  else
    case $(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null) in exited | created | dead) stopped=1 ;; esac
    before=$(image_of "$c")
    ran=$before
    # an image that ran and isn't there any more (built again with the same content, its tag went on and docker dropped
    # it while it ran): the one its tag names is the way back, the same a restart would run
    if ! docker image inspect "$before" > /dev/null 2>&1; then
      before=$(id_of "$img")
      [ -n "$before" ] && log "$p: the image it runs isn't there any more, the one its tag names is the way back"
    fi
    back=$(keep_back "$(repo_of "$img")" "$before" "$p")
    [ -n "$back" ] || { log "$p: the version before can't be kept, not built"; outcome "$p" error keep; return 1; }
    log "$p: kept the version before as $back, building ($2)"
  fi
  build_image "$p" "$commit" "$g"
  rc=$?
  [ $rc -eq 0 ] || [ $rc -eq 2 ] || log "$p: the build failed${back:+, the one before keeps running}"
  # (with MowBite's schedule held: the mower relies on it while it mows)
  if [ $rc -eq 0 ] && [ "$g" != none ] && ! hold "$p"; then
    rc=4
  elif [ $rc -eq 0 ] && ! gate_ok "$g"; then
    log "$p: the mower left the dock, the one before keeps running"
    rc=2
  fi
  if [ $rc -ne 0 ]; then
    unhold
    [ -z "$back" ] || undo_back "$back" "$img"
    [ $rc -eq 2 ] && return 2
    if [ -n "$new" ]; then outcome "$p" error gone; elif [ $rc -eq 4 ]; then outcome "$p" error hold; else outcome "$p" error build; fi
    return 1
  fi
  built=$(id_of "$img")
  if [ -z "$new" ] && [ "$before" = "$ran" ] && same "$built" "$before"; then
    # the same image again (built again it only has another record of its build): nothing to restart, compose would
    # leave it anyway. the tag stays on the one that runs, so that one stays there
    log "$p: the same image as before, it keeps running"
    docker tag "$before" "$img"
    docker rmi "$back" > /dev/null 2>&1
  elif [ -n "$stopped" ]; then
    # (nothing to see run, and the one before isn't kept for it)
    if ! compose $T_UP "$c" up --no-start --no-deps --no-build --pull never --force-recreate "$(service "$c")" >> "$LOG" 2>&1; then
      log "$p: compose couldn't make it anew${back:+, the one before stays}"
      [ -z "$back" ] || undo_back "$back" "$img"
      if [ -n "$new" ]; then outcome "$p" error gone; else outcome "$p" error compose; fi
      return 1
    fi
    [ -z "$back" ] || docker rmi "$back" > /dev/null 2>&1
    log "$p: made anew on its new build, stopped as it was"
  elif [ -n "$new" ]; then
    if ! restart "$p" "$built"; then
      box_rm "$c"
      log "$p: didn't run on its new build, removed again"
      outcome "$p" error gone
      return 1
    fi
    log "$p: running again"
  else
    # shellcheck disable=SC2086
    status "pending_$p" "$back" "$img" "$built" $fail
    restart "$p" "$built" || { go_back "$p" "$back" "$img" "$fail"; return 1; }
    status "pending_$p"
    log "$p: running again"
  fi
  build_done "$p" "$commit" "$name" "$how" "$base" "$stopped"
}
# its image built from its own context, at commit $2 (none: as its stack says), while its gate $3 lets it
build_image() {
  local ctx='' rc
  : > "$STATE/layers"
  [ -n "$2" ] && ctx=$(context_file "$1" "$2")
  with_progress "$1" "$3" compose $T_BUILD "$(box "$1")" ${ctx:+-f "$ctx"} --progress json build "$(service "$(box "$1")")"
  rc=$?
  [ -n "$ctx" ] && rm -f "$ctx"
  return $rc
}
# what's noted of a build made on its new image: built from commit $2 ($3 its name, $4 release or branch) on base $5,
# runs, or stopped ($6)
build_done() {
  status "gone_$1"
  status "$1_image" "$(image_of "$(box "$1")")"
  status "$1_built" "$2"
  release_name "$1" "$3" "$4"
  [ -n "$5" ] && status "$1_base_id" "$(id_of "$5")"
  status "$1_rebuild"
  if [ -n "${6:-}" ]; then outcome "$1" stopped; else outcome "$1" updated "$(now)" "$(said_of "$2" "$3" "$4")"; fi
  [ -n "$2" ] && status "$1_available" no "${3:-main}"
  return 0
}

# form: status <part>_available yes|no|failed|unknown <its release's tag or its branch>, of a build
# form: status <part>_stable yes|no, also of the planner's build
# form: status <part> updated <unix s> <a release's tag or the commit>, of a build
check_build() {
  local c built want base st
  c=$(box "$1")
  # (removed with OpenMower's version before: to be built)
  if gone "$c"; then
    status "$1_running" "?"
    status "$1_source" github
    status "$1_available" yes "$(gone_of "$c" | cut -d' ' -f7)"
    return
  fi
  built=$(built_of "$1")
  status "$1_running" "${built:-?}" "$(day_of "$(image_of "$c")")"
  status "$1_source" github
  # (whether there's a stable release to pick, for the planner. without an answer it stays as it was)
  if [ "$1" = planner ] && st=$(stable_release_of "$1"); then
    if [ "$st" = - ]; then status "$1_stable" no; else status "$1_stable" yes; fi
  fi
  # shellcheck disable=SC2046
  set -- "$1" $(want_of "$1")
  base=$(base_of "$c")
  if [ -z "${2:-}" ] || [ -z "$built" ]; then
    want=$(get "$1_release")
    status "$1_available" unknown "${3:-${want:-main}}"
  elif [ "$2" = "$built" ] && base_same "$1" "$base"; then
    # (the same commit, now with a release's name: nothing to build, only the name)
    release_name "$1" "$3" "$4"
    status "$1_available" no "$3"
  elif [ "$(build_key "$2" "$base")" = "$(get "$1_failed")" ]; then
    status "$1_available" failed "$3"
  else
    status "$1_available" yes "$3"
  fi
}

update_build() {
  local want base
  progress "$1" prepare
  # (removed with OpenMower's version before: built again, what github says or else what was noted then)
  if gone "$(box "$1")"; then
    build "$1" again "$(want_of "$1")"
    return
  fi
  running "$(box "$1")" || { log "$1: not running, left as it is"; outcome "$1" stopped; return 0; }
  want=$(want_of "$1") || { outcome "$1" error github; return 1; }
  # shellcheck disable=SC2086
  set -- "$1" $want
  # never back to an older release by picking stable, as with an image
  if [ "$4" = release ] && [ "$(channel "$1")" = stable ] && older "${3#v}" "$(get "$1_release" | sed 's/^v//')"; then
    log "$1: stable $3 is older than $(get "$1_release") that runs, it stays as it is"
    outcome "$1" stable_older "${3#v}"
    return 0
  fi
  base=$(base_of "$(box "$1")")
  if [ "$2" = "$(built_of "$1")" ] && base_same "$1" "$base"; then
    release_name "$1" "$3" "$4"
    outcome "$1" current
    return 0
  fi
  if [ "$(build_key "$2" "$base")" = "$(get "$1_failed")" ]; then
    log "$1: not again, $(said_of "$2" "$3" "$4") didn't start before"
    outcome "$1" skipped_failed
    return 0
  fi
  build "$1" "$(said_of "$2" "$3" "$4")" "$want"
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
  local rc
  case $(kind "$1") in
  openmower) update_openmower ;;
  image) update_image "$1" ;;
  build) update_build "$1" ;;
  local) outcome "$1" local ;;
  os) outcome openmower os ;;
  esac
  rc=$?
  # (whatever came of it: the schedule isn't held any more)
  unhold
  return $rc
}

# --- stopped halfway ---

# a run that didn't end (the power gone, the container stopped): data being put back is put back, a file it changed for
# a part it hadn't restarted yet goes back, if nobody changed it since; a tag moved to an image that never started goes
# back on the one that runs; a part it had restarted is looked at again (settle). nothing starts later on something
# nobody saw come up
recover() {
  local p c ref img tagged
  # (data put back halfway: done again before anything starts on half of it, then the part started again, unless it
  # waits to be seen running)
  # shellcheck disable=SC2046
  set -- $(get data_put)
  if [ -n "$1" ]; then
    log "$1: its data was being put back when it stopped"
    if [ -n "$3" ]; then
      docker stop "$(box "$1")" > /dev/null 2>&1
      data_back "$1" "$2" || outcome "$1" error data_put
    else
      status data_put
    fi
    [ -n "$(get "pending_$1")" ] || running "$(box "$1")" || restart_same "$1"
  fi
  [ "$(get result)" = running ] || return 0
  log "the last run was stopped halfway, putting back what didn't run yet"
  for p in $(part_ids); do
    [ -n "$(get "changed_$p")" ] && [ -z "$(get "pending_$p")" ] && undo_change "$p"
  done
  if [ -z "$(get pending_openmower)" ]; then om_saved_back; else status openmower_saved; fi
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
# with its tag or builds on, with the room each frees for real (its own layers), and the build cache. listed here,
# deleted when asked (room_free). after a run tidy clears images without a name, the build cache nothing points to and
# rollback tags beyond the ones kept by itself
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
# bytes from docker's sizes: 512B, 4.1kB, 12.3MB, 1.2GB, and a field of one of its json records
bytes_awk='function bytes(s, n, u) { n = s + 0; u = s; sub(/^[0-9.]+/, "", u); if (u == "kB") n *= 1e3; else if (u == "MB") n *= 1e6; else if (u == "GB") n *= 1e9; else if (u == "TB") n *= 1e12; return int(n) }
function field(k,    v) {
  if (!match($0, "\"" k "\":\"[^\"]*\"")) return ""
  v = substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5); gsub(/\\u003c/, "<", v); gsub(/\\u003e/, ">", v)
  return v
}'
# the images the containers run on, there and stopped
images_used() { docker ps -aq | xargs -r docker inspect -f '{{.Image}}' 2>/dev/null | tr '\n' ' '; }
# one line per image: img <id> <bytes> <its tags, comma separated, or -> <kind>, then: cache <bytes> (what clearing it
# frees: the entries no image shares). the way back of a part not seen running yet isn't listed
check_room() {
  local df out p only=
  used=" $(images_used) "
  named=" $(compose_refs | tr '\n' ' ') $(for p in $(part_ids); do get "pending_$p" | cut -d' ' -f1; done | tr '\n' ' ') "
  # (a test on a pc with images and containers of its own: only the ones with this label, TEST_LABEL=<key>=<value>)
  [ -n "${TEST_LABEL:-}" ] && only=" $(docker images -q --no-trunc --filter "label=$TEST_LABEL" | sort -u | tr '\n' ' ') "
  # (one look at docker's disk: the images, then the build cache)
  df=$(mktemp)
  timeout $T_UP docker system df -v --format '{{json .Images}}\n{{json .BuildCache}}' > "$df" 2>/dev/null
  # (next to the list it replaces: moved in place whole, its page never reads half of it)
  out=$(mktemp "$STATE/room.XXXXXX") || { rm -f "$df"; return; }
  sed -n 1p "$df" | sed 's/^\[//; s/\]$//; s/},{/}\n{/g' | awk -v used="$used" -v named="$named" -v only="$only" "$bytes_awk"'
    {
      id = field("ID"); repo = field("Repository"); tag = field("Tag"); ref = repo ":" tag
      if (id == "" || (only != "" && !index(only, " " id " "))) next
      if (field("Containers") != "0" || index(used, " " id " ") || (repo != "<none>" && index(named, " " ref " "))) { keep[id] = 1; next }
      size[id] = bytes(field("UniqueSize"))
      if (repo != "<none>") refs[id] = refs[id] (refs[id] == "" ? "" : ",") ref
      k = repo == "<none>" ? "dangling" : tag ~ /^rb-|^previous$|^keep-/ ? "rollback" : tag ~ /^before-/ ? "planner" : tag ~ /^prev-/ ? "old" : "unused"
      if (kind[id] == "" || kind[id] == "unused") kind[id] = k
    }
    END { for (id in size) if (!keep[id]) print "img", substr(id, 8, 12), size[id], (refs[id] == "" ? "-" : refs[id]), kind[id] }' > "$out"
  echo "cache $(sed -n 2p "$df" | sed 's/^\[//; s/\]$//; s/},{/}\n{/g' | awk "$bytes_awk"'field("Shared") == "false" { s += bytes(field("Size")) } END { print s + 0 }')" >> "$out"
  rm -f "$df"
  mv "$out" "$STATE/room"
}

# what was asked to delete: one image from the list (all its tags, never forced), all of them but the ways back (rb-,
# previous, before-, keep-: those one at a time), or the build cache. the list is made again first: only what still
# nothing needs goes
room_free() {
  alive
  before=$(free_mb)
  check_room
  alive
  case $1 in
  cache)
    timeout $T_UP docker builder prune -af > /dev/null 2>&1
    log "room: build cache cleared"
    ;;
  img | all)
    grep '^img ' "$STATE/room" 2>/dev/null | while read -r _ id _ refs kind; do
      if [ "$1" = all ]; then
        case $kind in rollback | planner) continue ;; esac
      elif [ "$id" != "$2" ]; then
        continue
      fi
      alive
      if [ "$refs" = - ]; then
        docker rmi "$id" > /dev/null 2>&1 && log "room: removed image $id"
      else
        for r in $(echo "$refs" | tr ',' ' '); do docker rmi "$r" > /dev/null 2>&1 && log "room: removed $r"; done
      fi
    done
    ;;
  esac
  alive
  check_room
  status disk_free "$(free_mb)"
  log "room: $(($(free_mb) - before)) MB more free, $(free_mb) MB free"
}

# --- the stacks' containers, like a small dockge: their list, a log, a restart ---

# the containers of the stacks (the compose projects in the folder its own stack is in), for its page: "<name> <stack>
# <state> <started> <restarts> <image>" a line (started as docker says it, - when it never ran)
look_boxes() {
  local root out
  root=$(stacks_root)
  out=$(mktemp "$STATE/containers.XXXXXX") || return 0
  # shellcheck disable=SC2046
  docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project"}}|{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}|{{.Config.Image}}' $(docker ps -aq) 2> /dev/null |
    awk -F'|' -v root="$root/" '
      index($2, root) == 1 && $3 != "" {
        n = $1; sub(/^\//, "", n)
        started = $5 ~ /^0001-/ ? "-" : $5
        print n, $3, $4, started, $6 + 0, ($7 == "" ? "-" : $7)
      }' | sort > "$out"
  mv "$out" "$STATE/containers"
}
# a container its page may ask about: one of the list, not itself or its helper
is_box() { [ "$1" != "$ME" ] && [ "$1" != "$SELF" ] && cut -d' ' -f1 "$STATE/containers" 2> /dev/null | grep -qxF -- "$1"; }
# what a log mustn't show of a container: the values of its settings that look like access (passwords, tokens, keys,
# users), its own mqtt password, and OpenMower's ntrip access from mower_params.yaml. a value a line, only kept in memory
secrets() {
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2> /dev/null |
    awk -F= 'toupper($1) ~ /PASS|SECRET|TOKEN|KEY|AUTH|USER|NTRIP|CRED/ { sub(/^[^=]*=/, ""); if (length($0) >= 3) print }'
  [ -n "${MQTT_PASSWORD:-}" ] && printf '%s\n' "$MQTT_PASSWORD"
  [ "$1" = "$OM" ] && calib_run read ntrip_client/username ntrip_client/password ntrip_client/user 2> /dev/null |
    awk '$1 ~ /^ntrip_client\// { sub(/^[^ ]* /, ""); gsub(/^["\047]|["\047]$/, ""); if (length($0) >= 3) print }'
}
# a log as it may be shown: the given values out, the access in a url (user:password@) and what follows password,
# token, secret or an api key with : or =, each as ***
redact() {
  # (through the environment: awk -v would read a backslash in one as an escape)
  SECRETS="$1" awk '
    function ci(w,   r, i, c, u, l) { r = ""; for (i = 1; i <= length(w); i++) { c = substr(w, i, 1); u = toupper(c); l = tolower(c); r = r (u != l ? "[" u l "]" : c) } return r }
    function lit(line, x,   out, p) { out = ""; while ((p = index(line, x)) > 0) { out = out substr(line, 1, p - 1) "***"; line = substr(line, p + length(x)) } return out line }
    BEGIN {
      n = split(ENVIRON["SECRETS"], s, "\n")
      # (up to the last @ before the host: a password can hold one)
      url = "://[^/@ :\"\047]+:[^ /\"\047]*@"
      kv = "(" ci("password") "|" ci("passwd") "|" ci("pwd") "|" ci("secret") "|" ci("token") "|" ci("api_key") "|" ci("apikey") ")[\"\047]?[ \t]*[:=][ \t]*[\"\047]?"
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
# a container's last log lines for its page, with the secrets out: "#<name> <unix>" and then the lines, oldest first
box_logs() {
  local out
  is_box "$1" || return 0
  out=$(mktemp "$STATE/logs.XXXXXX") || return 0
  { echo "#$1 $(now)"; docker logs --tail 300 --timestamps "$1" 2>&1 | redact "$(secrets "$1")"; } > "$out"
  mv "$out" "$STATE/logs"
}
# a MowBite OS host running on the mower: a container labelled mowbite.os or of an image named mowbite-os. OpenMower is
# never started next to one (two hosts at the board)
os_host() {
  docker ps ${TEST_LABEL:+--filter "label=$TEST_LABEL"} --format '{{.Names}}|{{.Image}}|{{.Label "mowbite.os"}}' 2> /dev/null |
    awk -F'|' '$3 != "" || $2 ~ /(^|\/)mowbite[-_]os([-_:@]|$)/ { found = 1 } END { exit !found }'
}
# a running container of the stacks started again, asked for on its page: only while OpenMower doesn't drive the mower,
# OpenMower itself only idle in the dock with MowBite's schedule held and seen answering after, never next to a MowBite
# OS host. a stopped one isn't started from here. status restarted "<name> <done|refused|error> <unix> [why]"
restart_box() {
  local img
  is_box "$1" || return 0
  if ! running "$1"; then
    status restarted "$1" refused "$(now)" stopped
    log "$1: not started, it was stopped"
  elif [ "$1" = "$OM" ] && os_host; then
    status restarted "$1" refused "$(now)" os_host
    log "$1: not started again, MowBite OS runs on the mower"
  elif [ "$1" = "$OM" ]; then
    if ! docked; then
      status restarted "$1" refused "$(now)" not_docked
      log "$1: not started again, the mower isn't idle in the dock"
      return 0
    fi
    img=$(image_of "$OM")
    hold openmower || { status restarted "$1" error "$(now)" hold; return 0; }
    if ! docked; then
      unhold
      status restarted "$1" refused "$(now)" not_docked
      log "$1: not started again, the mower left the dock"
      return 0
    fi
    progress openmower restart
    if docker restart "$OM" > /dev/null 2>&1 && rehold && seen openmower "$img"; then
      status restarted "$1" "done" "$(now)"
      log "$1: started again, asked for on its page"
    else
      status restarted "$1" error "$(now)" not_running
      log "$1: started again, but it didn't answer"
    fi
    status progress
    unhold
  elif ! quiet; then
    status restarted "$1" refused "$(now)" busy
    log "$1: not started again, OpenMower drives the mower"
  elif [ "$1" = "$PLANNER" ] && ! { hold planner && quiet; }; then
    # (the planner with the schedule held: a run starting meanwhile would get no plan)
    unhold
    status restarted "$1" refused "$(now)" busy
    log "$1: not started again, the schedule couldn't be held or the mower drives"
  elif docker restart "$1" > /dev/null 2>&1; then
    unhold
    status restarted "$1" "done" "$(now)"
    log "$1: started again, asked for on its page"
  else
    unhold
    status restarted "$1" error "$(now)" failed
    log "$1: couldn't be started again"
  fi
  look_boxes
}

# --- leftovers ---

# its own older rollback tags: of each part the newest few on other images than the one that runs (an app's: two, the
# big ones: none), newest first by the time in the tag. not while a part waits to be seen running, and never one on an
# image built here that can't be had again (a build's can: it's built from its source), or while its registry doesn't
# answer. tags it didn't make stay.
# then what a pull by its digest left of a part's repository (OpenMower back to the version before): no tag any more,
# only that digest, and no container on it. prune leaves it with docker's containerd store, it would stay for good.
# then what nothing uses and the build cache nothing points to
tidy() {
  local p keep name repo run kept n seen_before used t dg id
  used=" $(images_used) "
  for p in $(part_ids); do
    alive
    name=$(box "$p")
    exists "$name" || continue
    case $(kind "$p") in
    # (a big app, like xtech's with its 300 MB, keeps none: the mower's disk is small)
    image) if [ "$(image_bytes "$(image_of "$name")")" -lt 104857600 ]; then keep=$KEEP; else keep=$KEEP_BIG; fi ;;
    openmower | build) keep=$KEEP_BIG ;;
    *) continue ;;
    esac
    [ -n "$(get "pending_$p")" ] && continue
    repo=$(repo_of "$(ref_of "$name")")
    run=$(image_of "$name")
    backs "$p" "$repo" | {
      kept=" "
      n=0
      while read -r t id; do
        case $kept in *" $id "*) seen_before=1 ;; *) seen_before= ;; esac
        if [ "$id" != "$run" ] && [ -z "$seen_before" ] && [ $n -lt "$keep" ]; then
          kept="$kept$id "
          n=$((n + 1))
        elif [ "$(kind "$p")" != build ] && [ "$id" != "$run" ] && [ -z "$seen_before" ] && { built_here "$id"; [ $? -ne 1 ]; }; then
          kept="$kept$id "
        else
          docker rmi "$repo:$t" > /dev/null 2>&1 && log "removed $repo:$t"
        fi
      done
    }
    # (-a: docker 29's cli leaves untagged ones out of the list with the classic store)
    docker images -a --digests --no-trunc --format '{{.Tag}} {{.Digest}} {{.ID}}' "$repo" 2>/dev/null | while read -r t dg id; do
      [ "$t" = "<none>" ] && [ "$dg" != "<none>" ] || continue
      case $used in *" $id "*) continue ;; esac
      docker rmi "$repo@$dg" > /dev/null 2>&1 && log "removed $repo@$dg, nothing uses it any more"
    done
  done
  # (a test on a pc with images and builds of its own: PRUNE=0)
  if [ "${PRUNE:-1}" != 0 ]; then
    alive
    freed=$(timeout $T_UP docker image prune -f 2>/dev/null | sed -n 's/^Total reclaimed space: //p')
    alive
    cache=$(timeout $T_UP docker builder prune -f 2>/dev/null | sed -n 's/^Total: *//p')
  fi
  log "tidied up: images ${freed:-0B}, build cache ${cache:-0B}, $(free_mb) MB free"
}

# itself, for its card: the commit it runs and from when, its release (v and the version in its image's label: none for
# a build of main), whether its registry has a newer one
check_self() {
  local img rev v
  img=$(image_of "$ME")
  rev=$(rev_of "$img")
  status updater_running "${rev:-?}" "$(day_of "$img")"
  v=$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$img" 2>/dev/null)
  # form: status updater_release <its tag, v1.2.0>, none for a build of main
  status updater_release
  valid "$v" "$VERSION_RE" && status updater_release "v$v"
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
  local me prev new root need rc was remote n
  if ! in_compose "$ME"; then
    [ -n "$1" ] && log "the updater doesn't run from a compose file, it can't update itself" && outcome updater error compose
    return
  fi
  me=$(ref_of "$ME")
  if [ -z "$1" ]; then
    built_here "$(image_of "$ME")"
    [ $? -eq 1 ] || return
  fi
  # (asked for: its card shows it's on it)
  [ -n "$1" ] && [ -z "$(get taken)" ] && status taken "$(now)" self
  # nothing downloaded for the version that runs, or one that didn't start before
  remote=$(remote_digest "$me")
  if [ -n "$remote" ] && known_as "$(image_of "$ME")" | grep -q "@$remote"; then
    [ -n "$1" ] && log "the updater is up to date" && outcome updater current
    check_self
    return
  fi
  if failed_has updater "$remote"; then
    [ -n "$1" ] && log "the updater: not again, this version didn't start before" && outcome updater skipped_failed
    return
  fi
  # the helper of its update a moment ago may still see it come up, with :previous as its way back: that one first.
  # (one that ended and stayed is cleared away, a running one can't be)
  if docker container inspect "$SELF" > /dev/null 2>&1; then
    n=0
    while [ $n -lt 30 ] && running "$SELF"; do
      alive
      sleep 10
      n=$((n + 1))
    done
    docker rm "$SELF" > /dev/null 2>&1
  fi
  # (the layers looked up once: for the room and the bar)
  layers "$me" > "$STATE/layers"
  need=$(need_mb "$me" "$(image_of "$ME")" "$STATE/layers")
  [ -n "$need" ] || need=$(($(image_bytes "$(image_of "$ME")") / 1048576))
  if ! room_for $((need + ROOM_APP)); then
    log "the updater: not enough room (needs $need MB and $ROOM_APP to spare, $(free_mb) MB free), it stays as it is"
    outcome updater nospace "$need" "$(free_mb)"
    return
  fi
  # the image it runs now, kept first under a tag of its own: the helper runs on it, and it's the way back
  prev=$(repo_of "$me"):previous
  docker tag "$(image_of "$ME")" "$prev" 2>/dev/null || { log "the updater's own image can't be kept, it doesn't update itself"; outcome updater error keep; return; }
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
    # (quiet, a word now and then that it's there)
    timeout $T_PULL docker pull -q "$me" > /dev/null 2>&1 &
    n=$!
    while kill -0 "$n" 2> /dev/null; do
      alive
      sleep 10
    done
    wait "$n"
    rc=$?
  fi
  if [ $rc -ne 0 ]; then
    [ -n "$1" ] && log "the updater: its new version can't be downloaded, it stays as it is" && outcome updater error pull
    return
  fi
  new=$(id_of "$me")
  if [ "$new" = "$(id_of "$prev")" ]; then
    [ -n "$1" ] && log "the updater is up to date" && outcome updater current
    check_self
    return
  fi
  if failed_has updater "$new"; then
    docker tag "$prev" "$me"
    [ -n "$1" ] && log "the updater: not again, this version didn't start before" && outcome updater skipped_failed
    return
  fi
  # (all stacks: dockge may give each one a global.env next to them)
  root=$(dirname "$(label "$ME" project.working_dir)")
  log "updating the updater"
  # (what came of it, the next start says: a new version, or this one back)
  outcome updater restarting "$(now)"
  if ! docker run -d --rm --name "$SELF" -v /var/run/docker.sock:/var/run/docker.sock -v "$root:$root" -v /etc/localtime:/etc/localtime:ro \
    -e "STATE_DIR=$STATE" -e "UPDATER_CONTAINER=$ME" --entrypoint sh "$prev" /self.sh "$me" "$prev" > /dev/null 2>&1; then
    log "the updater's helper didn't start, it stays as it is"
    docker tag "$prev" "$me"
    outcome updater error helper
    return
  fi
  # (the helper replaces this container within a few minutes: nothing more is taken on here, a request waits for the new
  # one. a helper that ends without replacing it leaves it running on)
  n=0
  while [ $n -lt 60 ] && docker container inspect "$SELF" > /dev/null 2>&1; do
    alive
    sleep 5
    n=$((n + 1))
  done
}

# (a request from its page or MowBite is waiting)
asked() { [ -s "$REQ" ]; }
# the rest of a request that waited for its own update, asked for again at its start: each part on its own (all of
# them: itself is done), before its first look (that one stops for it)
rest_after_self() {
  local a
  [ -n "$(get after_self)" ] || return 0
  for a in $(get after_self); do if [ "$a" = all ]; then part_ids; else echo "$a"; fi; done | sed 's/^/now /' >> "$REQ"
  status after_self
}
# the look whether there's something new, for its page while it lasts (looking). a request that comes in meanwhile
# goes first: the look stops before its next step and is done again after it (half)
check_all() {
  local p
  half=1
  asked && return 0
  status looking "$(now)"
  # (the mower's time zone: the night's time is the mower's)
  status clock "$(date +%z)"
  alive
  find_parts
  for p in $(part_ids); do
    asked && break
    # (each step may wait a minute for its registry: MowBite takes it for gone after 5 minutes without a word)
    alive
    check_part "$p"
  done
  alive
  asked || check_self
  if ! asked; then
    alive
    check_room
    status disk_free "$(free_mb)"
    # (what a calibration may write there, for apps)
    calib_look
    os_look
    status checked "$(now)"
    looked=$(now)
    half=
  fi
  status looking
}

# the parts asked for (all: every one), OpenMower first (builds start from it), the rest in their order. the ones that
# wait for the dock only with the mower idle there, asked before each again. 2 when one had to wait for that. why:
# request, night, nokeep (OpenMower without a copy, asked for), again and start (its download tried again)
run() {
  local why="$1" parts="" p waited was did=
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
  rebuilt=
  # (one restarted before and not seen running yet comes first)
  if docked; then
    [ -n "$(for p in $(part_ids); do get "pending_$p"; done)" ] && did=1
    settle
  fi
  WHY=$why
  MANUAL=
  NOKEEP=
  case $why in request) MANUAL=1 ;; nokeep) MANUAL=1 NOKEEP=1 ;; esac
  waited=
  for p in $parts; do
    # (built on OpenMower's new version in this run already)
    case " $rebuilt " in *" $p "*) continue ;; esac
    # (OpenMower and what stopped with it are left alone next to MowBite OS)
    if os_parked "$p"; then
      outcome "$p" error os
      continue
    fi
    # (asked for: a part left as it was says why on its card. OpenMower's update without a copy looks for itself)
    if ! nokeep_open "$p" && ! gate_ok "$(gate "$p")"; then
      waited=1
      [ -n "$MANUAL" ] && outcome "$p" error not_docked
      continue
    fi
    # (nothing said on its card meanwhile: its time as before)
    was=$(get "${p}_at")
    did=1
    update_part "$p"
    if [ $? -eq 2 ]; then
      waited=1
      [ -n "$MANUAL" ] && [ "$(get "${p}_at")" = "$was" ] && outcome "$p" error not_docked
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
  # (nothing done, all of it waited for the dock: nothing to clear away, and the look of every 6 hours does)
  if [ -n "$did" ]; then
    tidy
    check_all
  fi
  [ -z "$waited" ] || return 2
}

# one thing asked for a part on its own ($1), on its page like a run of that part: what $2... does
alone() {
  rebuilt=
  status run_parts "$1"
  status result running
  status taken
  shift
  "$@"
  status progress
  status run_parts
  status result "done"
}
# a part back to the version before, by hand
back_part() {
  if [ "$1" = openmower ]; then back_openmower; else back_image "$1"; fi
  unhold
}

# OpenMower's update without a copy not done: on once at the updater's start, then when its next look is due
nokeep_due() {
  local next
  nokeep_busy || return 1
  [ -z "$nk_start" ] || return 0
  if exists "$OM"; then next=${nk_next:-0}; else next=$(get openmower_missing | cut -d' ' -f2); fi
  case $next in "" | *[!0-9]*) return 1 ;; esac
  [ "$(now)" -ge "$next" ]
}

# the builds removed with OpenMower's version before and not built since: built when the mower is still, looked at
# every NOKEEP_EVERY. one that failed only while OpenMower doesn't answer, without it nothing runs
gone_due() {
  local p
  ! nokeep_busy && ! os_busy && [ "$(now)" -ge "${gone_next:-0}" ] || return 0
  for p in $(gone_builds); do
    [ "$(get "$p")" != "error gone" ] || [ "$(mower)" = "0 unknown" ] && printf '%s ' "$p"
  done
}

# the parts set to update by themselves
auto_parts() {
  local p
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
# what a stop halfway left of files being written (status, log, settings, the list of what can go): nothing may grow.
# (a minute old: the helper of its own update may write right now)
find "$STATE" -maxdepth 1 \( -name 'status.??????' -o -name 'log.??????' -o -name 'conf.??????' -o -name 'room.??????' -o -name 'containers.??????' -o -name 'logs.??????' \) -mmin +1 -exec rm -f {} + 2> /dev/null
# (for its interface, so it needs no docker to find its folder)
printf '%s\n' "$STATE" > /tmp/updater-state
# the broker's user and password for mosquitto_sub and mosquitto_pub, see mqtt. (it takes the rest of the line, spaces too. an empty
# password: on its command line)
rm -f "$MQTT_OPTS" "$MQTT_PUB_OPTS"
[ -n "$MQTT_USER" ] && [ -n "$MQTT_PASSWORD" ] && mkdir -p "${MQTT_OPTS%/*}" &&
  (umask 077 && printf -- '-u %s\n-P %s\n' "$MQTT_USER" "$MQTT_PASSWORD" > "$MQTT_OPTS" && cp "$MQTT_OPTS" "$MQTT_PUB_OPTS")
serve
log "started"
# (its own prefix is gone: OpenMower's broker on the mower has none, an external one's comes from OpenMower)
[ -z "${MQTT_PREFIX:-}" ] || log "MQTT_PREFIX is left out: OpenMower's broker on the mower has no prefix, an external one's comes from OpenMower"
# a new version of itself since it last started (its own update, or one by hand in dockge), or the one before back
# when the new one didn't come up: said on its card
# shellcheck disable=SC2046
set -- $(get started)
case $(get updater) in restarting*) asked_self=1 ;; *) asked_self= ;; esac
if [ -n "$2" ] && [ "$2" != "$(image_of "$ME")" ] && ! failed_has updater "$2"; then
  log "the updater runs its new version"
  outcome updater updated "$(now)" "$(rev_of "$(image_of "$ME")")"
  # (its card right away, not only after its first look)
  status updater_available no "$(ref_of "$ME")"
elif [ -n "$asked_self" ] || { [ -n "$2" ] && [ "$2" != "$(image_of "$ME")" ]; }; then
  outcome updater rolled_back "$(now)"
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
# (on the way to MowBite OS or back when it stopped: on from there)
[ -z "$(get switch_os)" ] || alone os os_resume
rest_after_self
check_all
# (the night it ran last, also through a restart in its window: its own update came before it)
done_day=$(get night_done)
next=0
# (OpenMower's update without a copy stopped halfway: on once at the start)
nk_start=1
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
    calib_req=""
    nokeep=""
    switch=""
    while read -r w a b; do
      case $w in
      check) check=1 ;;
      # (the newest one: pairs "<path> <value>" checked by the interface, or back)
      calib) calib_req="$a${b:+ $b}" ;;
      # (all: itself too, first)
      now)
        parts="$parts $a"
        [ "$a" = all ] && self=1
        ;;
      self) self=1 ;;
      # (OpenMower without a copy of the version that runs, checked by the interface: only one that's offered)
      nokeep) [ "$(kind "$a")" = openmower ] && ! os_busy && nokeep=1 ;;
      # (to MowBite OS or back, checked by the interface: only what its status offers)
      switch) case $a in os | openmower) switch=$a ;; esac ;;
      back)
        if os_parked "$a"; then
          outcome "$a" error os
          continue
        fi
        case $(kind "$a") in
        image | openmower)
          if [ "$(gate "$a")" = none ] || nokeep_open "$a" || docked; then
            alone "$a" back_part "$a"
            # (the leftovers as after a run: a build made anew on it keeps the one before until then)
            tidy
            check_all
          else
            log "$a: not back to the version before, the mower isn't idle in the dock"
            outcome "$a" error not_docked
          fi
          ;;
        esac
        ;;
      # (a part's data kept at $b back, idle in the dock like an update)
      data)
        if os_parked "$a"; then
          outcome "$a" error os
        elif docked; then
          alone "$a" put_by_hand "$a" "$b"
        else
          log "$a: its data isn't put back, the mower isn't idle in the dock"
          outcome "$a" error not_docked
        fi
        ;;
      room) check_room ;;
      containers) look_boxes ;;
      logs) box_logs "$a" ;;
      restart) restart_box "$a" ;;
      free) room_free "$a" "$b" ;;
      esac
    done < "$REQ.$$"
    rm -f "$REQ.$$"
    [ -z "$calib_req" ] || calib "$calib_req"
    if [ -n "$switch" ]; then
      alone os os_switch "$switch"
      tidy
      check_all
    fi
    # itself first, its newest version updates the rest: that waits meanwhile (after_self) for the version that runs
    # next, the new one or this one put back. still here: nothing new of itself, the rest right away
    if [ -n "$self" ]; then
      # shellcheck disable=SC2086
      [ -z "$parts" ] || status after_self $parts
      update_self manual
      status after_self
    fi
    [ -z "$nokeep" ] || run nokeep openmower
    if [ -n "$parts" ]; then
      # shellcheck disable=SC2086
      run request $parts
    elif [ -n "$check" ] && [ -z "$nokeep" ]; then
      check_all
    fi
    status taken
  fi
  # a calibration that waits for the dock: tried each round, given up once CALIB_WAIT is over without the dock
  pending=$(get calib_pending)
  if [ -n "$pending" ]; then
    if docked; then
      calib "${pending#* }"
    elif [ $(($(now) - ${pending%% *})) -gt "$CALIB_WAIT" ]; then
      status calib_pending
      status calib error "$(now)" not_docked
      log "calibration: nothing written, the mower wasn't idle in the dock in time"
    fi
  fi
  # a request that came in while it was busy: at once, before the night's run or a look, its wake-up came while
  # nothing slept (one it can't take: next round, as before)
  [ -z "$stuck" ] && asked && continue
  if nokeep_due; then
    if [ -n "$nk_start" ]; then run start openmower; else run again openmower; fi
    nk_start=
    [ -z "$stuck" ] && asked && continue
  fi
  nk_start=
  parts=$(gone_due)
  if [ -n "$parts" ] && still; then
    gone_next=$(($(now) + NOKEEP_EVERY))
    # shellcheck disable=SC2086
    run again $parts
    [ -z "$stuck" ] && asked && continue
  fi
  # the night's run: once in its window (also past midnight, it counts as the night it started), again every 10 minutes
  # while the mower isn't in the dock
  parts=$(auto_parts)
  since=$((($(minute) - $(at_minute) + 1440) % 1440))
  start=$(($(now) - since * 60))
  # (the last look as its status says, or as it knows itself when the status can't be written: a full disk)
  last=$(get checked | grep -x '[0-9]*')
  [ "${looked:-0}" -gt "${last:-0}" ] && last=$looked
  if [ -n "$parts" ] && [ $since -lt $WINDOW ] && [ "$done_day" != "$(date -d "@$start" +%F)" ] && day_ok "$start" && [ "$(now)" -ge "$next" ]; then
    # itself first, once a night, also with the mower out of the dock (its own update doesn't touch the mower): its
    # newest version runs the night, a new one at its start, the window still open
    if [ "$(get self_night)" != "$(date -d "@$start" +%F)" ]; then
      status self_night "$(date -d "@$start" +%F)"
      update_self
    fi
    # shellcheck disable=SC2086
    run night $parts
    if [ $? -eq 2 ]; then
      next=$(($(now) + 600))
    else
      done_day=$(date -d "@$start" +%F)
      status night_done "$done_day"
    fi
  elif [ -n "$half" ] || [ $(($(now) - ${last:-0})) -ge $CHECK_EVERY ]; then
    check_all
  fi
  # (and one that came in during those)
  [ -z "$stuck" ] && asked && continue
  sleep 60 &
  nap=$!
  wait $nap
  kill $nap 2> /dev/null
done
