#!/bin/sh
# the updater's own steps around data and its own update, without docker, within a minute: docker is a script on files
# (fake/), the mower, the schedule's hold and a restart are functions that say what they were asked. the data kept
# (pieces, rights, the newest two and the one put back, a piece that isn't there, a full disk, a helper that fails),
# put back (checked first, kept first, nothing when it can't), what the format of the data says, going back with it,
# by hand from its page, a stop halfway, what a pull by its digest leaves, the rest of a request after its own update,
# its own update seen running and answering for 45 s or put back, and OpenMower updated without a copy (offered or not,
# done, a download that fails and its tries, a version that doesn't run, a stop halfway, a build that fails, all of it
# with OpenMower and the planner waiting for each other as with OM_PLANNER=external), and MowBite OS in OpenMower's place
# (offered or not, there and back, kept or deleted first, given up at each step, on after a stop halfway). in the
# image it's built on, nothing written here. what failed a line, 1 then. test/logic.sh data (or self, nokeep, os): only those
# (cases change the updater's functions in subshells of their own)
# shellcheck disable=SC2031,SC2329
set -u
cd "$(dirname "$0")/.." || exit 1
if [ "${1:-}" != in ]; then
  img=$(sed -n 's/^FROM \([^ ]*\)$/\1/p' Dockerfile | tail -n1)
  docker image inspect "$img" > /dev/null 2>&1 || docker pull -q "$img" > /dev/null || { echo "no $img"; exit 1; }
  # (a run that hangs ends by itself)
  exec docker run --rm --network none -v "$PWD:/r:ro" --entrypoint timeout "$img" 300 sh /r/test/logic.sh in "${1:-all}"
fi
only=${2:-all}

# (the updater isn't written for set -u)
set +u
for f in lib.sh updater.sh data.sh self.sh; do ln -sf "/r/$f" "/$f"; done
mkdir -p /fake/bin /fake/c /fake/rows /st /vol
: > /fake/refs
# docker as the updater asks it, on the files in /fake: containers (c/<name>/: image, ref, status, started, mounts as
# "type|source|destination|rw"), images by ref (refs: "<ref> <id> <digest>"), their layers (layers: "<id> <layer>..."),
# a repository's rows for docker images (rows/<repo>), what it was asked (calls). its helpers with data.sh run here,
# their mounts as links
cat > /fake/bin/docker << 'EOF'
#!/bin/sh
F=/fake
echo "$*" >> $F/calls
# (one that isn't there: an empty line and 1, as docker says it)
c() { [ -d "$F/c/$1" ] || { echo; exit 1; }; cat "$F/c/$1/$2" 2> /dev/null; }
# (a new start each time it's asked)
start() { n=$(($(cat $F/n 2> /dev/null || echo 0) + 1)) && echo $n > $F/n && echo "s$n" > "$F/c/$1/started"; }
id_of() { awk -v r="$1" '$1 == r || $2 == r {print $2; exit}' $F/refs; }
img() { id_of "$1" | grep . || awk -v i="$1" '$1 == i {print i; exit}' $F/layers 2> /dev/null; }
case $1 in
inspect)
  shift
  [ "$1" = -f ] || { [ -d "$F/c/$1" ]; exit; }
  fmt=$2
  shift 2
  for n in "$@"; do
    [ -d "$F/c/$n" ] || { echo; exit 1; }
    case $fmt in
    '{{.Image}} {{.Name}}') echo "$(c "$n" image) /$n" ;;
    *Mounts*) c "$n" mounts ;;
    *project.config_files*'|'*) echo "proj|/stk|/stk/compose.yaml|" ;;
    *compose.service*) echo svc ;;
    *working_dir*) echo /stk ;;
    *config_files*) echo /stk/compose.yaml ;;
    *compose.project*) echo proj ;;
    '{{.Image}}') c "$n" image ;;
    '{{.Config.Image}}') c "$n" ref ;;
    '{{.State.Status}}') c "$n" status ;;
    *Running*StartedAt*)
      [ -e $F/crashloop ] && start "$n"
      [ "$(c "$n" status)" = running ] && r=true || r=false
      echo "$r $(c "$n" started)"
      ;;
    *StartedAt*) c "$n" started ;;
    esac
  done
  ;;
image)
  shift 2
  case $1 in
  -f)
    case $2 in
    *.Id*RootFS*)
      shift 2
      for i; do grep "^$(img "$i") " $F/layers; done
      ;;
    *)
      i=$(img "$3")
      [ -n "$i" ] || { echo; exit 1; }
      case $2 in
      *RootFS*) grep "^$i " $F/layers | cut -d' ' -f2- ;;
      *RepoTags*) awk -v i="$i" '$2 == i && $1 !~ /@/ {printf "%s ", $1}' $F/refs ;;
      *.Id*) echo "$i" ;;
      *RepoDigests*) awk -v r="$3" '$1 == r || $2 == r {print $3; exit}' $F/refs ;;
      *.Size*) echo 1000 ;;
      esac
      ;;
    esac
    ;;
  # (ls: their sizes as docker lists them, from sizes "<id> <size>", else 1kB)
  --no-trunc) for i in $(cut -d' ' -f1 $F/layers); do echo "$i $(awk -v i="$i" '$1 == i {print $2}' $F/sizes 2> /dev/null | grep . || echo 1kB)"; done ;;
  *) [ -n "$(id_of "$1")" ]; exit ;;
  esac
  ;;
run)
  # (data.sh in a helper: its mounts linked where it looks)
  while [ $# -gt 0 ] && [ "$1" != /data.sh ]; do
    case $1 in -v) case $2 in *:/s:*) ln -sfn "${2%%:/s:*}" /s ;; *:/o) ln -sfn "${2%:/o}" /o ;; *:/b:ro) ln -sfn "${2%:/b:ro}" /b ;; esac ;; esac
    shift
  done
  shift
  [ "$1" = put ] && echo "putting $(sed -n 's/^data_put //p' /st/status) | $(sed -n 's/^progress //p' /st/status)" >> $F/calls
  [ -e "$F/fail_$1" ] || [ -e "$F/fail_$1_${3:-}" ] && exit 1
  exec sh /data.sh "$@"
  ;;
stop)
  echo "journal $(sed -n 's/^data_put //p' /st/status)" >> $F/calls
  echo exited > "$F/c/$2/status"
  ;;
tag) echo "$3 $(id_of "$2") $(awk -v r="$2" '$1 == r || $2 == r {print $3; exit}' $F/refs)" >> $F/refs ;;
rmi)
  case $2 in *@*) for f in $F/rows/*; do sed -i "\| ${2#*@} |d" "$f"; done ;; esac
  [ -s $F/layers ] || exit 0
  # (a tag goes, an image with its last tag or by its id, not while a container runs it or with more tags)
  i=$(img "$2")
  grep -q "^$i " $F/layers || exit 1
  n=$(awk -v i="$i" '$2 == i && $1 !~ /@/' $F/refs | wc -l)
  case $2 in sha256:*) [ "$n" -le 1 ] || exit 1 ;; *) [ "$n" -le 1 ] || { sed -i "\|^$2 |d" $F/refs; exit 0; } ;; esac
  grep -qx "$i" $F/c/*/image 2> /dev/null && exit 1
  sed -i "\| $i |d" $F/refs
  sed -i "\|^$i |d" $F/layers
  ;;
images)
  [ "$2" = -aq ] && { [ -e $F/no_list ] || cut -d' ' -f1 $F/layers 2> /dev/null; exit 0; }
  for f; do :; done
  cat "$F/rows/$(echo "$f" | tr / _)" 2> /dev/null
  ;;
ps) ls $F/c ;;
exec)
  [ -e $F/page ] || exit 1
  [ ! -e $F/page_until ] || [ "$(cat $F/clock)" -lt "$(cat $F/page_until)" ] || exit 1
  printf '{"status":{"started":"%s"}}\n' "$(sed -n 's/^started //p' /st/status)"
  ;;
compose)
  # (its service named last, as self.sh starts it)
  for a; do :; done
  [ "$a" = svc ] || exit 1
  [ -e $F/compose_fail ] && exit 1
  r=$(cat $F/c/me/ref)
  id_of "$r" > $F/c/me/image
  [ -e $F/norestart ] || start me
  echo running > $F/c/me/status
  [ -e $F/starts ] && { sed -i '/^started /d' /st/status; echo "started 1 $(cat $F/c/me/image)" >> /st/status; }
  ;;
esac
exit 0
EOF
# (the sha256 of a new copy, failing when asked)
cat > /fake/bin/sha256sum << 'EOF'
#!/bin/sh
[ "${1:-}" = -- ] && [ -e /fake/fail_sha ] && exit 1
exec busybox sha256sum "$@"
EOF
chmod 755 /fake/bin/sha256sum
# (for self.sh: time goes on only by its sleeps, as /proc/uptime says it. a new version that starts late says so then)
mkdir -p /fake/self
cat > /fake/self/sleep << 'EOF'
#!/bin/sh
t=$(($(cat /fake/clock) + $1))
echo $t > /fake/clock
if [ -e /fake/start_at ] && [ "$t" -ge "$(cat /fake/start_at)" ]; then
  echo "started 1 $(cat /fake/c/me/image)" >> /st/status
  rm /fake/start_at
fi
EOF
cat > /fake/self/cut << 'EOF'
#!/bin/sh
if [ "$*" = "-d. -f1 /proc/uptime" ]; then cat /fake/clock; else exec busybox cut "$@"; fi
EOF
echo 0 > /fake/clock
chmod 755 /fake/bin/docker /fake/self/sleep /fake/self/cut
export PATH="/fake/bin:$PATH" STATE_DIR=/st UPDATER_CONTAINER=me UPDATER_NO_LOOP=1 MOWBITE_CONTAINER=mb OPENMOWER_CONTAINER=om PRUNE=0
fails=0
bad() { echo "logic.sh: $*"; fails=$((fails + 1)); }
box_at() {
  mkdir -p "/fake/c/$1"
  echo "$2" > "/fake/c/$1/image"
  echo "$3" > "/fake/c/$1/ref"
  echo running > "/fake/c/$1/status"
  echo s0 > "/fake/c/$1/started"
  : > "/fake/c/$1/mounts"
}
box_at me sha256:me r/updater:latest
. /updater.sh
# (the time only goes on: each look at it a second later, so no two copies are named alike)
echo 1000 > /fake/now
now() { n=$(($(cat /fake/now) + 1)) && echo "$n" > /fake/now && echo "$n"; }
mower() { cat /fake/mower; }
soon() { [ -s /fake/soon ] && cat /fake/soon; }
hold() { echo "hold $1" >> /fake/calls; [ ! -e /fake/hold_fail ] && held=" own"; }
unhold() { echo unhold >> /fake/calls; held=; }
rehold() { :; }
restart() { echo "restart $1 $2" >> /fake/calls; echo running > "/fake/c/$(box "$1")/status"; [ ! -e /fake/restart_fail ]; }
undo_change() { :; }
backs() { :; }
asked() { :; }
called() { grep -q -- "$1" /fake/calls; }
# a fresh start for a case: MowBite with its /data, OpenMower with its map and mower_params.yaml, nothing kept
fresh() {
  rm -rf /st/* /st/.[!.]* /vol/* /fake/calls /fake/fail_* /fake/hold_fail /fake/restart_fail /fake/soon /fake/rows/*
  echo 1000 > /fake/now
  echo 1 > /fake/mower
  box_at mb sha256:mb r/mowbite:latest
  echo "volume|/vol/mb|/data|true" > /fake/c/mb/mounts
  box_at om sha256:om r/om:edge
  # (the one asked for not first)
  printf 'bind|/vol/params|/data/params|true\nbind|/vol/ros|/data/ros|true\n' > /fake/c/om/mounts
  mkdir -p /vol/mb/stats /vol/ros /vol/params
  echo 1 > /vol/mb/schema
  echo token > /vol/mb/notify.conf
  echo 1 2 3 > /vol/mb/stats/hours
  echo '{"areas":["front"]}' > /vol/ros/map.json
  echo "ll: {}" > /vol/params/mower_params.yaml
  status parts openmower:om:openmower mowbite:mb:image
  : > /fake/calls
}
newest() { data_dirs "$1" | head -n1; }
# (and MowBite's data kept before an update, in $d)
kept_fresh() {
  fresh
  keep_data mowbite update || bad "not kept to begin with"
  d=$kept
}

if [ "$only" != self ] && [ "$only" != nokeep ] && [ "$only" != os ]; then
# --- kept ---
fresh
keep_data mowbite update || bad "MowBite's data not kept"
d=$(newest mowbite)
[ -n "$d" ] && [ "$kept" = "$d" ] || bad "what it kept isn't said: $kept"
[ "$(stat -c %a /st/data) $(stat -c %a "$d") $(cat "$d/why") $(cat "$d/what")" = "700 700 update 1 /vol/mb|." ] || bad "kept: $(ls -la "$d")"
(cd "$d" && sha256sum -c -s sha256) && [ "$(cat "$d/1.schema")" = 1 ] || bad "its sha256 or schema"
keep_data openmower update && d=$(newest openmower) && [ "$(cat "$d/what" | tr '\n' ' ')" = "1 /vol/ros|map.json 2 /vol/params|mower_params.yaml " ] ||
  bad "OpenMower's two pieces: $(cat "$d/what" 2> /dev/null)"
rm /vol/ros/map.json
keep_data openmower update && d=$(newest openmower) && [ "$(cat "$d/what")" = "2 /vol/params|mower_params.yaml" ] || bad "a map not there: $(cat "$d/what")"
rm /vol/params/mower_params.yaml
n=$(data_dirs openmower | wc -l)
keep_data openmower update && [ -z "$kept" ] && [ "$(data_dirs openmower | wc -l)" = "$n" ] || bad "nothing there, but a copy made"
[ -z "$(ls -d /st/data/*.new 2> /dev/null)" ] || bad "nothing there, but its folder half written stays"
fresh
keep_data plain update && [ -z "$kept" ] && [ ! -e /st/data ] || bad "a part without data: $? $kept"
fresh
rm -rf /st/data && : > /st/data
keep_data mowbite update 2> /dev/null && bad "kept where its folder can't be made"
fresh
: > /fake/fail_keep_map.json
keep_data openmower update && bad "the first of two pieces failed, but kept"
[ -z "$(ls /st/data 2> /dev/null)" ] || bad "the first piece failed, left: $(ls /st/data)"
fresh
: > /fake/fail_sha
keep_data mowbite update && bad "kept without its sha256"
[ -z "$(ls /st/data 2> /dev/null)" ] || bad "without its sha256, left: $(ls /st/data)"
rm /fake/fail_sha
fresh
(
  # (two copies within the same second: the second waits for the next)
  echo 5000 > /fake/now
  now() { cat /fake/now; }
  sleep() { echo $(($(cat /fake/now) + $1)) > /fake/now; }
  keep_data mowbite update && a=$kept && keep_data mowbite update && [ "$kept" != "$a" ] && [ -d "$a" ] && [ -d "$kept" ]
) || bad "two copies in the same second: under one name"
fresh
keep_data mowbite update && a=$kept && keep_data mowbite update && b=$kept && keep_data mowbite update && c=$kept
[ "$(data_dirs mowbite | tr '\n' ' ')" = "$c $b " ] || bad "not the newest two: $(data_dirs mowbite | tr '\n' ' ')"
keep_data mowbite put "$b" && keep_data mowbite put "$b" && [ "$(data_dirs mowbite | tr '\n' ' ')" = "$kept $(data_dirs mowbite | sed -n 2p) $b " ] &&
  [ "$(data_dirs mowbite | wc -l)" = 3 ] || bad "the one to put back went: $(data_dirs mowbite | tr '\n' ' ')"
[ "$(data_dirs mowbite update | tr '\n' ' ')" = "$b " ] && [ "$(data_dirs mowbite put | wc -l)" = 2 ] || bad "by why: $(data_dirs mowbite update)"
fresh
mkdir -p /st/data/mowbite-5.new /st/data/openmower-5.new
keep_data mowbite update
[ ! -e /st/data/mowbite-5.new ] && [ -e /st/data/openmower-5.new ] || bad "a copy half written of its own stays, or another's went"
fresh
: > /fake/fail_keep_mower_params.yaml
keep_data openmower update && bad "a helper that failed, but kept"
[ -z "$(ls /st/data 2> /dev/null)" ] || bad "left of it: $(ls /st/data)"
rm /fake/fail_keep_mower_params.yaml
(free_mb() { echo 99; }; keep_data mowbite update) && bad "kept with less than 100 MB free"
[ -z "$(ls /st/data 2> /dev/null)" ] && grep -q "not enough room to keep" /st/log || bad "no room: $(ls /st/data)"
(free_mb() { echo 100; }; keep_data mowbite update) || bad "not kept with 100 MB free"

# --- put back ---
kept_fresh
before=$(cd /vol/mb && find . -type f | sort | xargs cat)
echo 2 > /vol/mb/schema && echo other > /vol/mb/notify.conf && rm -r /vol/mb/stats && echo new > /vol/mb/junk
put_data mowbite "$d" || bad "not put back"
[ "$(cd /vol/mb && find . -type f | sort | xargs cat)" = "$before" ] || bad "put back, but not as it was"
called "^stop mb" && grep -A1 "^stop mb" /fake/calls | grep -q "^journal mowbite $d" || bad "not stopped, or before what it does was noted"
grep -q "^putting mowbite $d /st/data/mowbite-[0-9]* | mowbite data " /fake/calls || bad "while it puts back: $(grep '^putting' /fake/calls)"
[ -z "$(get data_put)" ] || bad "what it did still noted: $(get data_put)"
k=$(data_dirs mowbite put | head -n1)
[ -n "$k" ] && [ "$(tar -xOf "$k/1.tar" ./notify.conf)" = other ] && [ -d "$d" ] || bad "what it had not kept first, or the copy put back gone"
called "^restart" && bad "started again in put_data"
kept_fresh
echo x >> "$d/1.tar"
echo other > /vol/mb/notify.conf
put_data mowbite "$d" && bad "a changed copy put back"
[ "$(cat /vol/mb/notify.conf)" = other ] && ! called "^stop" && [ -z "$(data_dirs mowbite put)" ] || bad "a changed copy: something changed"
kept_fresh
echo "volume|/vol/other|/data|true" > /fake/c/mb/mounts
put_data mowbite "$d" && bad "put back where it isn't mounted any more"
! called "^stop" || bad "stopped for a mount that went"
kept_fresh
(free_mb() { echo 50; }; put_data mowbite "$d") && bad "put back without room"
! called "^stop" || bad "stopped without room"
kept_fresh
echo other > /vol/mb/notify.conf
(keep_data() { return 1; }; put_data mowbite "$d") && bad "put back without keeping what it had"
[ "$(cat /vol/mb/notify.conf)" = other ] && [ -z "$(get data_put)" ] || bad "what it had not kept: something changed"
kept_fresh
: > /fake/fail_put
put_data mowbite "$d" && bad "a helper that failed to put it back, said done"
[ -z "$(get data_put)" ] && grep -q "couldn't all be put back" /st/log || bad "a failed putting back: $(get data_put)"

# --- the format of its data ---
kept_fresh
[ -z "$(newer_data mowbite)" ] || bad "the same schema taken for a higher one"
echo 2 > /vol/mb/schema
[ "$(newer_data mowbite)" = "$d" ] || bad "a higher schema not seen"
keep_data mowbite put
[ "$(newer_data mowbite)" = "$d" ] || bad "a copy before putting back taken for the one before the update"
echo x > /vol/mb/schema
[ -z "$(newer_data mowbite)" ] || bad "a schema that isn't a number taken for higher"
echo 0 > /vol/mb/schema
[ -z "$(newer_data mowbite)" ] || bad "a lower schema taken for higher"
fresh
rm /vol/mb/schema
keep_data mowbite update
echo 2 > /vol/mb/schema
[ -z "$(newer_data mowbite)" ] || bad "no schema kept, but going back with its data"
fresh
[ -z "$(newer_data mowbite)" ] || bad "nothing kept, but something to go back to"
kept_fresh
echo 2 > /vol/mb/schema
keep_data mowbite update
[ -z "$(newer_data mowbite)" ] || bad "the copy before the last update isn't the one that counts"

# --- going back by itself ---
kept_fresh
echo 2 > /vol/mb/schema && echo other > /vol/mb/notify.conf
status pending_mowbite rb-1 r/mowbite:latest sha256:new
go_back mowbite rb-1 r/mowbite:latest sha256:new
[ "$(get mowbite)" = "rolled_back data" ] && [ "$(cat /vol/mb/notify.conf)" = token ] && [ "$(cat /vol/mb/schema)" = 1 ] ||
  bad "a higher schema: $(get mowbite), $(cat /vol/mb/notify.conf)"
[ "$(grep -n "^restart mowbite" /fake/calls | cut -d: -f1)" -gt "$(grep -n "^stop mb" /fake/calls | cut -d: -f1)" ] || bad "started before its data was back"
[ -z "$(get pending_mowbite)" ] && [ "$(get mowbite_failed)" = sha256:new ] || bad "pending $(get pending_mowbite), left out $(get mowbite_failed)"
kept_fresh
echo other > /vol/mb/notify.conf
go_back mowbite rb-1 r/mowbite:latest sha256:new
[ "$(get mowbite)" = rolled_back ] && [ "$(cat /vol/mb/notify.conf)" = other ] && ! called "^stop" || bad "the same schema: $(get mowbite)"
kept_fresh
echo 2 > /vol/mb/schema && echo x >> "$kept/1.tar"
go_back mowbite rb-1 r/mowbite:latest sha256:new
[ "$(get mowbite)" = "error data_put" ] && called "^restart mowbite" || bad "its data not back: $(get mowbite)"
fresh
go_back mowbite rb-1 r/mowbite:latest sha256:new
[ "$(get mowbite)" = rolled_back ] && ! called "^stop" || bad "nothing kept: $(get mowbite)"
fresh
: > /fake/restart_fail
go_back mowbite rb-1 r/mowbite:latest sha256:new
[ "$(get mowbite)" = "error rollback" ] || bad "not started again: $(get mowbite)"

# --- by hand ---
fresh
put_by_hand mowbite 77
[ "$(get mowbite)" = "error no_data" ] && ! called "^hold" || bad "a copy it doesn't have: $(get mowbite)"
keep_data mowbite update
t=${kept##*-}
echo 1777 > /fake/soon
put_by_hand mowbite "$t"
[ "$(get mowbite)" = "error schedule 1777" ] && ! called "^hold" || bad "before the schedule: $(get mowbite)"
rm /fake/soon
: > /fake/hold_fail
put_by_hand mowbite "$t"
[ "$(get mowbite)" = "error hold" ] && ! called "^stop" || bad "without the hold: $(get mowbite)"
rm /fake/hold_fail
echo "0 MOWING" > /fake/mower
: > /fake/calls
put_by_hand mowbite "$t"
[ "$(get mowbite)" = "error not_docked" ] && called "^unhold" && ! called "^stop" || bad "out of the dock: $(get mowbite)"
echo 1 > /fake/mower
echo other > /vol/mb/notify.conf
: > /fake/calls
put_by_hand mowbite "$t"
[ "$(get mowbite | cut -d' ' -f1,3)" = "data_back $t" ] && [ "$(cat /vol/mb/notify.conf)" = token ] && called "^restart mowbite" && called "^unhold" ||
  bad "by hand: $(get mowbite)"
! grep -q "doesn't answer" /st/log || bad "it answered, but the log says it doesn't"
echo exited > /fake/c/mb/status
: > /fake/calls
put_by_hand mowbite "$t"
[ "$(get mowbite | cut -d' ' -f1)" = data_back ] && ! called "^restart" || bad "a stopped part started after its data was put back"
echo running > /fake/c/mb/status
: > /fake/fail_put
: > /fake/calls
put_by_hand mowbite "$t"
[ "$(get mowbite)" = "error data_put" ] && called "^restart mowbite" || bad "stopped and then failed: not started again"
rm /fake/fail_put
echo x >> "/st/data/mowbite-$t/1.tar"
: > /fake/calls
put_by_hand mowbite "$t"
[ "$(get mowbite)" = "error data_put" ] && ! called "^restart" && called "^unhold" || bad "a changed copy by hand: $(get mowbite)"

# --- stopped halfway ---
kept_fresh
keep_data mowbite put "$d"
echo other > /vol/mb/notify.conf && mkdir /vol/mb/.updater-put && echo half > /vol/mb/.updater-put/x
echo exited > /fake/c/mb/status
status data_put mowbite "$d" "$kept"
: > /fake/calls
recover
[ "$(cat /vol/mb/notify.conf)" = token ] && [ ! -e /vol/mb/.updater-put ] && [ -z "$(get data_put)" ] && called "^restart mowbite" ||
  bad "put back halfway: $(cat /vol/mb/notify.conf), $(get data_put)"
kept_fresh
echo other > /vol/mb/notify.conf
echo exited > /fake/c/mb/status
status data_put mowbite "$kept"
: > /fake/calls
recover
[ "$(cat /vol/mb/notify.conf)" = other ] && [ -z "$(get data_put)" ] && called "^restart mowbite" && ! called "^stop" ||
  bad "stopped before what it had was kept: $(cat /vol/mb/notify.conf)"
kept_fresh
echo exited > /fake/c/mb/status
status data_put mowbite "$kept" "$kept"
status pending_mowbite rb-1 r/mowbite:latest sha256:new
: > /fake/calls
recover
! called "^restart" || bad "started though it waits to be seen running"
kept_fresh
: > /fake/fail_put
status data_put mowbite "$kept" "$kept"
recover
[ "$(get mowbite)" = "error data_put" ] || bad "a failed putting back halfway: $(get mowbite)"
fresh
status data_put mowbite /st/data/mowbite-1
: > /fake/calls
recover
! called "^restart" && [ -z "$(get data_put)" ] || bad "stopped before it stopped the part: started again though it runs"
status data_put mowbite /st/data/mowbite-1 -
recover
[ "$(get mowbite)" = "error data_put" ] && [ -z "$(get data_put)" ] || bad "its copy gone, but put back: $(get mowbite)"

# --- what a pull by its digest leaves ---
fresh
printf '<none> sha256:d1 sha256:i1\n<none> sha256:d2 sha256:i2\nedge sha256:d3 sha256:i3\n<none> <none> sha256:i4\n' > /fake/rows/r_om
echo sha256:i2 > /fake/c/mb/image
tidy
called "rmi r/om@sha256:d1" && [ "$(grep -c '^rmi' /fake/calls)" = 1 ] || bad "what a pull by its digest left: $(grep '^rmi' /fake/calls | tr '\n' ' ')"
: > /fake/calls
status pending_openmower rb-1 r/om:edge sha256:new
tidy
! called "^rmi" || bad "tidied while OpenMower waits to be seen running"

# --- the rest of a request after its own update ---
fresh
status after_self all
rest_after_self
[ "$(tr '\n' ' ' < "$REQ")" = "now openmower now mowbite " ] && [ -z "$(get after_self)" ] || bad "all of it again: $(cat "$REQ")"
rm -f "$REQ"
status after_self mowbite openmower
rest_after_self
[ "$(tr '\n' ' ' < "$REQ")" = "now mowbite now openmower " ] || bad "the parts again: $(cat "$REQ")"
rm -f "$REQ"
rest_after_self
[ ! -e "$REQ" ] || bad "asked though nothing waited"

fi

if [ "$only" != data ] && [ "$only" != nokeep ] && [ "$only" != os ]; then
# --- its own update ---
# (self.sh as the helper runs it, its time going on by its sleeps. the new version starts at once (starts) or at a
# second (at=), its page answers (page) until a second (until=))
selfrun() {
  echo 0 > /fake/clock
  rm -f /fake/starts /fake/page /fake/page_until /fake/crashloop /fake/compose_fail /fake/norestart /fake/start_at /st/status /st/log
  box_at me sha256:old r/updater:latest
  printf 'r/updater:latest sha256:new r/updater@sha256:dnew\nr/updater:previous sha256:old r/updater@sha256:dold\n' > /fake/refs
  for o in "$@"; do
    case $o in
    at=*) echo "${o#at=}" > /fake/start_at ;;
    until=*) echo "${o#until=}" > /fake/page_until ;;
    no=*) sed -i "\|^${o#no=} |d" /fake/refs ;;
    *) : > "/fake/$o" ;;
    esac
  done
  : > /fake/calls
  PATH=/fake/self:$PATH sh /self.sh r/updater:latest r/updater:previous > /dev/null 2>&1
}
back() { called "^tag r/updater:previous r/updater:latest"; }
stays() { grep -q "runs and answers" /st/log && ! back && [ -z "$(get updater_failed)" ]; }
selfrun starts page
stays || bad "its new version runs and answers, but it went back"
selfrun page at=60
stays || bad "a minute to start, but it went back"
selfrun page
back && [ "$(get updater_failed)" = "sha256:new sha256:dnew" ] && [ "$(grep -c '^compose' /fake/calls)" = 2 ] || bad "never said it started: $(get updater_failed)"
selfrun starts
back && grep -q "didn't come up or didn't answer" /st/log || bad "its page doesn't answer, but it stays"
selfrun starts page crashloop
back || bad "starting again and again, but it stays"
selfrun starts page norestart
back || bad "not started anew, but it stays"
selfrun starts page compose_fail
back && [ -z "$(get updater_failed)" ] && grep -q "couldn't be started" /st/log && [ "$(grep -c '^compose' /fake/calls)" = 2 ] ||
  bad "compose failed: left out $(get updater_failed), the one before not started again"
selfrun page at=170
stays || bad "started within three minutes, then 45 s on that start, but it went back"
selfrun page at=185
back || bad "started after three minutes, but it stays"
selfrun starts page until=50
stays || bad "answered its 45 s, but it went back"
selfrun starts page until=45
back || bad "stopped answering within its 45 s, but it stays"
selfrun starts page no=r/updater:latest
! called "^compose" && ! back || bad "no new image, but started"
selfrun starts page no=r/updater:previous
! called "^compose" || bad "no way back, but started"
fi

if [ "$only" = all ] || [ "$only" = nokeep ]; then
# --- OpenMower without a copy ---
# (OpenMower r/om:edge with layers l1 l2 l3, its new version l1 n2 n3 of 201 MB packed: 1000 MB missing x5 and 1 GB
# don't fit in 1500 MB free, with 600 MB of build cache and the image that runs gone all of it does. the planner pl
# built on it, an older planner image r/pl:before-1 with one of its layers, an image of its own with only l1 and
# MowBite on others. compose, the downloads, the registry and github as functions)
PLANNER=pl
# (its build cache cleared too, docker here is the script)
PRUNE=1
C1=1111111111111111111111111111111111111111
mkdir -p /stk
: > /stk/compose.yaml
NK_REFS='r/om:edge sha256:om r/om@sha256:dom
r/pl:edge sha256:pl -
r/pl:before-1 sha256:pl0 -
r/om:mine sha256:loc -
r/mowbite:latest sha256:mb r/mowbite@sha256:dmb'
nk_fresh() {
  fresh
  rm -rf /fake/sizes /fake/c/pl /fake/c/x /fake/builds /fake/pull_fail /fake/build_fail /fake/nostart* /fake/reg_gone /fake/reg_down /fake/gh_down /fake/no_ids /fake/rm_fail_* /fake/page /fake/no_list /fake/external
  printf '%s\n' "$NK_REFS" > /fake/refs
  printf 'sha256:om l1 l2 l3\nsha256:pl l1 l2 l3 p1\nsha256:pl0 l1 l2 p0\nsha256:loc l1 l9\nsha256:mb m1\n' > /fake/layers
  box_at pl sha256:pl r/pl:edge
  printf '# its stack\nVERSION="edge"\n' > /stk/.env
  echo 1500 > /fake/free
  echo 629145600 > /fake/cache
  check_room
  status parts openmower:om:openmower planner:pl:build mowbite:mb:image
  status planner_image sha256:pl
  status planner_built "$C1"
  status planner_base_id sha256:om
  : > /fake/calls
  WHY=request MANUAL=1 NOKEEP=
  nk_next=
  nk_start=
  gone_next=
  rebuilt=
}
free_mb() { cat /fake/free; }
check_room() { echo "cache $(cat /fake/cache)" > "$STATE/room"; }
remote_digest() { echo sha256:dnew; }
layers() { printf 'aaaaaaaaaaaa 1048576\nbbbbbbbbbbbb 104857600\ncccccccccccc 104857600\n'; }
diff_ids() { [ -e /fake/no_ids ] || printf 'l1\nn2\nn3\n'; }
in_registry() { [ -e /fake/reg_down ] && return 2; ! grep -qxF "$1" /fake/reg_gone 2> /dev/null; }
want_of() { [ -e /fake/gh_down ] && return 1; echo "$C1 v1.0.0 release"; }
base_of() { [ "$1" = pl ] && echo r/om:edge; }
context_of() { [ "$1" = pl ] && echo https://github.com/x/pl.git#main; }
with_progress() {
  shift 2
  "$@"
}
pull_image() {
  echo "pull $1" >> /fake/calls
  [ -e /fake/pull_fail ] && return 1
  case $1 in
  *@*) echo "$1 sha256:om $1" >> /fake/refs && echo "sha256:om l1 l2 l3" >> /fake/layers ;;
  *) sed -i "\\|^$1 |d" /fake/refs && echo "$1 sha256:new r/om@sha256:dnew" >> /fake/refs && echo "sha256:new l1 n2 n3" >> /fake/layers ;;
  esac
}
# (rm, build and up of a stack's service, an image built anew each time)
compose() {
  local c="$2" r n
  shift 2
  echo "compose $c $*" >> /fake/calls
  case " $* " in
  *" rm "*) [ ! -e "/fake/rm_fail_$c" ] && rm -rf "/fake/c/$c" ;;
  *" build "*)
    [ -e /fake/build_fail ] && return 1
    n=$(($(cat /fake/builds 2> /dev/null || echo 0) + 1)) && echo $n > /fake/builds
    r=$(ref_of "$c")
    sed -i "\\|^$r |d" /fake/refs
    echo "$r sha256:b$n -" >> /fake/refs
    echo "sha256:b$n l1 n2 n3 p1" >> /fake/layers
    ;;
  *" up "*)
    r=$(ref_of "$c")
    mkdir -p "/fake/c/$c"
    echo "$r" > "/fake/c/$c/ref"
    id_of "$r" > "/fake/c/$c/image"
    case " $* " in *" --no-start "*) echo created ;; *) echo running ;; esac > "/fake/c/$c/status"
    echo s0 > "/fake/c/$c/started"
    if [ "$c" = om ]; then printf 'bind|/vol/params|/data/params|true\nbind|/vol/ros|/data/ros|true\n'; fi > "/fake/c/$c/mounts"
    ;;
  esac
}
restart() {
  echo "restart $1 $2" >> /fake/calls
  compose 1 "$(box "$1")" up -d "$(service "$(box "$1")")" && seen "$1" "$2"
}
# (a new version that doesn't run: its id in nostart, or nostart_<part>. external: as with OM_PLANNER=external, OpenMower
# answers only while the planner runs, the planner only while OpenMower runs)
seen() {
  fw_failed=
  echo "seen $1 $2" >> /fake/calls
  [ "$(image_of "$(box "$1")")" = "$2" ] && ! grep -qx "$2" /fake/nostart 2> /dev/null && [ ! -e "/fake/nostart_$1" ] || return 1
  [ ! -e /fake/external ] || if [ "$1" = openmower ]; then running pl; else running om; fi
}
mower() { if [ -e /fake/external ] && [ -d /fake/c/om ] && ! running pl; then echo "0 unknown"; else cat /fake/mower; fi; }
id() { cat "/fake/c/$1/image" 2> /dev/null; }
nokeep() { NOKEEP=1 WHY=nokeep update_openmower; }
first() { grep -n -- "$1" /fake/calls | head -n1 | cut -d: -f1; }

# offered
nk_fresh
update_openmower
[ "$(get openmower | cut -d' ' -f1)" = nospace ] && [ "$(get openmower_nokeep)" = "yes 201 planner r/om:edge,r/pl:edge r/pl:before-1" ] ||
  bad "nokeep: not offered: $(get openmower), $(get openmower_nokeep)"
! called "^compose" && ! called "^rmi" && [ "$(id om)" = sha256:om ] || bad "nokeep: only offered, but something changed"
# and not: each reason
nk_fresh
echo r/om@sha256:dom > /fake/reg_gone
update_openmower
[ "$(get openmower_nokeep)" = "no prev" ] || bad "nokeep: the version that runs not in its registry, but: $(get openmower_nokeep)"
nk_fresh
sed -i '/^r\/om:edge /s/ r\/om@sha256:dom$/ -/' /fake/refs
update_openmower
[ "$(get openmower_nokeep)" = "no prev" ] || bad "nokeep: one built here, but: $(get openmower_nokeep)"
nk_fresh
echo 'openmower latest' > "$CONF"
update_openmower
[ "$(get openmower_nokeep)" = "no base planner" ] || bad "nokeep: another channel with the planner on it, but: $(get openmower_nokeep)"
nk_fresh
printf 'VERSION="mine"\n' > /stk/.env
echo 'openmower edge' > "$CONF"
update_openmower
[ "$(get openmower_nokeep)" = "no env" ] || bad "nokeep: its .env saved with another version, but: $(get openmower_nokeep)"
rm -f "$CONF"
nk_fresh
: > /fake/no_ids
update_openmower
[ "$(get openmower_nokeep)" = "no registry" ] || bad "nokeep: the new version's layers unknown, but: $(get openmower_nokeep)"
nk_fresh
echo 0 > /fake/cache
check_room
update_openmower
[ "$(get openmower_nokeep)" = "no room 2029 1500" ] || bad "nokeep: no room either way, but: $(get openmower_nokeep)"
# (the image that runs counted as docker lists it, not as inspect's packed Size of containerd's store)
echo 'sha256:om 600MB' > /fake/sizes
update_openmower
[ "$(get openmower_nokeep | cut -d' ' -f1)" = yes ] || bad "nokeep: room with the image that runs gone, but: $(get openmower_nokeep)"
nk_fresh
box_at x sha256:pl0 r/pl:before-1
update_openmower
[ "$(get openmower_nokeep)" = "no box x" ] || bad "nokeep: another container on its layers, but: $(get openmower_nokeep)"
nk_fresh
: > /fake/gh_down
status planner_release v0.9.0
update_openmower
[ "$(get openmower_nokeep | cut -d' ' -f1)" = yes ] || bad "nokeep: github away, the commit it runs known, but: $(get openmower_nokeep)"
status planner_built
update_openmower
[ "$(get openmower_nokeep)" = "no github planner" ] || bad "nokeep: github away and the commit it runs unknown, but: $(get openmower_nokeep)"
# asked for, not offered any more: nothing deleted
nk_fresh
echo 0 > /fake/cache
nokeep
! called "^compose" && ! called "^rmi" && [ "$(id om)" = sha256:om ] && [ -z "$(get nokeep_openmower)" ] && [ "$(get openmower | cut -d' ' -f1)" = nospace ] ||
  bad "nokeep: asked for without room, but: $(get openmower)"
# its way back gone from its registry right before: nothing deleted
nk_fresh
(
  keep_data() { echo r/om@sha256:dom > /fake/reg_gone; }
  nokeep
)
! called "^compose" && ! called "^rmi" && [ "$(id om)" = sha256:om ] && [ "$(get openmower)" = "error registry" ] &&
  [ -z "$(get nokeep_openmower)$(get gone_openmower)$(get openmower_fw_check)" ] || bad "nokeep: no way back right before, but: $(get openmower)"
nk_fresh
echo "0 MOWING" > /fake/mower
nokeep
[ $? = 2 ] && ! called "^compose" && [ "$(id om)" = sha256:om ] || bad "nokeep: out of the dock, but something changed"

# done: the builds' containers removed first, then OpenMower's, then the images
nk_fresh
nokeep
[ "$(get openmower | cut -d' ' -f1,3)" = "updated edge" ] && [ "$(id om)" = sha256:new ] && [ "$(get openmower_prev)" = r/om@sha256:dom ] ||
  bad "nokeep: not updated: $(get openmower), runs $(id om)"
[ "$(get planner | cut -d' ' -f1,3)" = "updated v1.0.0" ] && [ "$(id pl)" = sha256:b1 ] && [ "$(get planner_base_id)" = sha256:new ] &&
  [ "$(cat /fake/c/pl/status)" = running ] || bad "nokeep: the planner not built again: $(get planner), runs $(id pl)"
! grep -q '^gone_\|^nokeep_\|^openmower_missing\|^openmower_fw_check\|^changed_' /st/status || bad "nokeep: notes left: $(grep '^gone_\|^nokeep_\|^openmower_missing' /st/status)"
! grep -q 'sha256:pl0\|sha256:pl \|sha256:om' /fake/layers && grep -q '^sha256:loc ' /fake/layers && grep -q '^sha256:mb ' /fake/layers ||
  bad "nokeep: not what holds its layers deleted: $(cut -d' ' -f1 /fake/layers | tr '\n' ' ')"
[ "$(first 'compose pl .*rm')" -lt "$(first 'compose om .*rm')" ] && [ "$(first 'compose om .*rm')" -lt "$(first '^rmi')" ] &&
  [ "$(first '^rmi')" -lt "$(first '^pull r/om:edge')" ] && [ "$(first 'builder prune')" -lt "$(first '^pull')" ] ||
  bad "nokeep: not in its order: $(grep '^compose\|^rmi\|^pull\|builder' /fake/calls | tr '\n' '|')"
! grep '^compose' /fake/calls | grep -q -- ' -v' && ! grep -q '^rmi -f' /fake/calls || bad "nokeep: volumes or forced"
[ "$(grep '^pull\|^unhold\|^hold\|^restart openmower' /fake/calls | sed '/^restart openmower/q' | tail -n 4 | tr '\n' '|')" = "pull r/om:edge|unhold|hold openmower|restart openmower sha256:new|" ] ||
  bad "nokeep: not held anew right before its start: $(grep '^pull\|^unhold\|^hold\|^restart' /fake/calls | tr '\n' '|')"
[ -n "$(data_dirs openmower update)" ] && grep -q '^VERSION="edge"$' /stk/.env || bad "nokeep: its data not kept or its .env changed"

# a container's labels, its image and its stack from its note while it's gone (docker says an empty line for it)
nk_fresh
rm -rf /fake/c/om
mkdir -p /stkx
: > /stkx/.env
status gone_openmower om r/om:edge running 'projx|/stkx|/stkx/c.yaml,/stkx/d.yaml|.env,/stkx/none.env' svcx
[ "$(om_env)" = /stkx/.env ] && [ "$(service om)" = svcx ] && [ "$(ref_of om)" = r/om:edge ] ||
  bad "nokeep: from its note: $(om_env | od -c | head -n1), $(service om), $(ref_of om)"
(
  . /lib.sh
  compose 5 om rm -s -f svcx
)
called '^compose -p projx --project-directory /stkx --env-file /stkx/.env -f /stkx/c.yaml -f /stkx/d.yaml rm -s -f svcx$' ||
  bad "nokeep: compose from its note: $(grep '^compose' /fake/calls)"
# (its restart and a failed download's words as the updater has them, not as the cases here make them)
(
  . /updater.sh
  seen() { :; }
  restart openmower sha256:om
  log "openmower: downloading r/om:new"
  with_progress openmower none sh -c 'echo "{\"error\":true,\"message\":\"manifest unknown\"}"; exit 1'
  [ "$(nokeep_never r/om:new)" = unknown ] || echo never >> /fake/calls
)
# a MowBite OS host: never held from here, also when it doesn't answer
(
  . /updater.sh
  os_host() { true; }
  om_brokers() { echo own; return 2; }
  on_broker() { echo "pub $*" >> /fake/calls; }
  hold planner && echo held >> /fake/calls
)
! called '^pub\|^held' || bad "hold on an os host: $(grep '^pub\|^held' /fake/calls | tr '\n' '|')"
called '^compose -p projx --project-directory /stkx --env-file /stkx/.env -f /stkx/c.yaml -f /stkx/d.yaml up -d --no-deps --no-build --pull never --force-recreate svcx$' &&
  ! called '^never' || bad "nokeep: its restart or download from its note: $(grep '^compose\|^never' /fake/calls | tr '\n' '|')"
# OpenMower's brokers: none to ask while it's gone for its update, as before otherwise
om_brokers > /dev/null
[ $? = 2 ] || bad "nokeep: om_brokers with OpenMower gone for its update"
status gone_openmower
echo "0 MOWING" > /fake/mower
om_brokers > /dev/null
[ $? = 1 ] || bad "nokeep: om_brokers with OpenMower gone by itself"
# the interface takes nokeep only while it's offered
sed 's|^request() {.*|request() { echo "$1" >> /fake/req; plain ok; }|' /r/www/cgi-bin/updater > /fake/cgi
cgi() { REQUEST_METHOD=POST CONTENT_TYPE=application/json QUERY_STRING=$1 sh /fake/cgi > /dev/null 2>&1; }
nk_fresh
rm -f /fake/req
status openmower_nokeep no room 2029 1500
cgi nokeep=openmower
status openmower_nokeep yes 201 planner r/om:edge -
cgi nokeep=planner
cgi nokeep=openmower
[ "$(cat /fake/req 2> /dev/null)" = "nokeep openmower" ] || bad "nokeep: the interface took $(cat /fake/req 2> /dev/null | tr '\n' '|')"
# not offered when what holds the version that runs isn't known
nk_fresh
: > /fake/no_list
update_openmower
[ "$(get openmower_nokeep)" = "no holders" ] || bad "nokeep: holders unknown, but: $(get openmower_nokeep)"

# a container that can't be removed: nothing deleted, the ones removed back
nk_fresh
: > /fake/rm_fail_pl
nokeep
[ "$(get openmower)" = "error remove" ] && [ "$(id om)" = sha256:om ] && [ "$(id pl)" = sha256:pl ] && ! called '^rmi' && ! called 'compose om .*rm' &&
  ! grep -q '^gone_\|^nokeep_' /st/status || bad "nokeep: the planner's container stayed: $(get openmower), $(grep '^gone_\|^nokeep_' /st/status)"
nk_fresh
: > /fake/rm_fail_om
nokeep
[ "$(get openmower)" = "error remove" ] && [ "$(id om)" = sha256:om ] && [ "$(id pl)" = sha256:pl ] && [ "$(cat /fake/c/pl/status)" = running ] &&
  ! called '^rmi' && ! grep -q '^gone_\|^nokeep_' /st/status || bad "nokeep: OpenMower's container stayed: $(get openmower), planner $(id pl)"

# and one removed before that can't be made again: its note stays, its card with it
nk_fresh
: > /fake/rm_fail_om
(
  restart() { [ "$1" != planner ] && compose 1 "$(box "$1")" up -d svc; }
  nokeep
)
find_parts
[ "$(get openmower)" = "error undo" ] && [ -n "$(get gone_planner)" ] && [ -z "$(get nokeep_openmower)$(get gone_openmower)" ] && ! called '^rmi' &&
  case " $(get parts) " in *" planner:pl:build "*) true ;; *) false ;; esac || bad "nokeep: one not made again: $(get openmower), $(get parts)"

# stopped while the containers are removed: on at the start, or put back while the mower mows
nk_stopped() {
  nk_fresh
  (
    box_rm() { [ "$1" != om ] || exit 9; compose 1 "$1" rm -s -f svc; ! exists "$1"; }
    nokeep
  )
}
nk_stopped
find_parts
[ "$(get nokeep_openmower | cut -d' ' -f1)" = rm ] && [ -n "$(get gone_openmower)" ] && [ -n "$(get gone_planner)" ] && [ "$(get openmower)" = replacing ] ||
  bad "nokeep: stopped while removing: $(get nokeep_openmower), $(get openmower)"
WHY=start MANUAL='' update_openmower
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(id om)" = sha256:new ] && [ "$(id pl)" = sha256:b1 ] && ! grep -q '^sha256:om ' /fake/layers ||
  bad "nokeep: not on after a stop while removing: $(get openmower), $(get planner)"
nk_stopped
echo "0 MOWING" > /fake/mower
WHY=start MANUAL='' update_openmower
[ "$(get openmower)" = "error not_docked" ] && [ "$(id om)" = sha256:om ] && [ "$(id pl)" = sha256:pl ] && ! called '^rmi' &&
  ! grep -q '^gone_\|^nokeep_' /st/status || bad "nokeep: not put back with the mower out: $(get openmower), planner $(id pl)"
# or its way back gone from the registry meanwhile
nk_stopped
echo r/om@sha256:dom > /fake/reg_gone
WHY=start MANUAL='' update_openmower
[ "$(get openmower)" = "error registry" ] && [ "$(id om)" = sha256:om ] && [ "$(id pl)" = sha256:pl ] && ! called '^rmi' &&
  ! grep -q '^gone_\|^nokeep_' /st/status || bad "nokeep: on after a stop without its way back: $(get openmower), planner $(id pl)"
# stopped while the images are deleted: the rest of them first
nk_fresh
(
  drop_image() { [ ! -e /fake/dropped ] || exit 9; : > /fake/dropped; docker rmi "$1"; }
  nokeep
)
rm -f /fake/dropped
[ "$(get nokeep_openmower | cut -d' ' -f1)" = drop ] || bad "nokeep: stopped while deleting: $(get nokeep_openmower)"
WHY=start MANUAL='' update_openmower
[ "$(get openmower | cut -d' ' -f1)" = updated ] && ! grep -q 'sha256:pl0\|sha256:om ' /fake/layers && [ -z "$(get nokeep_holders)" ] ||
  bad "nokeep: not on after a stop while deleting: $(get openmower), $(cut -d' ' -f1 /fake/layers | tr '\n' ' ')"

# a download that fails: OpenMower missing, tried again, then done
nk_fresh
: > /fake/pull_fail
nokeep
# shellcheck disable=SC2046
set -- $(get openmower_missing)
[ "$(get openmower)" = "error missing" ] && [ "$1" = 0 ] && [ "$2" -gt "$(cat /fake/now)" ] && [ "$3 $4 $5 $6 $7" = "new r/om:edge r/om@sha256:dom r/om:edge /stk" ] &&
  [ ! -e /fake/c/om ] || bad "nokeep: a download that failed: $(get openmower), $(get openmower_missing)"
! nokeep_due || bad "nokeep: missing, but a try due"
find_parts
case " $(get parts) " in *" openmower:om:openmower "*" planner:pl:build "*) ;; *) bad "nokeep: what's missing not a part any more: $(get parts)" ;; esac
check_part openmower
check_part planner
[ "$(get openmower_available | cut -d' ' -f1)" = yes ] && [ "$(get planner_available)" = "yes v1.0.0" ] && [ "$(label pl service)" = svc ] ||
  bad "nokeep: missing, its card: $(get openmower_available), $(get planner_available)"
(back_openmower) || [ "$(get openmower)" = "error nokeep" ] || bad "nokeep: back to the version before while it's missing: $(get openmower)"
echo 2000000000 > /fake/now
nokeep_due || bad "nokeep: a try not due after its time"
n=1
while [ $n -le 6 ]; do WHY=again MANUAL='' update_openmower; n=$((n + 1)); done
[ "$(get openmower_missing | cut -d' ' -f1,2)" = "6 -" ] && ! nokeep_due || bad "nokeep: after six tries: $(get openmower_missing)"
[ "$(grep -c '^pull' /fake/calls)" = 7 ] || bad "nokeep: tries: $(grep -c '^pull' /fake/calls)"
WHY=night MANUAL='' update_openmower
[ "$(grep -c '^pull' /fake/calls)" = 7 ] || bad "nokeep: tried again at night"
nk_start=1
nokeep_due && nk_start= || bad "nokeep: no try at its start"
WHY=request update_openmower
[ "$(get openmower_missing | cut -d' ' -f1)" = 0 ] && [ "$(get openmower_missing | cut -d' ' -f2)" != - ] || bad "nokeep: a tap didn't start its tries anew: $(get openmower_missing)"
rm /fake/pull_fail
# (and the schedule can't be held while it's missing: the broker in its container)
(
  hold() { echo "hold $1" >> /fake/calls; [ -d /fake/c/om ]; }
  WHY=again MANUAL='' update_openmower
)
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(id om)" = sha256:new ] && [ "$(id pl)" = sha256:b1 ] && [ -z "$(get openmower_missing)$(get nokeep_openmower)" ] ||
  bad "nokeep: a try after the download failed: $(get openmower), $(get planner)"
# downloaded on a later try, it doesn't run and the mower's out meanwhile: there, not missing any more
nk_fresh
: > /fake/pull_fail
nokeep
rm /fake/pull_fail
echo sha256:new > /fake/nostart
echo "0 MOWING" > /fake/mower
WHY=again MANUAL='' update_openmower
[ "$(get openmower)" = unconfirmed ] && [ -e /fake/c/om ] && [ -z "$(get openmower_missing)" ] && [ "$(get nokeep_openmower | cut -d' ' -f1)" = back ] ||
  bad "nokeep: there again but not seen running: $(get openmower), $(get openmower_missing)"
# the version before started by hand meanwhile: said so, not taken for the new one
nk_fresh
: > /fake/pull_fail
nokeep
printf 'r/om@sha256:dom sha256:om r/om@sha256:dom\nr/om:edge sha256:om r/om@sha256:dom\n' >> /fake/refs
echo "sha256:om l1 l2 l3" >> /fake/layers
box_at om sha256:om r/om:edge
WHY=again MANUAL='' update_openmower
[ "$(get openmower)" = "rolled_back hand" ] && [ -z "$(get openmower_prev)$(get nokeep_openmower)$(get openmower_missing)" ] ||
  bad "nokeep: the version before by hand: $(get openmower), prev $(get openmower_prev)"
# one its registry doesn't have: back to the one before at once
nk_fresh
(
  pull_image() {
    echo "pull $1" >> /fake/calls
    case $1 in
    *@*) echo "$1 sha256:om $1" >> /fake/refs && echo "sha256:om l1 l2 l3" >> /fake/layers ;;
    *) echo "Error response from daemon: manifest unknown" >> "$LOG" && return 1 ;;
    esac
  }
  nokeep
)
[ "$(get openmower)" = "rolled_back unknown" ] && [ "$(id om)" = sha256:om ] && [ "$(cat /fake/c/om/ref)" = r/om:edge ] && [ -z "$(get nokeep_openmower)" ] &&
  [ "$(get planner_base_id)" = sha256:om ] || bad "nokeep: a version its registry doesn't have: $(get openmower), runs $(id om)"

# the new version doesn't run: the one before back from its registry
nk_fresh
echo sha256:new > /fake/nostart
nokeep
[ "$(get openmower)" = rolled_back ] && [ "$(id om)" = sha256:om ] && [ "$(cat /fake/c/om/ref)" = r/om:edge ] || bad "nokeep: not back: $(get openmower), runs $(id om)"
[ "$(get openmower_failed)" = "sha256:new sha256:dnew" ] && called '^pull r/om@sha256:dom' && ! grep -q '^sha256:new ' /fake/layers ||
  bad "nokeep: left out $(get openmower_failed), the new one $(grep '^sha256:new' /fake/layers)"
[ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(get planner_base_id)" = sha256:om ] && [ -z "$(get nokeep_openmower)$(get gone_planner)" ] ||
  bad "nokeep: the planner not on the one before: $(get planner)"
# and its download fails too: missing, the one before is what comes
nk_fresh
echo sha256:new > /fake/nostart
(
  pull_image() {
    case $1 in *@*) return 1 ;; esac
    sed -i "\\|^$1 |d" /fake/refs
    echo "$1 sha256:new r/om@sha256:dnew" >> /fake/refs
    echo "sha256:new l1 n2 n3" >> /fake/layers
  }
  nokeep
)
[ "$(get openmower)" = "error missing" ] && [ "$(get openmower_missing | cut -d' ' -f3-)" = "back r/om:edge r/om@sha256:dom r/om:edge /stk" ] && [ ! -e /fake/c/om ] ||
  bad "nokeep: the one before not downloaded: $(get openmower), $(get openmower_missing)"
WHY=again MANUAL='' update_openmower
[ "$(get openmower)" = rolled_back ] && [ "$(id om)" = sha256:om ] && [ "$(id pl | cut -c1-8)" = sha256:b ] || bad "nokeep: the one before on its next try: $(get openmower)"

# stopped halfway, after the new version started
nk_fresh
(
  seen() { exit 9; }
  nokeep
)
status result running
recover
[ -n "$(get nokeep_openmower)" ] && grep -q '^VERSION="edge"$' /stk/.env || bad "nokeep: recover undid it: $(get nokeep_openmower)"
WHY=start MANUAL='' update_openmower
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(id om)" = sha256:new ] && [ "$(get planner | cut -d' ' -f1)" = updated ] ||
  bad "nokeep: not on after a stop halfway: $(get openmower), $(get planner)"
# and the new version doesn't run, the mower out at the start: looked at again later, not in the dock's way
nk_fresh
(
  seen() { exit 9; }
  nokeep
)
echo sha256:new > /fake/nostart
echo "0 MOWING" > /fake/mower
run start openmower
[ "$(get openmower)" = unconfirmed ] && [ "$(get nokeep_openmower | cut -d' ' -f1)" = new ] && [ -z "$(get openmower_missing)" ] && [ -n "$nk_next" ] && ! nokeep_due ||
  bad "nokeep: a stop halfway with the mower out: $(get openmower), $(get nokeep_openmower), next $nk_next"
echo 1 > /fake/mower
echo "$nk_next" > /fake/now
nokeep_due || bad "nokeep: its next look not due"
run again openmower
[ "$(get openmower)" = rolled_back ] && [ "$(id om)" = sha256:om ] && [ -z "$(get nokeep_openmower)" ] && [ "$(get planner_base_id)" = sha256:om ] ||
  bad "nokeep: not back after a stop halfway: $(get openmower), runs $(id om)"

# the mower out of the dock once OpenMower runs: the planner built before it starts is seen all the same, a stopped one
# waits for the dock, then it's made
nk_fresh
(
  restart() { echo "0 IDLE" > /fake/mower; compose 1 "$(box "$1")" up -d svc && seen "$1" "$2"; }
  nokeep
)
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(cat /fake/c/pl/status)" = running ] ||
  bad "nokeep: the planner with the mower out: $(get planner)"
nk_fresh
echo exited > /fake/c/pl/status
(
  restart() { echo "0 IDLE" > /fake/mower; compose 1 "$(box "$1")" up -d svc && seen "$1" "$2"; }
  nokeep
)
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(get planner)" = "error gone_dock" ] && [ ! -e /fake/c/pl ] && [ "$(gone_due)" = "planner " ] ||
  bad "nokeep: the stopped planner waiting for the dock: $(get planner), due $(gone_due)"
echo 1 > /fake/mower
run again planner
[ "$(get planner)" = stopped ] && [ "$(cat /fake/c/pl/status)" = created ] && [ -z "$(get gone_planner)$(gone_due)" ] ||
  bad "nokeep: the stopped planner not made in the dock: $(get planner)"

# a build that fails stays missing, its button builds it
nk_fresh
: > /fake/build_fail
nokeep
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(get planner)" = "error gone" ] && [ ! -e /fake/c/pl ] && [ -n "$(get gone_planner)" ] &&
  [ -z "$(gone_due)" ] || bad "nokeep: a build that failed: $(get planner), due $(gone_due)"
rm /fake/build_fail
: > /fake/nostart_planner
update_build planner
[ "$(get planner)" = "error gone" ] && [ ! -e /fake/c/pl ] && [ -n "$(get gone_planner)" ] || bad "nokeep: a build that doesn't run isn't removed again: $(get planner)"
rm /fake/nostart_planner
update_build planner
[ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(cat /fake/c/pl/status)" = running ] && [ -z "$(get gone_planner)" ] || bad "nokeep: its button didn't build it: $(get planner)"

# --- OM_PLANNER=external: OpenMower and the planner wait for each other ---
# both built, started and seen, the planner built and started before OpenMower and seen after it
nk_fresh
: > /fake/external
nokeep
[ "$(get openmower | cut -d' ' -f1,3)" = "updated edge" ] && [ "$(id om)" = sha256:new ] && [ "$(get planner | cut -d' ' -f1,3)" = "updated v1.0.0" ] &&
  [ "$(id pl)" = sha256:b1 ] && [ "$(get planner_base_id)" = sha256:new ] && [ "$(mower)" = 1 ] ||
  bad "external: not updated: $(get openmower), $(get planner), runs $(id om) $(id pl)"
! grep -q '^gone_\|^nokeep_\|^openmower_missing\|^openmower_fw_check' /st/status && ! grep -q 'sha256:pl \|sha256:pl0\|sha256:om ' /fake/layers ||
  bad "external: notes or the old layers left: $(grep '^gone_\|^nokeep_' /st/status), $(cut -d' ' -f1 /fake/layers | tr '\n' ' ')"
[ "$(first 'compose pl .* build svc')" -lt "$(first 'compose pl up -d')" ] && [ "$(first 'compose pl up -d')" -lt "$(first '^restart openmower')" ] &&
  [ "$(first '^seen openmower')" -lt "$(first '^seen planner')" ] && [ "$(grep -c 'compose pl .* build svc' /fake/calls)" = 1 ] ||
  bad "external: not in its order: $(grep '^compose\|^restart\|^seen' /fake/calls | tr '\n' '|')"
# the new version doesn't run: the planner built on it goes with it, built again on the one before
nk_fresh
: > /fake/external
echo sha256:new > /fake/nostart
nokeep
[ "$(get openmower)" = rolled_back ] && [ "$(id om)" = sha256:om ] && [ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(id pl)" = sha256:b2 ] &&
  [ "$(get planner_base_id)" = sha256:om ] && [ -z "$(get nokeep_openmower)$(get gone_planner)" ] ||
  bad "external: not back: $(get openmower), $(get planner), runs $(id om) $(id pl)"
! grep -q '^sha256:b1 \|^sha256:new ' /fake/layers && [ "$(get openmower_failed)" = "sha256:new sha256:dnew" ] ||
  bad "external: the new version or the planner built on it left: $(cut -d' ' -f1 /fake/layers | tr '\n' ' ')"
# the planner can't be built: OpenMower not seen without it, no way back, looked at again with the planner built then
nk_fresh
: > /fake/external
: > /fake/build_fail
nokeep
[ "$(get openmower)" = unconfirmed ] && [ "$(id om)" = sha256:new ] && [ "$(get planner)" = "error gone" ] && [ ! -e /fake/c/pl ] &&
  [ "$(get nokeep_openmower | cut -d' ' -f1)" = new ] && [ -z "$(get openmower_failed)" ] && ! called '^pull r/om@' && [ -n "$nk_next" ] ||
  bad "external: a planner that can't be built: $(get openmower), $(get planner), $(get nokeep_openmower)"
[ "$(mower)" = "0 unknown" ] && still && [ "$(gate planner)" = still ] || bad "external: not still without the planner: $(mower)"
rm /fake/build_fail
echo "$nk_next" > /fake/now
nokeep_due || bad "external: its next look not due"
run again openmower
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(id om)" = sha256:new ] && [ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(id pl)" = sha256:b1 ] &&
  ! grep -q '^gone_\|^nokeep_' /st/status || bad "external: not done on its next look: $(get openmower), $(get planner)"
# stuck as before: OpenMower runs on the version before, the planner gone and nothing answers. built then, not while the
# mower mows or is idle out of the dock
nk_fresh
: > /fake/external
gone_note planner "$C1 v1.0.0 release"
rm -rf /fake/c/pl
outcome planner error not_docked
[ "$(mower)" = "0 unknown" ] && [ "$(gone_due)" = "planner " ] && still || bad "external: stuck: $(mower), due $(gone_due)"
outcome planner error gone
[ "$(gone_due)" = "planner " ] || bad "external: one that failed not due without an answer"
rm /fake/external
for m in 1 "0 MOWING" "0 IDLE"; do
  echo "$m" > /fake/mower
  [ -z "$(gone_due)" ] || bad "external: one that failed due with OpenMower at $m"
done
outcome planner error not_docked
for m in "0 MOWING" "0 IDLE"; do
  echo "$m" > /fake/mower
  ! still || bad "external: still at $m"
  run again planner
  [ ! -e /fake/c/pl ] && ! called 'compose pl .* build svc' || bad "external: built at $m: $(get planner)"
done
: > /fake/external
run again planner
[ "$(get planner | cut -d' ' -f1)" = updated ] && [ "$(cat /fake/c/pl/status)" = running ] && [ -z "$(get gone_planner)$(gone_due)" ] && [ "$(mower)" = "0 IDLE" ] ||
  bad "external: not built while OpenMower doesn't answer: $(get planner)"
fi

if [ "$only" = all ] || [ "$only" = os ]; then
# --- MowBite OS instead of OpenMower ---
# (OpenMower om r/om:edge of 5.8 GB with its broker omq in its stack, the planner pl built on it, MowBite mb. the OS's
# image r/os:t1 of 230 MB packed, its stack's files in /fake/osimg, its compose as a function: config says the targets
# in /fake/os_targets, up makes mowbite-os and mowbite-mosquitto. the broker answers while a mosquitto runs, robot_state
# is /fake/state, the clock goes on 5 s each look)
PLANNER=pl
PRUNE=0
OS_REPO=r/os
C1=1111111111111111111111111111111111111111
mkdir -p /stacks /fake/osimg
printf 'name: mbt-os\nservices: {}\n' > /fake/osimg/nx60i.compose.yaml
echo 'listener 1883' > /fake/osimg/mosquitto.conf
printf 'MOWBITE_OS_TAG=\nMOWBITE_DATUM_LAT=\nTZ=Europe/Berlin\nMOWBITE_DATA_DIR=/d/os\nMOWBITE_JOURNAL_DIR=/d/journal\n' > /fake/osimg/env.example
OS_REFS='r/om:edge sha256:om r/om@sha256:dom
r/pl:edge sha256:pl -
eclipse-mosquitto:2 sha256:mq -
eclipse-mosquitto:2.0.22 sha256:mq2 -
r/mowbite:latest sha256:mb r/mowbite@sha256:dmb'
TARGETS='      - type: bind
        target: /import/openmower/ros
        read_only: true
      - type: bind
        target: /import/openmower/params
        read_only: true
      - type: bind
        target: /export'
os_fresh() {
  fresh
  rm -rf /fake/c/pl /fake/c/omq /fake/c/mowbite-os /fake/c/mowbite-mosquitto /stacks/* /fake/os_* /fake/up_fail /fake/pull_fail \
    /fake/reg_gone /fake/reg_down /fake/no_info /fake/foreign /fake/stop_fail /fake/om_nostart /fake/state /fake/sizes /fake/export \
    /fake/external /fake/nostart* /fake/build_fail /fake/gh_down /fake/no_ids /fake/rm_fail_* /fake/no_list /fake/fw_blocked \
    /fake/drain /fake/fw_late
  printf '%s\nr/os:t1 sha256:os -\n' "$OS_REFS" > /fake/refs
  printf 'sha256:om l1 l2 l3\nsha256:pl l1 l2 l3 p1\nsha256:mq q1\nsha256:mq2 q2\nsha256:mb m1\nsha256:os o1\n' > /fake/layers
  box_at pl sha256:pl r/pl:edge
  box_at omq sha256:mq eclipse-mosquitto:2
  for c in om omq pl mb; do echo unless-stopped > "/fake/c/$c/policy"; done
  echo proj > /fake/c/om/project
  echo proj > /fake/c/omq/project
  printf '%s\n' "$TARGETS" > /fake/os_targets
  printf 'll/services/gps/datum_lat 53.1\nll/services/gps/datum_long "9.2"\nbackup x\n' > /fake/datum
  echo '{"current_state":"IDLE","is_charging":1,"emergency_reason":0,"battery_percentage":0.8}' > /fake/state
  echo 1 > /fake/os_fw
  echo 5000 > /fake/free
  echo 0 > /fake/up
  echo "os t1" > "$CONF"
  status parts openmower:om:openmower planner:pl:build mowbite:mb:image
  check_room
  : > /fake/calls
  held=
  rebuilt=
  WHY=request MANUAL=1
}
# (the OS's image not here: in its registry only)
os_away() {
  sed -i '/^r\/os:t1 /d' /fake/refs
  sed -i '/^sha256:os /d' /fake/layers
}
# the firmware major from the OS image's labels, here or in its registry
fw_json='{"a":"b","mowbite.xcore.firmware.major":"1","z":"2"}'
(
  timeout() {
    shift
    "$@"
  }
  # (an image for one platform only: no list to pick from)
  # shellcheck disable=SC2032
  docker() { case $* in *linux/*) return 1 ;; *) echo "$fw_json" ;; esac; }
  id_of() { :; }
  [ "$(os_fw_major x)" = 1 ] || bad "os: the firmware major not read from the image's labels: $(os_fw_major x)"
  id_of() { return 1; }
  fw_json='{"mowbite.xcore.firmware.major":"2"}'
  [ "$(os_fw_major x)" = 2 ] || bad "os: the firmware major not read from its registry: $(os_fw_major x)"
  id_of() { :; }
  for fw_json in '{"mowbite.xcore.firmware.major":""}' null '{"mowbite.xcore.firmware.minor":"1"}' '{"mowbite.xcore.firmware.major":"1a"}'; do
    [ -z "$(os_fw_major x)" ] || bad "os: a firmware major from $fw_json: $(os_fw_major x)"
  done
  exit "$fails"
) || fails=$?
stacks_root() { echo /stacks; }
find_parts() { :; }
fw_blocked() { if [ -e /fake/fw_blocked ]; then return 0; fi; return 1; }
os_fw_major() { cat /fake/os_fw; }
free_mb() { cat /fake/free; }
check_room() { { echo "cache 0"; cat /fake/os_room 2> /dev/null; } > "$STATE/room"; }
in_registry() { [ -e /fake/reg_down ] && return 2; ! grep -qxF "$1" /fake/reg_gone 2> /dev/null; }
layers() { printf 'aaaaaaaaaaaa 241172480\n'; }
base_of() { [ "$1" = pl ] && echo r/om:edge; }
want_of() { echo "$C1 v1.0.0 release"; }
calib_run() { [ "$1" = read ] && cat /fake/datum; }
os_kept() { [ -e /fake/os_kept ]; }
os_info() { [ ! -e /fake/no_info ]; }
os_rpc() { [ "$1" = setup.get ] && cat /fake/os_setup 2> /dev/null; }
sleep() { :; }
# (docker here is partly a function)
timeout() {
  shift
  "$@"
}
up() { n=$(($(cat /fake/up) + 5)) && echo "$n" > /fake/up && echo "$n"; }
with_progress() {
  shift 2
  "$@"
}
pull_image() {
  echo "pull $1" >> /fake/calls
  [ ! -e /fake/drain ] || echo '{"current_state":"IDLE","is_charging":1,"emergency_reason":0,"battery_percentage":0.3}' > /fake/state
  [ ! -e /fake/fw_late ] || : > /fake/fw_blocked
  case $1 in
  *@*) echo "$1 sha256:om $1" >> /fake/refs && echo "sha256:om l1 l2 l3" >> /fake/layers ;;
  *) [ ! -e /fake/pull_fail ] && echo "$1 sha256:os -" >> /fake/refs && echo "sha256:os o1" >> /fake/layers ;;
  esac
}
mqtt() {
  case $1 in
  robot_state/json) [ -s /fake/state ] && cat /fake/state && return 0; return 27 ;;
  *) for c in omq mowbite-mosquitto; do running "$c" && return 27; done; [ -e /fake/foreign ] && return 27; return 1 ;;
  esac
}
seen() {
  echo "seen $1 $2" >> /fake/calls
  [ ! -e /fake/om_nostart ] && [ ! -e "/fake/nostart_$1" ] && running "$(box "$1")"
}
start_part() { echo "start $1" >> /fake/calls; echo running > "/fake/c/$(box "$1")/status"; }
build_image() {
  echo "build $1" >> /fake/calls
  box_at pl sha256:pl r/pl:edge
  echo created > /fake/c/pl/status
}
build_done() { :; }
# (a stack's rm and up of a service on files)
compose() {
  local c="$2"
  shift 2
  echo "compose $c $*" >> /fake/calls
  case " $* " in
  *" rm "*) rm -rf "/fake/c/$c" ;;
  *" up "*)
    box_at "$c" "$(id_of "$(ref_of "$c")")" "$(ref_of "$c")"
    echo created > "/fake/c/$c/status"
    echo unless-stopped > "/fake/c/$c/policy"
    echo proj > "/fake/c/$c/project"
    printf 'bind|/vol/params|/data/params|true\nbind|/vol/ros|/data/ros|true\n' > "/fake/c/$c/mounts"
    ;;
  esac
}
os_compose() {
  local dir="$2" c
  shift 2
  echo "os_compose $dir $*" >> /fake/calls
  case " $* " in
  *" config --images "*) printf 'r/os:t1\neclipse-mosquitto:2.0.22\n' ;;
  *" config "*) [ -s "$dir/compose.yaml" ] && [ -s "$dir/.env" ] && sed -n 1p "$dir/compose.yaml" && cat /fake/os_targets ;;
  *" up "*)
    [ ! -e /fake/up_fail ] || return 1
    box_at mowbite-os sha256:os r/os:t1
    box_at mowbite-mosquitto sha256:mq2 eclipse-mosquitto:2.0.22
    for c in mowbite-os mowbite-mosquitto; do echo mbt-os > "/fake/c/$c/project"; echo "${c#mowbite-}" > "/fake/c/$c/service"; : > "/fake/c/$c/osl"; done
    echo os > /fake/c/mowbite-os/service
    ;;
  *" stop "*) for c in mowbite-os mowbite-mosquitto; do [ ! -d "/fake/c/$c" ] || echo exited > "/fake/c/$c/status"; done ;;
  esac
}
# docker for the OS's steps: filters by the files project, service and osl, restart policies, health, logs, the
# stack's files out of the image, the export. the rest as before (xargs runs the script)
# shellcheck disable=SC2032
docker() {
  local c a p='' s='' q='' o='' img=''
  case $1 in
  ps)
    shift
    for a; do
      case $a in
      label=com.docker.compose.project=*) p=${a#*=} p=${p#*=} ;;
      label=com.docker.compose.service=*) s=${a#*=} s=${s#*=} ;;
      label=mowbite.os) o=1 ;;
      -q) q=1 ;;
      esac
    done
    for c in /fake/c/*; do
      c=${c##*/}
      [ -z "$p" ] || [ "$(cat "/fake/c/$c/project" 2> /dev/null)" = "$p" ] || continue
      [ -z "$s" ] || [ "$(cat "/fake/c/$c/service" 2> /dev/null)" = "$s" ] || continue
      [ -z "$o" ] || [ -e "/fake/c/$c/osl" ] || continue
      [ -z "$q" ] || running "$c" || continue
      echo "$c"
    done
    ;;
  inspect)
    case $3 in
    *RestartPolicy*) cat "/fake/c/$4/policy" ;;
    *Health.Status*) cat /fake/os_health 2> /dev/null || echo healthy ;;
    *Health.Log*) cat /fake/os_healthlog 2> /dev/null ;;
    *) command docker "$@" ;;
    esac
    ;;
  logs) cat /fake/os_log 2> /dev/null ;;
  update) [ -d "/fake/c/$3" ] && echo "${2#--restart=}" > "/fake/c/$3/policy" && echo "update $2 $3" >> /fake/calls ;;
  stop) echo "stop $2" >> /fake/calls; [ ! -e /fake/stop_fail ] && echo exited > "/fake/c/$2/status" ;;
  start) echo "start $2" >> /fake/calls; echo running > "/fake/c/$2/status" ;;
  exec)
    echo "exec $*" >> /fake/calls
    read -r a < /fake/export
    [ "$a" = 0 ] && cat /fake/os_map > /stacks/mowbite-os/export/map.json && cat /fake/os_report > /stacks/mowbite-os/export/report.json
    return "$a"
    ;;
  run)
    for a; do [ "$a" = cat ] && img=1; done
    if [ -n "$img" ]; then
      for a; do :; done
      cat "/fake/osimg/${a##*/}" 2> /dev/null
    else
      command docker "$@"
    fi
    ;;
  *) command docker "$@" ;;
  esac
}
policies() { for c in om omq pl mb; do printf '%s:%s:%s ' "$c" "$(cat "/fake/c/$c/policy" 2> /dev/null)" "$(cat "/fake/c/$c/status" 2> /dev/null)"; done; }
on_om() { [ "$(policies)" = "om:unless-stopped:running omq:unless-stopped:running pl:unless-stopped:running mb:unless-stopped:running " ]; }
no_notes() { ! grep -qE '^(switch_os|os_ran|os_drop|os_image|os_env|os_data|os_safety|gone_[a-z_]*) ' /st/status; }
first() { grep -n -- "$1" /fake/calls | head -n1 | cut -d: -f1; }
last() { grep -n -- "$1" /fake/calls | tail -n1 | cut -d: -f1; }

# offered: the image here, from its registry next to OpenMower, with OpenMower deleted first, and not
os_fresh
rm "$CONF"
os_look
[ -z "$(get os_switch)" ] || bad "os: offered without its image set: $(get os_switch)"
os_fresh
os_look
[ "$(get os_switch)" = "yes 0 keep import" ] || bad "os: not offered with its image here: $(get os_switch)"
: > /fake/os_kept
os_look
[ "$(get os_switch)" = "yes 0 keep kept" ] || bad "os: data_dir with the OS's data not said: $(get os_switch)"
os_fresh
os_away
echo 3000 > /fake/free
os_look
[ "$(get os_switch)" = "yes 230 keep import" ] || bad "os: not offered from its registry: $(get os_switch)"
echo 1000 > /fake/free
echo "img 0123456789ab 1258291200 - dangling" > /fake/os_room
check_room
os_look
[ "$(get os_switch)" = "yes 230 keep import" ] || bad "os: what nothing needs not counted: $(get os_switch)"
rm /fake/os_room
check_room
os_look
[ "$(get os_switch)" = "no room 2174 1000" ] || bad "os: room with OpenMower's image counted that isn't: $(get os_switch)"
echo 'sha256:om 5.8GB' > /fake/sizes
os_look
[ "$(get os_switch)" = "yes 230 drop import" ] || bad "os: not offered with OpenMower deleted first: $(get os_switch)"
echo r/om@sha256:dom > /fake/reg_gone
os_look
[ "$(get os_switch)" = "no prev" ] || bad "os: OpenMower deleted though its registry hasn't it: $(get os_switch)"
for w in datum data registry image import writable files openmower pending stack; do
  os_fresh
  case $w in
  datum) echo 'll/services/gps/datum_long 9.2' > /fake/datum ;;
  data) printf 'volume|params|/data/params|true\nbind|/vol/ros|/data/ros|true\n' > /fake/c/om/mounts ;;
  registry) os_away && : > /fake/reg_down ;;
  image) os_away && echo r/os:t1 > /fake/reg_gone ;;
  import) sed -i '/export/d' /fake/os_targets ;;
  writable) sed -i '3d' /fake/os_targets ;;
  files) rm /fake/osimg/mosquitto.conf ;;
  openmower) echo exited > /fake/c/om/status ;;
  pending) status pending_mowbite x ;;
  stack) mkdir /stacks/mowbite-os ;;
  esac
  os_look
  case $w in writable) w=import ;; esac
  [ "$(get os_switch)" = "no $w" ] || bad "os: $w not said: $(get os_switch)"
  echo 'listener 1883' > /fake/osimg/mosquitto.conf
done
# the stack's .env made anew from the image's env.example, what was changed in it by hand kept, the updater's own not
os_fresh
mkdir -p /stacks/mowbite-os
printf 'MOWBITE_OS_TAG=\nTZ=Europe/Berlin\nMOWBITE_DATA_DIR=/d/old\nMOWBITE_JOURNAL_DIR=/d/journal\n' > /stacks/mowbite-os/env.example
printf 'MOWBITE_OS_TAG=t0\r\nTZ=Europe/Paris\r\nMOWBITE_DATA_DIR=/d/mine\r\nMOWBITE_JOURNAL_DIR=/d/journal\r\nEXTRA=1\r\nMOWBITE_IMPORT_ROS=/x\r\n' > /stacks/mowbite-os/.env
sed -i 's|^MOWBITE_JOURNAL_DIR=.*|MOWBITE_JOURNAL_DIR=/d/j2|' /fake/osimg/env.example
status os_stack mbt-os
os_files r/os:t1 /tmp/os.env "53.1 9.2 0 /vol/ros /vol/params"
[ "$(sort /tmp/os.env/.env | tr '\n' ' ')" = "EXTRA=1 MOWBITE_DATA_DIR=/d/mine MOWBITE_DATUM_HEIGHT=0 MOWBITE_DATUM_LAT=53.1 MOWBITE_DATUM_LONG=9.2 MOWBITE_IMPORT_PARAMS=/vol/params MOWBITE_IMPORT_ROS=/vol/ros MOWBITE_JOURNAL_DIR=/d/j2 MOWBITE_OS_TAG=t1 TZ=Europe/Paris " ] ||
  bad "os: the .env from before not kept as it should: $(sort /tmp/os.env/.env | tr '\n' ' ')"
(
  os_kept() { [ "$1" = /d/mine ]; }
  os_look
)
[ "$(get os_switch)" = "yes 0 keep kept" ] || bad "os: the data_dir set by hand not looked at: $(get os_switch)"
rm -rf /tmp/os.env /stacks/mowbite-os
status os_stack
sed -i 's|^MOWBITE_JOURNAL_DIR=.*|MOWBITE_JOURNAL_DIR=/d/journal|' /fake/osimg/env.example
# the CGI only what's offered
cp /r/www/cgi-bin/updater /fake/cgi
cgi() { REQUEST_METHOD=POST CONTENT_TYPE=application/json QUERY_STRING=$1 sh /fake/cgi > /dev/null 2>&1; }
os_fresh
rm -f "$REQ"
cgi switch=os
cgi switch=openmower
[ ! -s "$REQ" ] || bad "os: asked for without an offer: $(cat "$REQ")"
status os_switch yes 0 keep import
cgi switch=os
cgi switch=openmower
[ "$(cat "$REQ")" = "switch os" ] || bad "os: the way there not asked for: $(cat "$REQ")"
rm -f "$REQ"
status os_switch on 1
cgi switch=os
cgi switch=openmower
[ "$(cat "$REQ")" = "switch openmower" ] || bad "os: the way back not asked for: $(cat "$REQ")"
rm -f "$REQ"

# the way there: kept, pulled, stopped (the brokers last), the stack made, seen
os_fresh
os_away
alone os os_switch os
[ "$(get os | cut -d' ' -f1,3)" = "switched import" ] && [ "$(get os_switch | cut -d' ' -f1)" = on ] || bad "os: not switched: $(get os), $(get os_switch)"
[ "$(policies)" = "om:no:exited omq:no:exited pl:no:exited mb:no:exited " ] || bad "os: OpenMower's world not stopped: $(policies)"
[ "$(get os_ran)" = "om:unless-stopped:running omq:unless-stopped:running pl:unless-stopped:running mb:unless-stopped:running" ] || bad "os: not noted: $(get os_ran)"
running mowbite-os && running mowbite-mosquitto && [ "$(get os_stack)" = mbt-os ] || bad "os: its stack not started"
called 'os_compose.* up .*--force-recreate' || bad "os: its containers not made anew, an old halt would count"
[ "$(first '^pull r/os:t1')" -lt "$(first '^stop')" ] && [ "$(last '^stop om$')" -lt "$(first '^stop omq')" ] && [ "$(first '^stop omq')" -lt "$(first 'os_compose.* up ')" ] ||
  bad "os: not in its order: $(grep '^pull\|^stop\|up -d' /fake/calls | tr '\n' '|')"
grep -qx 'MOWBITE_OS_TAG=t1' /stacks/mowbite-os/.env && grep -qx 'MOWBITE_DATUM_LAT=53.1' /stacks/mowbite-os/.env && grep -qx 'MOWBITE_DATUM_LONG=9.2' /stacks/mowbite-os/.env &&
  grep -qx 'MOWBITE_DATUM_HEIGHT=0' /stacks/mowbite-os/.env && grep -qx 'MOWBITE_IMPORT_ROS=/vol/ros' /stacks/mowbite-os/.env && grep -qx 'MOWBITE_IMPORT_PARAMS=/vol/params' /stacks/mowbite-os/.env &&
  grep -qx 'MOWBITE_DATA_DIR=/d/os' /stacks/mowbite-os/.env && [ -s /stacks/mowbite-os/compose.yaml ] && [ -d /stacks/mowbite-os/export ] ||
  bad "os: its stack's files: $(tr '\n' ' ' < /stacks/mowbite-os/.env)"
[ -n "$(data_dirs openmower update)" ] && [ "$(get os_data)" = "$(data_dirs openmower update | head -n1)" ] || bad "os: OpenMower's data not kept"
[ "$(grep -c '^hold' /fake/calls)" = 1 ] && [ "$(first '^hold')" -lt "$(first '^stop')" ] || bad "os: held other than once before the stop"
# meanwhile OpenMower and what stopped with it are left alone
: > /fake/calls
run request openmower mowbite planner
[ "$(get openmower)" = "error os" ] && [ "$(get mowbite)" = "error os" ] && [ "$(get planner)" = "error os" ] && ! called '^start\|^restart\|^pull\|^compose' ||
  bad "os: a part updated next to the OS: $(get openmower), $(get mowbite), $(get planner)"
[ -z "$(gone_due)" ] || bad "os: a build due next to the OS"
(
  os_ref() { return 1; }
  os_look
)
[ "$(get os_switch | cut -d' ' -f1)" = on ] || bad "os: its setting gone on the OS took the way back: $(get os_switch)"
# a safety check of its setup failed: said for the way back's warning, as long as it stands
echo '{"jsonrpc":"2.0","result":{"step":null,"safety":{"open":false,"why":"CHECK_FAILED"}},"id":"x"}' > /fake/os_setup
os_look
[ "$(get os_safety)" = check_failed ] || bad "os: a failed check of its setup not said: $(get os_safety)"
echo '{"jsonrpc":"2.0","result":{"step":null,"safety":{"open":true,"why":null}},"id":"x"}' > /fake/os_setup
os_look
[ -z "$(get os_safety)" ] || bad "os: a failed check said after it passed: $(get os_safety)"
echo '{"jsonrpc":"2.0","result":{"safety":{"open":false,"why":"CHECK_FAILED"}},"id":"x"}' > /fake/os_setup
os_look
# back: the OS's map into OpenMower's map.json with its owner and rights, OpenMower's world as it was
cp -p /st/status /fake/on_os
cp -rp /stacks /fake/on_os_stacks
chown 1000:1001 /vol/ros/map.json
chmod 640 /vol/ros/map.json
echo 0 > /fake/export
echo '{"areas":["os"]}' > /fake/os_map
echo '{"lost": []}' > /fake/os_report
: > /fake/calls
alone os os_switch openmower
[ "$(get os | cut -d' ' -f1,3-)" = "back map" ] && on_om && no_notes || bad "os: not back: $(get os), $(policies)"
[ "$(cat /vol/ros/map.json)" = '{"areas":["os"]}' ] && [ "$(stat -c %u:%g:%a /vol/ros/map.json)" = 1000:1001:640 ] || bad "os: the map not taken: $(cat /vol/ros/map.json), $(stat -c %u:%g:%a /vol/ros/map.json)"
! running mowbite-os && ! running mowbite-mosquitto && [ "$(get os_stack)" = mbt-os ] || bad "os: the OS not stopped"
[ "$(first '^start omq')" -lt "$(first '^start om$')" ] && [ "$(first '^hold')" -lt "$(first '^start om$')" ] || bad "os: OpenMower before its broker or unheld"
[ "$(data_dirs openmower | wc -l)" -ge 2 ] || bad "os: what OpenMower had not kept before the map came"
# lost, busy, an export that fails
for w in lost busy failed gone out; do
  cp -p /fake/on_os /st/status
  rm -rf /stacks && cp -rp /fake/on_os_stacks /stacks
  for c in om omq pl mb; do echo no > "/fake/c/$c/policy"; echo exited > "/fake/c/$c/status"; done
  for c in mowbite-os mowbite-mosquitto; do echo running > "/fake/c/$c/status"; done
  echo '{"areas":["front"]}' > /vol/ros/map.json
  echo '{"lost": [{"kind": "drawn"}]}' > /fake/os_report
  case $w in
  lost) echo 0 > /fake/export ;;
  busy) echo 2 > /fake/export ;;
  failed) echo 1 > /fake/export ;;
  gone) echo exited > /fake/c/mowbite-os/status && echo "0 unknown" > /fake/mower ;;
  out) echo "0 MOWING" > /fake/mower ;;
  esac
  alone os os_switch openmower
  echo 1 > /fake/mower
  case $w in
  lost) [ "$(get os | cut -d' ' -f1,3-)" = "back map lost" ] && on_om || bad "os: lost not said: $(get os)" ;;
  out) [ "$(get os)" = "error not_docked" ] && running mowbite-os && [ -z "$(get switch_os)" ] || bad "os: back while it drives: $(get os)" ;;
  busy) [ "$(get os)" = "error busy" ] && running mowbite-os && [ -n "$(get os_ran)" ] && [ -z "$(get switch_os)" ] || bad "os: busy, but: $(get os)" ;;
  *)
    [ "$(get os | cut -d' ' -f1,3-)" = "back old" ] && on_om && [ "$(cat /vol/ros/map.json)" = '{"areas":["front"]}' ] ||
      bad "os: export $w, but: $(get os), $(cat /vol/ros/map.json)"
    ;;
  esac
done
# OpenMower that doesn't come back: noted, a tap goes on
cp -p /fake/on_os /st/status
for c in om omq pl mb; do echo no > "/fake/c/$c/policy"; echo exited > "/fake/c/$c/status"; done
echo 1 > /fake/export
: > /fake/om_nostart
alone os os_switch openmower
[ "$(get os)" = "error back" ] && [ "$(get switch_os)" = "openmower start old" ] || bad "os: OpenMower not back, but: $(get os), $(get switch_os)"
rm /fake/om_nostart
alone os os_switch openmower
[ "$(get os | cut -d' ' -f1,3-)" = "back old" ] && on_om && no_notes || bad "os: the tap after didn't go on: $(get os)"

# the way there given up: the OS not as it should, its pull, a broker that stays, the dock, the schedule
for w in health halt info emergency calm pull up broker not_docked schedule stop; do
  os_fresh
  case $w in
  health) echo unhealthy > /fake/os_health ;;
  halt) echo 'MOWBITE_OS_HALT reason=SCHEMA_NEWER' > /fake/os_log ;;
  info) : > /fake/no_info ;;
  emergency) echo '{"current_state":"IDLE","emergency_reason":4098,"battery_percentage":0.8}' > /fake/state ;;
  calm) echo '{"current_state":"IDLE","emergency_reason":1,"battery_percentage":0.8}' > /fake/state ;;
  pull) os_away && : > /fake/pull_fail ;;
  up) : > /fake/up_fail ;;
  broker) : > /fake/foreign ;;
  not_docked) echo "0 MOWING" > /fake/mower ;;
  schedule) echo 2000 > /fake/soon ;;
  stop) : > /fake/stop_fail ;;
  esac
  alone os os_switch os
  rm -f /fake/soon /fake/stop_fail
  case $w in
  calm) [ "$(get os | cut -d' ' -f1)" = switched ] || bad "os: another bit took for one that stops it: $(get os)" ;;
  pull | not_docked | schedule)
    [ "$(get os | cut -d' ' -f1,2)" = "error $w" ] && on_om && no_notes && ! called '^stop' || bad "os: $w, but: $(get os), $(policies)"
    ;;
  broker | stop) [ "$(get os)" = "error $w" ] && on_om && no_notes || bad "os: $w, but: $(get os), $(policies)" ;;
  *)
    case $w in up) w=start ;; esac
    [ "$(get os)" = "rolled_back $w" ] && on_om && no_notes && ! running mowbite-os || bad "os: $w, but: $(get os), $(policies)"
    ;;
  esac
  echo 1 > /fake/mower
done

# the battery and the board's firmware: nothing pulled or stopped, and nothing stopped when it changes meanwhile
for w in battery nobattery half fw label nolabel drain fw_late; do
  os_fresh
  os_away
  case $w in
  battery) echo '{"current_state":"IDLE","is_charging":1,"battery_percentage":0.49}' > /fake/state ;;
  nobattery) echo '{"current_state":"IDLE","is_charging":1}' > /fake/state ;;
  half) echo '{"current_state":"IDLE","is_charging":1,"emergency_reason":0,"battery_percentage":0.5}' > /fake/state ;;
  fw) : > /fake/fw_blocked ;;
  label) echo 2 > /fake/os_fw ;;
  nolabel) : > /fake/os_fw ;;
  drain | fw_late) : > "/fake/$w" ;;
  esac
  alone os os_switch os
  case $w in
  half) [ "$(get os | cut -d' ' -f1)" = switched ] || bad "os: not switched at 50 %: $(get os)" ;;
  battery | nobattery | fw | label | nolabel)
    case $w in *battery) x="battery 50" ;; *) x=firmware ;; esac
    [ "$(get os)" = "error $x" ] && on_om && no_notes && ! called '^stop' && ! called '^pull' || bad "os: $w, but: $(get os), $(policies)"
    ;;
  *)
    case $w in drain) x="battery 50" ;; *) x=firmware ;; esac
    [ "$(get os)" = "error $x" ] && called '^pull' && on_om && no_notes && ! called '^stop' || bad "os: $w meanwhile, but: $(get os), $(policies)"
    ;;
  esac
done

# a planner built on OpenMower's version before stops with it too
os_fresh
os_away
(
  base_of() { [ "$1" = pl ] && echo r/om:before; }
  alone os os_switch os
)
[ "$(get os | cut -d' ' -f1)" = switched ] && [ "$(cat /fake/c/pl/status)" = exited ] || bad "os: a planner on OpenMower's version before left running: $(get os), $(policies)"

# given up and OpenMower not back: a tap goes on from where it got to, its broker running already
os_fresh
os_away
echo unhealthy > /fake/os_health
: > /fake/om_nostart
alone os os_switch os
rm -f /fake/om_nostart /fake/os_health
[ "$(get os)" = "error back" ] && [ "$(get switch_os)" = "openmower start old" ] && running omq && [ -z "$(get os_switch)" ] ||
  bad "os: given up, OpenMower not back, but: $(get os), $(get switch_os), offer $(get os_switch)"
alone os os_switch openmower
[ "$(get os | cut -d' ' -f1,3-)" = "back old" ] && on_om && no_notes || bad "os: the tap after a way there given up didn't go on: $(get os), $(get switch_os)"

# stopped while it went back: back on from there, not on to the OS
os_fresh
os_away
echo unhealthy > /fake/os_health
(
  os_om_up() { exit 0; }
  alone os os_switch os
)
rm -f /fake/os_health
[ "$(get switch_os)" = "os back rolled_back health" ] || bad "os: going back not noted: $(get switch_os)"
alone os os_resume
[ "$(get os)" = "rolled_back health" ] && on_om && no_notes && ! running mowbite-os || bad "os: not back on after a stop going back: $(get os), $(policies)"

# with OpenMower deleted first: its containers removed, its image and what's built on it deleted, back from its registry
os_fresh
os_away
echo 1000 > /fake/free
echo 'sha256:om 5.8GB' > /fake/sizes
alone os os_switch os
[ "$(get os | cut -d' ' -f1)" = switched ] && [ ! -d /fake/c/om ] && [ ! -d /fake/c/pl ] && ! grep -q '^sha256:om \|^sha256:pl ' /fake/layers ||
  bad "os: not switched with OpenMower deleted: $(get os), $(policies)"
[ "$(get os_drop | cut -d' ' -f1,2)" = "r/om@sha256:dom r/om:edge" ] && [ -n "$(get gone_openmower)" ] && [ -n "$(get gone_planner)" ] || bad "os: its way back not noted"
[ "$(first 'compose om .*rm')" -lt "$(first '^rmi')" ] && [ "$(first '^rmi')" -lt "$(first '^pull r/os:t1')" ] || bad "os: deleted in the wrong order"
echo 0 > /fake/export
echo '{"areas":["os"]}' > /fake/os_map
echo '{"lost": []}' > /fake/os_report
echo r/om@sha256:dom > /fake/reg_gone
alone os os_switch openmower
rm /fake/reg_gone
[ "$(get os)" = "error registry" ] && running mowbite-os && [ -z "$(get switch_os)" ] || bad "os: back without OpenMower in its registry: $(get os)"
echo 0 > /fake/export
echo '{"areas":["os"]}' > /fake/os_map
echo '{"lost": []}' > /fake/os_report
: > /fake/calls
alone os os_switch openmower
[ "$(get os | cut -d' ' -f1,3-)" = "back map" ] && running om && running pl && running omq && running mb && no_notes ||
  bad "os: not back with OpenMower from its registry: $(get os), $(policies)"
[ "$(first '^rmi r/os:t1')" -lt "$(first '^pull r/om@sha256:dom')" ] || bad "os: OpenMower downloaded next to the OS's image: $(grep '^rmi\|^pull' /fake/calls | tr '\n' '|')"
[ "$(first '^pull r/om@sha256:dom')" -lt "$(first 'compose om .*--no-start')" ] && [ "$(cat /vol/ros/map.json)" = '{"areas":["os"]}' ] ||
  bad "os: OpenMower not made again with the OS's map: $(grep '^pull\|compose' /fake/calls | tr '\n' '|')"
[ "$(first '^build pl')" -lt "$(first '^start om$')" ] || bad "os: the planner not built before OpenMower"
# OpenMower made again and not started yet: its broker answers, it doesn't (0 unknown), the planner built all the same.
# its broker not answering: not built, OpenMower not back, a tap goes on once it answers
for w in quiet mute; do
  os_fresh
  os_away
  echo 1000 > /fake/free
  echo 'sha256:om 5.8GB' > /fake/sizes
  alone os os_switch os
  echo 0 > /fake/export
  echo '{"areas":["os"]}' > /fake/os_map
  echo '{"lost": []}' > /fake/os_report
  : > /fake/calls
  [ "$w" = quiet ] || : > /fake/mute
  (
    # (OM_PLANNER=external: OpenMower up only with the planner)
    seen() {
      echo "seen $1 $2" >> /fake/calls
      running "$(box "$1")" && { [ "$1" != openmower ] || running pl; }
    }
    mower() { if running om || running mowbite-os; then cat /fake/mower; elif [ ! -e /fake/mute ] && running omq; then echo "0 unknown"; fi; }
    os_broker() { [ ! -e /fake/mute ] && running omq; }
    alone os os_switch openmower
    if [ "$w" = mute ]; then
      [ "$(get os)" = "error back" ] && ! called '^build pl' || bad "os: back with a broker that doesn't answer: $(get os), $(policies)"
      rm /fake/mute
      : > /fake/calls
      alone os os_switch openmower
    fi
  )
  [ "$(get os | cut -d' ' -f1,3-)" = "back map" ] && running om && running pl && [ "$(first '^build pl')" -lt "$(first '^start om$')" ] ||
    bad "os: $w, the planner not built on OpenMower made again: $(get os), $(policies)"
done
rm -f /fake/mute
# a planner that doesn't run on OpenMower made again: removed again, its note kept
os_fresh
os_away
echo 1000 > /fake/free
echo 'sha256:om 5.8GB' > /fake/sizes
alone os os_switch os
echo 0 > /fake/export
echo '{"areas":["os"]}' > /fake/os_map
echo '{"lost": []}' > /fake/os_report
: > /fake/nostart_planner
alone os os_switch openmower
rm -f /fake/nostart_planner
[ "$(get os | cut -d' ' -f1)" = back ] && running om && [ "$(get planner)" = "error gone" ] && [ ! -e /fake/c/pl ] && [ -n "$(get gone_planner)" ] ||
  bad "os: a planner that doesn't run after the way back: $(get os), planner $(get planner), $(policies)"
# given up before anything was deleted: the planner as it was, not taken as built again
os_fresh
os_away
echo 1000 > /fake/free
echo 'sha256:om 5.8GB' > /fake/sizes
: > /fake/stop_fail
(
  build_done() { : > /fake/built; }
  alone os os_switch os
)
rm /fake/stop_fail
[ "$(get os)" = "error stop" ] && on_om && no_notes && [ -z "$(get planner)" ] && [ ! -e /fake/built ] || bad "os: given up before the delete, but: $(get os), planner $(get planner), $(policies)"
# a pull that fails once OpenMower is deleted: OpenMower back from its registry
os_fresh
os_away
echo 1000 > /fake/free
echo 'sha256:om 5.8GB' > /fake/sizes
(
  os_clear() { : > /fake/pull_fail; }
  alone os os_switch os
)
rm -f /fake/pull_fail
[ "$(get os)" = "rolled_back pull" ] && running om && no_notes || bad "os: a pull that failed after the delete, but: $(get os), $(policies)"

# stopped halfway: before anything stopped given up, from its step on else
os_fresh
os_away
status os_image r/os:t1 - 2174 import
status switch_os os pull
alone os os_resume
[ "$(get os)" = "error interrupted" ] && on_om && no_notes || bad "os: a stop before the stop, but: $(get os)"
os_fresh
(
  os_seen() { echo exited > /fake/c/mowbite-os/status; exit 0; }
  alone os os_switch os
)
[ "$(get switch_os)" = "os wait" ] || bad "os: not left in its step: $(get switch_os)"
echo running > /fake/c/mowbite-os/status
alone os os_resume
[ "$(get os | cut -d' ' -f1)" = switched ] && [ -z "$(get switch_os)" ] || bad "os: not on from its step: $(get os)"
os_fresh
status switch_os os stop
status os_image r/os:t1 sha256:os 0 import
mkdir -p "$STATE/os.new"
echo "0 MOWING" > /fake/mower
alone os os_resume
[ "$(get os | cut -d' ' -f1)" = error ] && on_om && no_notes || bad "os: on while the mower drives: $(get os)"
fi

[ $fails = 0 ]
