#!/bin/sh
# the updater against a mower of its own on this docker: a registry, a broker with a made-up mower state, small apps in
# stacks, the updater built from this checkout. each case through its interface, the way its page and MowBite use it,
# then a look at what runs. only things named mbt-* are made here and cleared away afterwards. needs docker with compose
# and buildx, curl, python3 and the internet (github for the build and stable cases). a few minutes, two waits of two
# minutes for a version that doesn't start
set -u
cd "$(dirname "$0")/.." || exit 1
SRC=$PWD
REG=127.0.0.1:${MBT_REGISTRY_PORT:-5077}
MQTT=${MBT_MQTT_PORT:-51877}
PAGE=${MBT_PAGE_PORT:-58077}
WORK=${MBT_WORK:-$(mktemp -d /tmp/mbt.XXXXXX)}
STACKS=$WORK/stacks
API=http://127.0.0.1:$PAGE/cgi-bin/updater
fails=0

say() { printf '\n== %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
bad() {
  printf '   FAILED: %s\n' "$*"
  fails=$((fails + 1))
}

# --- the made-up mower and the updater's interface ---

# the mower as the publisher sends it every second: docked (idle, charging) or out (mowing)
mower() {
  case $1 in
  docked) echo '{"current_state":"IDLE","is_charging":true}' > "$WORK/state/robot_state.json" ;;
  out) echo '{"current_state":"MOWING","is_charging":false}' > "$WORK/state/robot_state.json" ;;
  esac
}
post() { curl -s -m 10 -X POST -H 'Content-Type: application/json' --data-binary "${2:-}" "$API?$1"; }
st() { curl -s -m 10 "$API"; }
# a value of its answer, by a python expression on d (the answer), s (its status) and c (its settings)
val() { st | python3 -c "import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
s, c = d.get('status', {}), d.get('conf', {})
v = $1
print('' if v is None else v)" 2> /dev/null; }
# until the python expression is true, within $2 seconds
until_true() {
  end=$(($(date +%s) + $2))
  while [ "$(date +%s)" -lt "$end" ]; do
    [ "$(val "bool($1)")" = True ] && return 0
    sleep 2
  done
  return 1
}
# a part's id by its container
part() { val "next((p['id'] for p in d.get('parts', []) if p['container'] == '$1'), '')"; }
runs_on() { [ "$(docker inspect -f '{{.Image}}' "$1" 2> /dev/null)" = "$(docker image inspect -f '{{.Id}}' "$2" 2> /dev/null)" ]; }
log_has() { val "any('$1' in l for l in d.get('log', []))"; }

# --- the world ---

cleanup() {
  say "clearing away"
  for f in "$STACKS"/*/compose.yaml "$WORK"/away/compose.yaml; do
    [ -f "$f" ] && docker compose -f "$f" down -t 2 > /dev/null 2>&1
  done
  docker ps -aq --filter name=mbt- | xargs -r docker rm -f > /dev/null 2>&1
  docker rm -f mowbite-updater-self > /dev/null 2>&1
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^($REG/)?mbt-" | xargs -r docker rmi -f > /dev/null 2>&1
  docker network ls -q --filter name=mbt | xargs -r docker network rm > /dev/null 2>&1
  [ -z "${MBT_WORK:-}" ] && rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

image() { # <tag> <what it does: run|crash>
  dir=$WORK/img-$1
  mkdir -p "$dir"
  if [ "$2" = crash ]; then
    printf 'FROM busybox:1.37-musl\nLABEL mbt.version=%s\nCMD ["sh", "-c", "exit 1"]\n' "$1" > "$dir/Dockerfile"
  else
    printf 'FROM busybox:1.37-musl\nLABEL mbt.version=%s\nCMD ["sleep", "100000"]\n' "$1" > "$dir/Dockerfile"
  fi
  docker build -q -t "$REG/mbt-app:$1" "$dir" > /dev/null
  docker push -q "$REG/mbt-app:$1" > /dev/null
}
# :latest in the registry moved to another tag, nothing changed here (as on a mower: only the updater pulls)
publish() { docker buildx imagetools create -t "$REG/mbt-app:latest" "$REG/mbt-app:$1" > /dev/null 2>&1; }

say "setting up in $WORK"
mkdir -p "$WORK/state" "$STACKS/updater" "$STACKS/app" "$STACKS/plain" "$STACKS/build" "$STACKS/app2" "$WORK/away"
mower docked
docker run -d --name mbt-registry -p "$REG:5000" registry:2 > /dev/null
docker run -d --name mbt-broker -p "127.0.0.1:$MQTT:1883" eclipse-mosquitto:2 mosquitto -c /mosquitto-no-auth.conf > /dev/null
docker run -d --name mbt-pub --network host -v "$WORK/state:/state:ro" eclipse-mosquitto:2 sh -c \
  "while :; do mosquitto_pub -h 127.0.0.1 -p $MQTT -t robot_state/json -f /state/robot_state.json; sleep 1; done" > /dev/null
sleep 3

docker build -q --label org.opencontainers.image.revision=a000000test -t "$REG/mbt-updater:latest" . > /dev/null || { bad "the updater doesn't build"; exit 1; }
docker push -q "$REG/mbt-updater:latest" > /dev/null
docker tag "$REG/mbt-updater:latest" "$REG/mbt-updater:a"
docker push -q "$REG/mbt-updater:a" > /dev/null
image v1 run
image v2 run
image v3 run
image v4 run
image broken crash
publish v1

cat > "$STACKS/updater/compose.yaml" << EOF
services:
  updater:
    image: $REG/mbt-updater:latest
    container_name: mbt-updater
    restart: unless-stopped
    network_mode: host
    environment:
      PORT: "$PAGE"
      MQTT_PORT: "$MQTT"
      UPDATER_CONTAINER: mbt-updater
      OPENMOWER_CONTAINER: mbt-om
      MOWBITE_CONTAINER: mbt-mowbite
      PLANNER_CONTAINER: mbt-planner
      PRUNE: "0"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $STACKS:$STACKS
EOF
cat > "$STACKS/app/compose.yaml" << EOF
services:
  app:
    image: $REG/mbt-app:latest
    container_name: mbt-app
    labels:
      mowbite.update: "on"
EOF
cat > "$STACKS/plain/compose.yaml" << EOF
services:
  plain:
    image: busybox:1.37-musl
    container_name: mbt-plain
    command: sleep 100000
EOF
# built from github with pull_policy: build, like the MowBite Planner: compose up would build it once more
cat > "$STACKS/build/compose.yaml" << EOF
services:
  build:
    build:
      context: https://github.com/mkaaaaaay/mowbite-updater.git#main
      dockerfile: Dockerfile
    image: mbt-build:edge
    pull_policy: build
    container_name: mbt-build
    labels:
      mowbite.update: "on"
EOF
# a version as its tag and a stable channel from a repository whose newest release (MowBite's) is older
cat > "$STACKS/app2/compose.yaml" << EOF
services:
  app2:
    image: $REG/mbt-app:9.9.9
    container_name: mbt-app2
    labels:
      mowbite.update: "on"
      mowbite.update.stable: github:mkaaaaaay/mowbite
EOF
docker tag "$REG/mbt-app:v2" "$REG/mbt-app:9.9.9" && docker push -q "$REG/mbt-app:9.9.9" > /dev/null
cat > "$WORK/away/compose.yaml" << EOF
services:
  away:
    image: busybox:1.37-musl
    container_name: mbt-away
    command: sleep 100000
    labels:
      mowbite.update: "on"
EOF
for s in app plain app2; do docker compose -f "$STACKS/$s/compose.yaml" up -d > /dev/null 2>&1; done
docker compose -f "$WORK/away/compose.yaml" up -d > /dev/null 2>&1
docker run -d --name mbt-loose --label mowbite.update=on busybox:1.37-musl sleep 100000 > /dev/null
docker compose -f "$STACKS/updater/compose.yaml" up -d > /dev/null 2>&1
until_true "s.get('checked')" 120 || { bad "the updater doesn't come up"; docker logs mbt-updater 2>&1 | tail -20; exit 1; }
ok "the updater runs and has looked"
APP=$(part mbt-app)

# --- the cases ---

say "interface"
[ "$(curl -s -m 10 -X POST --data-binary x "$API?check")" = bad ] && ok "a post without json is turned down" || bad "a post without json went through"
post conf 'picked x;rm -rf /,y
days 9
at 3:00' > /dev/null
[ "$(val "c.get('picked')")" = none ] && [ "$(val "c.get('days')")" = daily ] && [ "$(val "c.get('at')")" = 03:00 ] &&
  ok "settings that aren't valid are left out" || bad "settings not checked: $(val 'c')"
# (taken: away from the queue, the look itself may take its time)
t0=$(date +%s)
post check > /dev/null
until_true "not d.get('requested')" 15 && ok "a request is taken at once ($(($(date +%s) - t0)) s)" || bad "a request waited longer than 15 s"
until_true "int(s.get('checked', 0)) >= $t0" 120 || bad "the look asked for didn't happen"

say "what it finds"
[ -n "$APP" ] && ok "the labelled app ($APP)" || bad "the labelled app isn't a part"
case " $(val "s.get('candidates', '')") " in *" mbt-plain "*) ok "the plain app can be picked" ;; *) bad "the plain app isn't offered: $(val "s.get('candidates')")" ;; esac
un=$(val "s.get('unreachable', '')")
case $un in *"mbt-away@$WORK/away"*) ok "the app in another folder is out of reach" ;; *) bad "out of reach not said: $un" ;; esac
case $un in *"mbt-loose@-"*) ok "the app without a compose file too" ;; *) bad "the one without compose not said: $un" ;; esac

say "update"
publish v2
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('updated') and s.get('result') != 'running'" 180 && runs_on mbt-app "$REG/mbt-app:v2" &&
  ok "v1 -> v2" || bad "not updated: $(val "s.get('$APP')"), runs $(docker inspect -f '{{.Image}}' mbt-app)"

say "a version that doesn't start"
publish broken
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('rolled_back') and s.get('result') != 'running'" 400 && runs_on mbt-app "$REG/mbt-app:v2" &&
  ok "back on v2" || bad "not back: $(val "s.get('$APP')"), runs $(docker inspect -f '{{.Image}}' mbt-app)"
[ -n "$(val "s.get('${APP}_failed')")" ] && ok "the broken one is left out" || bad "the broken one isn't noted"
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('skipped_failed') and s.get('result') != 'running'" 120 && runs_on mbt-app "$REG/mbt-app:v2" &&
  ok "not tried again" || bad "tried again: $(val "s.get('$APP')")"

say "the mower out of the dock"
publish v3
mower out
sleep 3
post "now=$APP" > /dev/null
until_true "s.get('result') == 'waiting'" 60 && runs_on mbt-app "$REG/mbt-app:v2" && ok "it waits, nothing changed" || bad "it didn't wait: $(val "s.get('result')")"
mower docked
sleep 3

say "stopped halfway"
post "now=$APP" > /dev/null
until_true "s.get('progress', '').startswith('$APP wait')" 120 || bad "it never got to the wait"
docker restart -t 1 mbt-updater > /dev/null
until_true "s.get('$APP', '').startswith('updated') and s.get('result') != 'running'" 240 && runs_on mbt-app "$REG/mbt-app:v3" &&
  ok "after the restart it looked again: v3 runs" || bad "after the restart: $(val "s.get('$APP')"), result $(val "s.get('result')")"
[ "$(log_has 'stopped halfway')" = True ] && ok "it says so in its log" || bad "the log doesn't say it was stopped"

say "picked by hand"
post conf 'picked mbt-plain' > /dev/null
post check > /dev/null
until_true "any(p['container'] == 'mbt-plain' for p in d.get('parts', []))" 60 && ok "added" || bad "not added"
PLAIN=$(part mbt-plain)
[ "$(val "s.get('${PLAIN}_picked')")" = yes ] && ok "marked as picked" || bad "not marked as picked"
post conf 'picked none' > /dev/null
post check > /dev/null
until_true "not any(p['container'] == 'mbt-plain' for p in d.get('parts', [])) and not any(k.endswith('_picked') for k in s)" 60 &&
  ok "taken out again" || bad "still there"

say "stable older than what runs"
APP2=$(part mbt-app2)
post conf "$APP2 stable" > /dev/null
post "now=$APP2" > /dev/null
until_true "s.get('$APP2', '').startswith('stable_older') and s.get('result') != 'running'" 120 && runs_on mbt-app2 "$REG/mbt-app:9.9.9" &&
  ok "stays on 9.9.9 ($(val "s.get('$APP2')"))" || bad "stable: $(val "s.get('$APP2')"), runs $(docker inspect -f '{{.Image}}' mbt-app2)"

say "built from github with pull_policy: build"
if docker compose -f "$STACKS/build/compose.yaml" up -d > /dev/null 2>&1; then
  post check > /dev/null
  until_true "any(p['container'] == 'mbt-build' and p['kind'] == 'build' for p in d.get('parts', []))" 120 || bad "not found as a build"
  BUILD=$(part mbt-build)
  post "now=$BUILD" > /dev/null
  until_true "s.get('$BUILD', '').split(' ')[0] in ('updated', 'rolled_back', 'error') and s.get('result') != 'running'" 600
  r=$(val "s.get('$BUILD')")
  case $r in updated*) ok "updated without going back" ;; *) bad "build: $r" ;; esac
  runs_on mbt-build mbt-build:edge && ok "runs the image it checked" || bad "runs another image than its tag"
else
  bad "the build stack doesn't come up (github?)"
fi

say "itself"
docker build -q --label org.opencontainers.image.revision=b000000test -t "$REG/mbt-updater:b" . > /dev/null
docker push -q "$REG/mbt-updater:b" > /dev/null
docker buildx imagetools create -t "$REG/mbt-updater:latest" "$REG/mbt-updater:b" > /dev/null 2>&1
post check > /dev/null
until_true "s.get('updater_available', '').startswith('yes')" 60 && ok "sees its newer version" || bad "doesn't see it: $(val "s.get('updater_available')")"
post self > /dev/null
until_true "s.get('updater', '').startswith('updated') and 'b000000' in s.get('updater_running', '')" 240 && ok "runs its new version" ||
  bad "itself: $(val "s.get('updater')") $(val "s.get('updater_running')")"
dir=$WORK/img-selfbroken
mkdir -p "$dir"
printf 'FROM %s\nLABEL org.opencontainers.image.revision=c000000test\nENTRYPOINT ["sh", "-c", "exit 1"]\n' "$REG/mbt-updater:b" > "$dir/Dockerfile"
docker build -q -t "$REG/mbt-updater:c" "$dir" > /dev/null
docker push -q "$REG/mbt-updater:c" > /dev/null
docker buildx imagetools create -t "$REG/mbt-updater:latest" "$REG/mbt-updater:c" > /dev/null 2>&1
post self > /dev/null
until_true "s.get('updater', '').startswith('rolled_back') and 'b000000' in s.get('updater_running', '')" 400 && ok "a broken version of itself: back on the one before" ||
  bad "broken self: $(val "s.get('updater')") $(val "s.get('updater_running')")"
[ "$(docker inspect -f '{{.State.Running}}' mbt-updater 2> /dev/null)" = true ] && ok "and it runs" || bad "the updater doesn't run any more"

say "done"
if [ $fails -eq 0 ]; then echo "all passed"; else
  echo "$fails failed"
  echo "--- its log"
  st | python3 -c "import json, sys; print('\n'.join(json.load(sys.stdin).get('log', [])[-60:]))" 2> /dev/null
fi
[ $fails -eq 0 ]
