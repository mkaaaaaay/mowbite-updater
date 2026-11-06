#!/bin/sh
# the updater's own steps around data and its own update, without docker, within a minute: docker is a script on files
# (fake/), the mower, the schedule's hold and a restart are functions that say what they were asked. the data kept
# (pieces, rights, the newest two and the one put back, a piece that isn't there, a full disk, a helper that fails),
# put back (checked first, kept first, nothing when it can't), what the format of the data says, going back with it,
# by hand from its page, a stop halfway, what a pull by its digest leaves, the rest of a request after its own update,
# and its own update seen running and answering for 45 s or put back. in the image it's built on, nothing written here.
# what failed a line, 1 then. test/logic.sh data (or self): only those
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
# "type|source|destination|rw"), images by ref (refs: "<ref> <id> <digest>"), a repository's rows for docker images
# (rows/<repo>), what it was asked (calls). its helpers with data.sh run here, their mounts as links
cat > /fake/bin/docker << 'EOF'
#!/bin/sh
F=/fake
echo "$*" >> $F/calls
c() { [ -d "$F/c/$1" ] || exit 1; cat "$F/c/$1/$2" 2> /dev/null; }
# (a new start each time it's asked)
start() { n=$(($(cat $F/n 2> /dev/null || echo 0) + 1)) && echo $n > $F/n && echo "s$n" > "$F/c/$1/started"; }
id_of() { awk -v r="$1" '$1 == r || $2 == r {print $2; exit}' $F/refs; }
case $1 in
inspect)
  shift
  [ "$1" = -f ] || { [ -d "$F/c/$1" ]; exit; }
  fmt=$2
  shift 2
  for n in "$@"; do
    case $fmt in
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
    *.Id*) id_of "$3" | grep . ;;
    *RepoDigests*) awk -v r="$3" '$1 == r || $2 == r {print $3; exit}' $F/refs ;;
    *.Size*) echo 1000 ;;
    esac
    ;;
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
rmi) case $2 in *@*) for f in $F/rows/*; do sed -i "\| ${2#*@} |d" "$f"; done ;; esac ;;
images) for f; do :; done; cat "$F/rows/$(echo "$f" | tr / _)" 2> /dev/null ;;
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
hold() { echo "hold $1" >> /fake/calls; [ ! -e /fake/hold_fail ]; }
unhold() { echo unhold >> /fake/calls; }
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

if [ "$only" != self ]; then
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

if [ "$only" != data ]; then
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

[ $fails = 0 ]
