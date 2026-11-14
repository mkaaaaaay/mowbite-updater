#!/bin/sh
# the updater's own steps around data and its own update, without docker, within a minute: docker is a script on files
# (fake/), the mower, the schedule's hold and a restart are functions that say what they were asked. the data kept
# (pieces, rights, the newest two and the one put back, a piece that isn't there, a full disk, a helper that fails),
# put back (checked first, kept first, nothing when it can't), what the format of the data says, going back with it,
# by hand from its page, a stop halfway, what a pull by its digest leaves, the rest of a request after its own update,
# its own update seen running and answering for 45 s or put back, and OpenMower updated without a copy (offered or not,
# done, a download that fails and its tries, a version that doesn't run, a stop halfway, a build that fails). in the
# image it's built on, nothing written here. what failed a line, 1 then. test/logic.sh data (or self, nokeep): only those
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

if [ "$only" != self ] && [ "$only" != nokeep ]; then
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

if [ "$only" != data ] && [ "$only" != nokeep ]; then
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
  rm -rf /fake/sizes /fake/c/pl /fake/c/x /fake/builds /fake/pull_fail /fake/build_fail /fake/nostart* /fake/reg_gone /fake/reg_down /fake/gh_down /fake/no_ids /fake/rm_fail_* /fake/page /fake/no_list
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
# (a new version that doesn't run: its id in nostart, or nostart_<part>)
seen() {
  fw_failed=
  echo "seen $1 $2" >> /fake/calls
  [ "$(image_of "$(box "$1")")" = "$2" ] && ! grep -qx "$2" /fake/nostart 2> /dev/null && [ ! -e "/fake/nostart_$1" ]
}
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

# the mower out of the dock once OpenMower runs: the planner waits for it, then it's built
nk_fresh
(
  restart() { echo "0 IDLE" > /fake/mower; compose 1 "$(box "$1")" up -d svc && seen "$1" "$2"; }
  nokeep
)
[ "$(get openmower | cut -d' ' -f1)" = updated ] && [ "$(get planner)" = "error gone_dock" ] && [ ! -e /fake/c/pl ] && [ "$(gone_due)" = "planner " ] ||
  bad "nokeep: the planner waiting for the dock: $(get planner), due $(gone_due)"
echo 1 > /fake/mower
run again planner
[ "$(get planner | cut -d' ' -f1)" = updated ] && [ -e /fake/c/pl ] && [ -z "$(get gone_planner)$(gone_due)" ] || bad "nokeep: the planner not built in the dock: $(get planner)"

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
fi

[ $fails = 0 ]
