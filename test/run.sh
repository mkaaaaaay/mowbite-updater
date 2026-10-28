#!/bin/sh
# the updater against a mower of its own on this docker: a registry, a broker with a made-up mower state, OpenMower with
# its .env, MowBite, the planner built on OpenMower, small apps in stacks. it starts from the updater that's out
# (ghcr.io; MBT_FROM=checkout or without ghcr: from a build of this checkout) and updates that to this checkout the way
# each mower does, then each case through its interface, the way its page and MowBite use it, and a look at what runs
# and at the files it changed. only what's labelled mbt.run=<id> or named <id>-* is made here (MBT_ID, default mbt) and
# cleared away afterwards, also when it's stopped; a second run at the same time needs another MBT_ID and other
# MBT_*_PORTs. its folder in TMPDIR (or MBT_WORK, kept then), on a disk with 1.5 GB free. needs docker with compose and
# buildx, curl, python3 and the internet (ghcr.io, github for the builds and the stable channel). about 45 minutes,
# most of it waiting for versions that don't start
set -u
cd "$(dirname "$0")/.." || exit 1
SRC=$PWD
P=${MBT_ID:-mbt}
REG=127.0.0.1:${MBT_REGISTRY_PORT:-5077}
MQTT=${MBT_MQTT_PORT:-51877}
PAGE=${MBT_PAGE_PORT:-58077}
WORK=${MBT_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/mbt.XXXXXX")}
STACKS=$WORK/stacks
STATE=$STACKS/updater/.updater
OMENV=$STACKS/om/.env
API=http://127.0.0.1:$PAGE/cgi-bin/updater
# the updater every mower runs right now: the update to this checkout starts from it
OUT=ghcr.io/mkaaaaaay/mowbite-updater:latest
fails=0
finished=
gate=

case $P in "" | *[!a-z0-9-]*)
  echo "MBT_ID: a-z, 0-9 and -"
  exit 1
  ;;
esac

began=$(date +%s)
say() { printf '\n== %s (%s)\n' "$*" "$(date -u -d "@$(($(date +%s) - began))" +%M:%S)"; }
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
  sleep 2
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
# until the shell command is true, within $2 seconds
until_sh() {
  end=$(($(date +%s) + $2))
  while [ "$(date +%s)" -lt "$end" ]; do
    eval "$1" && return 0
    sleep 1
  done
  return 1
}
# a part's id by its container
part() { val "next((p['id'] for p in d.get('parts', []) if p['container'] == '$1'), '')"; }
id_of() { docker image inspect -f '{{.Id}}' "$1" 2> /dev/null; }
runs_on() { [ "$(docker inspect -f '{{.Image}}' "$1" 2> /dev/null)" = "$(id_of "$2")" ]; }
log_has() { val "any('$1' in l for l in d.get('log', []))"; }
# what its card says last, its first word
said() { val "s.get('$1', '').split(' ')[0]"; }
# the rollback tags of a part in the app's repository
backs() { docker images --format '{{.Tag}}' "$REG/$P-app" | grep -c "^rb-$1-"; }
# a file's owner and rights, and the version in OpenMower's .env
perm() { stat -c %u:%g:%a "$1"; }
envv() { sed -n 's/^VERSION=//p' "$OMENV"; }
# its status written the way it writes it
in_updater() { docker exec "$P-updater" sh -c ". /lib.sh; $1"; }

# the registry's front (test/gate.py): the daemon's download from a repository held, or no answer at all
hold() { echo "$P-$1" > "$WORK/gate/hold"; }
release() { rm -f "$WORK/gate/hold"; }
registry_down() { : > "$WORK/gate/down"; }
registry_up() { rm -f "$WORK/gate/down"; }

# --- the world ---

cleanup() {
  trap - EXIT
  trap '' INT TERM
  # (what went wrong, its log before it's gone)
  if [ "$fails" -gt 0 ] || [ -z "$finished" ]; then
    echo "--- its log"
    st | python3 -c "import json, sys; print('\n'.join(json.load(sys.stdin).get('log', [])[-80:]))" 2> /dev/null ||
      docker logs --tail 40 "$P-updater" 2>&1
  fi
  say "clearing away"
  for f in "$STACKS"/*/compose.yaml "$WORK"/away/compose.yaml; do
    [ -f "$f" ] && docker compose -f "$f" down -v -t 2 > /dev/null 2>&1
  done
  docker ps -aq --filter "label=mbt.run=$P" | xargs -r docker rm -fv > /dev/null 2>&1
  docker ps -aq --filter "name=^$P-" | xargs -r docker rm -fv > /dev/null 2>&1
  # (the helper of the updater that's out has its fixed name: only the one on this run's stacks)
  for c in $(docker ps -aq --filter 'name=^mowbite-updater-self$'); do
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2> /dev/null | grep -qx "STATE_DIR=$STATE" &&
      docker rm -f "$c" > /dev/null 2>&1
  done
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^($REG/)?$P-" | xargs -r docker rmi -f > /dev/null 2>&1
  docker images -q --filter "label=mbt.run=$P" | sort -u | xargs -r docker rmi -f > /dev/null 2>&1
  docker network ls -q --filter "name=^$P-" | xargs -r docker network rm > /dev/null 2>&1
  [ -n "$gate" ] && kill "$gate" 2> /dev/null
  # (its folder in the stack is root's, the updater runs as root)
  [ -z "${MBT_WORK:-}" ] && docker run --rm --label "mbt.run=$P" -v "$WORK:/work" busybox:1.37-musl rm -rf /work/stacks > /dev/null 2>&1
  [ -z "${MBT_WORK:-}" ] && rm -rf "$WORK"
}

# a test image <repo>:<tag> in the registry: run (says ready and stays, with /start for a planner built on it), crash
# (ends at once), nostart (can't be started), bare (stays, nothing for a planner), mowbite (says its version $4)
img() {
  dir=$WORK/img/$1-$2
  mkdir -p "$dir"
  {
    echo 'FROM busybox:1.37-musl'
    echo "LABEL mbt.run=$P mbt.version=$1:$2"
    case $3 in
    run) printf 'RUN printf "#!/bin/sh\\necho ready\\necho MowBite Planner answers\\nexec sleep 100000\\n" > /start && chmod 755 /start\nCMD ["/start"]\n' ;;
    crash) echo 'CMD ["sh", "-c", "exit 1"]' ;;
    nostart) echo 'CMD ["/nothing"]' ;;
    bare) echo 'CMD ["sleep", "100000"]' ;;
    mowbite)
      cat > "$dir/version" << EOF
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
[ -e /tmp/quiet ] || printf '{"version":"$4"}'
EOF
      printf 'COPY --chmod=755 version /www/cgi-bin/version\nCMD ["httpd", "-f", "-p", "8080", "-h", "/www"]\n'
      ;;
    esac
  } > "$dir/Dockerfile"
  docker build -q -t "$REG/$P-$1:$2" "$dir" > /dev/null && docker push -q "$REG/$P-$1:$2" > /dev/null
}
# an image only in the registry, not here: its download has something to hold (gate.py)
forget() { docker rmi "$REG/$P-$1" > /dev/null 2>&1; }
# a tag in the registry moved to the image of another, nothing changed here (as on a mower: only the updater pulls)
move() { docker buildx imagetools create -t "$REG/$P-$1:$2" "$REG/$P-$1:$3" > /dev/null 2>&1; }
publish() { move app latest "$1"; }
# the updater built from this checkout (<tag> <revision>), or on top of that build (<tag> <revision> broken|label)
updater_img() {
  if [ -z "${3:-}" ]; then
    docker build -q --label "mbt.run=$P" --label "org.opencontainers.image.revision=$2" -t "$REG/$P-updater:$1" . > /dev/null
  else
    dir=$WORK/img/updater-$1
    mkdir -p "$dir"
    {
      echo "FROM $REG/$P-updater:b"
      echo "LABEL mbt.run=$P org.opencontainers.image.revision=$2"
      [ "$3" = broken ] && echo 'ENTRYPOINT ["sh", "-c", "exit 1"]'
    } > "$dir/Dockerfile"
    docker build -q -t "$REG/$P-updater:$1" "$dir" > /dev/null
  fi && docker push -q "$REG/$P-updater:$1" > /dev/null
}

say "setting up in $WORK ($P)"
if [ -n "$(docker ps -aq --filter "label=mbt.run=$P")" ]; then
  echo "there's a run with the id $P (or what's left of one): another MBT_ID, or clear it away"
  [ -z "${MBT_WORK:-}" ] && rmdir "$WORK"
  exit 1
fi
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$WORK/state" "$WORK/gate" "$WORK/img" "$WORK/away" "$STACKS"
# (it measures the room where its stacks are: OpenMower wants 1 GB to spare)
[ "$(df -Pm "$WORK" | awk 'NR == 2 {print $4}')" -ge 1500 ] || echo "   (less than 1.5 GB free in $WORK: OpenMower's cases need more, TMPDIR or MBT_WORK elsewhere)"
mower docked
docker run -d --name "$P-registry" --label "mbt.run=$P" -p 127.0.0.1::5000 registry:2 > /dev/null || { bad "no registry"; exit 1; }
behind=$(docker port "$P-registry" 5000/tcp | sed -n 's/^127\.0\.0\.1://p' | head -n1)
python3 "$SRC/test/gate.py" "${REG#*:}" "$behind" "$WORK/gate" &
gate=$!
docker run -d --name "$P-broker" --label "mbt.run=$P" -p "127.0.0.1:$MQTT:1883" eclipse-mosquitto:2 mosquitto -c /mosquitto-no-auth.conf > /dev/null ||
  { bad "no broker"; exit 1; }
docker run -d --name "$P-pub" --label "mbt.run=$P" --network host -v "$WORK/state:/state:ro" eclipse-mosquitto:2 sh -c \
  "while :; do mosquitto_pub -h 127.0.0.1 -p $MQTT -t robot_state/json -f /state/robot_state.json; sleep 1; done" > /dev/null
sleep 3
kill -0 "$gate" 2> /dev/null || { bad "no front for the registry (port ${REG#*:} taken?)"; exit 1; }

# the version it starts from, and this checkout
if [ "${MBT_FROM:-}" != checkout ] && timeout 600 docker buildx imagetools create -t "$REG/$P-updater:a" "$OUT" > /dev/null 2>&1; then
  from="from $OUT"
else
  from="from a build of this checkout"
  [ "${MBT_FROM:-}" = checkout ] || echo "   ($OUT can't be had: it starts $from)"
  updater_img a a000000test || { bad "the updater doesn't build"; exit 1; }
fi
updater_img b b000000test || { bad "the updater doesn't build"; exit 1; }
move updater latest a
# the newest release of MowBite, the stable channel of the apps here
REL=$(curl -sI -m 15 https://github.com/mkaaaaaay/mowbite/releases/latest | tr -d '\r' |
  sed -n 's|^[Ll]ocation: .*/releases/tag/v\{0,1\}\([^[:space:]?]*\).*|\1|p' | tail -n1)
for v in v1 v2 v3 v4 v5 dl a3old a3new a3n1 a3n2; do img app "$v" run || bad "app:$v doesn't build"; done
for v in o1 o2 o3 o4 o6 o7 o8 o9; do img om "$v" run || bad "om:$v doesn't build"; done
img app broken crash && img om ox nostart && img om o5 bare && img mowbite m1 mowbite 9.0.0-beta.1 || bad "a test image doesn't build"
[ $fails -eq 0 ] || exit 1
O6=$(id_of "$REG/$P-om:o6")
forget app:dl
forget om:o6
forget om:o8
forget om:o9
publish v1
move app 9.9.9 v2
move app 0.0.1 a3old
[ -n "$REL" ] && move app "$REL" a3new
move om v1 o1
move om edge o2
move om latest ox
move mowbite latest m1

mkdir -p "$STACKS/updater" "$STACKS/app" "$STACKS/plain" "$STACKS/build" "$STACKS/app2" "$STACKS/app3" "$STACKS/om" \
  "$STACKS/planner" "$STACKS/mowbite" "$STACKS/twin" "$STACKS/mosq" "$STACKS/names"
cat > "$STACKS/updater/compose.yaml" << EOF
name: $P-updater
services:
  updater:
    image: $REG/$P-updater:latest
    container_name: $P-updater
    restart: unless-stopped
    network_mode: host
    labels:
      mbt.run: $P
    environment:
      PORT: "$PAGE"
      MQTT_PORT: "$MQTT"
      MQTT_USER: mbt
      MQTT_PASSWORD: mbt-secret
      UPDATER_CONTAINER: $P-updater
      UPDATER_SELF: $P-updater-self
      OPENMOWER_CONTAINER: $P-om
      MOWBITE_CONTAINER: $P-mowbite
      PLANNER_CONTAINER: $P-planner
      PRUNE: "0"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $STACKS:$STACKS
EOF
# (pull_policy: always: compose would get the new version back on the way back)
cat > "$STACKS/app/compose.yaml" << EOF
name: $P-app
services:
  app:
    image: $REG/$P-app:latest
    container_name: $P-app
    network_mode: bridge
    pull_policy: always
    labels:
      mbt.run: $P
      mowbite.update: "on"
EOF
cat > "$STACKS/plain/compose.yaml" << EOF
name: $P-plain
services:
  plain:
    image: busybox:1.37-musl
    container_name: $P-plain
    network_mode: bridge
    command: sleep 100000
    labels:
      mbt.run: $P
EOF
# built from github with pull_policy: build, like the MowBite Planner: compose up would build it once more
cat > "$STACKS/build/compose.yaml" << EOF
name: $P-build
services:
  build:
    build:
      context: https://github.com/mkaaaaaay/mowbite-updater.git#main
      dockerfile_inline: |
        FROM busybox:1.37-musl
        LABEL mbt.run=$P
        CMD ["sh", "-c", "echo ready; exec sleep 100000"]
    image: $P-build:edge
    pull_policy: build
    container_name: $P-build
    network_mode: bridge
    labels:
      mbt.run: $P
      mowbite.update: "on"
      mowbite.update.log: ready
EOF
# a version as its tag and a stable channel from a repository whose newest release (MowBite's) is older
cat > "$STACKS/app2/compose.yaml" << EOF
name: $P-app2
services:
  app2:
    image: $REG/$P-app:9.9.9
    container_name: $P-app2
    network_mode: bridge
    labels:
      mbt.run: $P
      mowbite.update: "on"
      mowbite.update.stable: github:mkaaaaaay/mowbite
EOF
# the same repository as the first app, older than the release, shows it runs in its log
cat > "$STACKS/app3/compose.yaml" << EOF
name: $P-app3
services:
  app3:
    image: $REG/$P-app:0.0.1
    container_name: $P-app3
    network_mode: bridge
    labels:
      mbt.run: $P
      mowbite.update: "on"
      mowbite.update.stable: github:mkaaaaaay/mowbite
      mowbite.update.log: ready
EOF
chmod 640 "$STACKS/app3/compose.yaml"
cat > "$STACKS/om/compose.yaml" << EOF
name: $P-om
services:
  open_mower_ros:
    image: $REG/$P-om:\${VERSION}
    container_name: $P-om
    network_mode: bridge
    labels:
      mbt.run: $P
EOF
printf '# made-up OpenMower\nVERSION="v1"\nOM_PLANNER=external\n' > "$OMENV"
chmod 640 "$OMENV"
# built on OpenMower's image like the planner, from github, starts with what OpenMower's image has for it
cat > "$STACKS/planner/compose.yaml" << EOF
name: $P-planner
services:
  planner:
    build:
      context: https://github.com/mkaaaaaay/mowbite-updater.git#main
      dockerfile_inline: |
        ARG OPENMOWER_IMAGE
        FROM \$\${OPENMOWER_IMAGE}
        LABEL mbt.run=$P
        CMD ["/start"]
      args:
        OPENMOWER_IMAGE: $REG/$P-om:edge
    image: $P-planner:edge
    pull_policy: build
    container_name: $P-planner
    network_mode: bridge
    labels:
      mbt.run: $P
EOF
# image: and build: . like MowBite's own stack, the stable channel by its label
cat > "$STACKS/mowbite/compose.yaml" << EOF
name: $P-mowbite
services:
  mowbite:
    image: $REG/$P-mowbite:latest
    build: .
    container_name: $P-mowbite
    network_mode: bridge
    labels:
      mbt.run: $P
      mowbite.update.stable: github:mkaaaaaay/mowbite
EOF
printf 'FROM busybox:1.37-musl\n' > "$STACKS/mowbite/Dockerfile"
# the updater's own image under another name, labelled: not an app to update from inside
cat > "$STACKS/twin/compose.yaml" << EOF
name: $P-twin
services:
  twin:
    image: $REG/$P-updater:a
    container_name: $P-twin
    network_mode: bridge
    entrypoint: ["sleep", "100000"]
    labels:
      mbt.run: $P
      mowbite.update: "on"
EOF
# an mqtt broker in a stack: never offered as an app
cat > "$STACKS/mosq/compose.yaml" << EOF
name: $P-mosq
services:
  mosq:
    image: eclipse-mosquitto:2
    container_name: $P-mosq
    network_mode: bridge
    command: sleep 100000
    labels:
      mbt.run: $P
EOF
cat > "$WORK/away/compose.yaml" << EOF
name: $P-away
services:
  away:
    image: busybox:1.37-musl
    container_name: $P-away
    network_mode: bridge
    command: sleep 100000
    labels:
      mbt.run: $P
      mowbite.update: "on"
EOF
docker pull -q "$REG/$P-mowbite:latest" > /dev/null
for s in app plain app2 app3 om mowbite twin mosq; do
  docker compose -f "$STACKS/$s/compose.yaml" up -d > /dev/null 2>&1 || bad "the stack $s doesn't come up"
done
# OpenMower's .env saved in dockge with another version, not started since
sed -i 's/^VERSION=.*/VERSION="latest"/' "$OMENV"
docker pull -q "$REG/$P-om:edge" > /dev/null
docker compose -f "$STACKS/planner/compose.yaml" up -d > /dev/null 2>&1 || bad "the planner doesn't build (github?)"
docker compose -f "$WORK/away/compose.yaml" up -d > /dev/null 2>&1
docker run -d --name "$P-loose" --label "mbt.run=$P" --label mowbite.update=on busybox:1.37-musl sleep 100000 > /dev/null
docker compose -f "$STACKS/updater/compose.yaml" up -d > /dev/null 2>&1
until_true "s.get('checked')" 180 || { bad "the updater doesn't come up"; exit 1; }
ok "the updater runs and has looked ($from, $(val "s.get('updater_running')"))"

# --- the cases ---

say "itself: to this checkout"
# (the night's window far off: nothing runs by itself before its case)
FAR=$(date -u -d '+6 hours' +%H:%M)
post conf "$(printf 'at %s\ndays 1,3,5' "$FAR")" > /dev/null
move updater latest b
post self > /dev/null
until_true "s.get('updater', '').startswith('updated') and 'b000000' in s.get('updater_running', '')" 300 &&
  ok "it updates itself to this checkout" || bad "not to this checkout: $(val "s.get('updater')"), runs $(val "s.get('updater_running')")"
[ "$(val "c.get('at') + ' ' + c.get('days')")" = "$FAR 1,3,5" ] && ok "with the settings it had" || bad "its settings: $(val 'c')"
[ -z "$(val "s.get('updater_failed')")" ] && ok "nothing left out" || bad "left out: $(val "s.get('updater_failed')")"
APP=$(part "$P-app")
APP2=$(part "$P-app2")
APP3=$(part "$P-app3")

say "interface"
[ "$(curl -s -m 10 -X POST --data-binary x "$API?check")" = bad ] && ok "a post without json is turned down" || bad "a post without json went through"
post conf 'picked x;rm -rf /,y
days 9
at 3:00' > /dev/null
[ "$(val "c.get('picked')")" = none ] && [ "$(val "c.get('days')")" = 1,3,5 ] && [ "$(val "c.get('at')")" = "$FAR" ] &&
  ok "settings that aren't valid are left out, the ones before stay" || bad "settings not checked: $(val 'c')"
# (taken: away from the queue, the look itself may take its time. the look of its start over first: it would only
# stop for it between two steps, and a step may wait for its registry)
until_true "int(s.get('checked', 0)) >= int(s.get('started', '0').split(' ')[0]) and not s.get('looking')" 180 || bad "its first look didn't end"
t0=$(date +%s)
post check > /dev/null
until_true "not d.get('requested')" 15 && ok "a request is taken at once ($(($(date +%s) - t0)) s)" || bad "a request waited longer than 15 s"
until_true "int(s.get('checked', 0)) >= $t0" 120 || bad "the look asked for didn't happen"
# one while it looks goes first (not after the look and a minute's sleep): the look stops for it, before its end, and
# is done again. (how long it takes is a step of the look, a step may wait for its registry)
t1=$(date +%s)
post check > /dev/null
sleep 2
post room > /dev/null
t2=$(date +%s)
until_true "not d.get('requested')" 120 && [ "$(val "int(s.get('checked', 0)) < $t1")" = True ] &&
  ok "a request while it looks is taken at once, the look stops for it ($(($(date +%s) - t2)) s)" ||
  bad "a request while it looks waited: checked $(val "s.get('checked')"), the look from $t1"
until_true "int(s.get('checked', 0)) >= $t1 and not s.get('looking') and not s.get('taken')" 180 && ok "the look done again after it" ||
  bad "the look wasn't done again: checked $(val "s.get('checked')"), looking $(val "s.get('looking')"), taken $(val "s.get('taken')")"
# its page asked for again each time (busybox's httpd sends its files without cache-control), what it loads named with
# its version, also as MowBite embeds it
r=$(curl -s -m 10 -D - "http://127.0.0.1:$PAGE/?embed=1&theme=dark&lang=de" | tr -d '\r')
case $r in
*"Cache-Control: no-cache"*'<script src="app.js?v='[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'"></script>'*) ok "its page, asked for again each time" ;;
*) bad "its page: $(printf '%s' "$r" | head -n 4 | tr '\n' ' ')" ;;
esac
# settings from two places at the same time: one after the other, none lost
ids="openmower planner mowbite $APP $APP2 $APP3"
pids=
for id in $ids; do
  post conf "${id}_auto 1" > /dev/null &
  pids="$pids $!"
done
# shellcheck disable=SC2086
wait $pids
n=0
for id in $ids; do [ "$(val "c.get('${id}_auto')")" = 1 ] && n=$((n + 1)); done
[ $n -eq 6 ] && ok "six settings sent at once: none lost" || bad "sent at once: $n of 6 kept ($(val 'c'))"
post conf "$(for id in $ids; do echo "${id}_auto 0"; done)" > /dev/null
# a full disk, in a container of its own on its image: its status and settings stay whole, the page is told
r=$(docker run --rm --label "mbt.run=$P" --tmpfs /s:size=64k --entrypoint sh "$REG/$P-updater:b" -c '
  export STATE_DIR=/s
  . /lib.sh
  printf "at 05:00\ndays daily\n" > "$CONF"
  status result running
  status pending_x a b
  dd if=/dev/zero of=/s/fill bs=1k 2> /dev/null
  status looking
  status alive 1
  printf "%s|%s|" "$(get result)" "$(get pending_x)"
  printf "at 06:00\n" | REQUEST_METHOD=POST CONTENT_TYPE=application/json QUERY_STRING=conf CONTENT_LENGTH=9 sh /www/cgi-bin/updater |
    tail -n1 | tr -d "\r\n"
  printf "|%s" "$(tr "\n" " " < "$CONF")"' 2> /dev/null)
[ "$r" = "running|a b|failed|at 05:00 days daily " ] && ok "a full disk: status and settings stay whole, the page hears it failed" ||
  bad "a full disk: $r"

say "what it finds"
[ -n "$APP" ] && ok "the labelled app ($APP)" || bad "the labelled app isn't a part"
cand=" $(val "s.get('candidates', '')") "
case $cand in *" $P-plain "*) ok "the plain app can be picked" ;; *) bad "the plain app isn't offered: $cand" ;; esac
case $cand in *" $P-mosq "* | *" $P-twin "*) bad "offered: $cand" ;; *) ok "not offered: an mqtt broker, a container on its own image" ;; esac
[ -z "$(part "$P-twin")" ] && ok "a labelled container on its own image isn't a part" || bad "its own image is a part"
r=$(val "' '.join(p['id'] + ':' + p['kind'] for p in d.get('parts', []) if p['id'] in ('openmower', 'mowbite', 'planner'))")
[ "$r" = "openmower:openmower mowbite:image planner:build" ] && ok "OpenMower, MowBite and the planner" || bad "found: $r"
un=$(val "s.get('unreachable', '')")
case $un in *"$P-away@$WORK/away"*) ok "the app in another folder is out of reach" ;; *) bad "out of reach not said: $un" ;; esac
case $un in *"$P-loose@-"*) ok "the app without a compose file too" ;; *) bad "the one without compose not said: $un" ;; esac
[ "$(val "s.get('clock')")" = +0000 ] && ok "the mower's time zone" || bad "its time zone: $(val "s.get('clock')")"
r=$(docker exec "$P-updater" sh -c 'f=${XDG_CONFIG_HOME:-$HOME/.config}/mosquitto_sub; stat -c %a "$f"; head -n1 "$f"' 2> /dev/null | tr '\n' ' ')
[ "$(val "s.get('mower')")" = 1 ] && [ "$r" = "600 -u mbt " ] && ok "the broker's user and password in a file of its own, not on a command line" ||
  bad "the broker: mower $(val "s.get('mower')"), its file: $r"

say "update"
publish v2
t0=$(date +%s)
post "now=$APP" > /dev/null
until_true "'now:$APP' in s.get('taken', '') or s.get('result') == 'running'" 10 && ok "its page knows at once it's on it" ||
  bad "nothing for its page: taken $(val "s.get('taken')"), result $(val "s.get('result')")"
until_true "s.get('$APP', '').startswith('updated') and s.get('result') != 'running'" 180 && runs_on "$P-app" "$REG/$P-app:v2" &&
  ok "v1 -> v2" || bad "not updated: $(val "s.get('$APP')"), runs $(docker inspect -f '{{.Image}}' "$P-app")"
[ "$(said "${APP}_available")" = no ] && ok "its card says up to date right away" || bad "still new: $(val "s.get('${APP}_available')")"
[ "$(val "int(s.get('${APP}_at', 0)) >= $t0")" = True ] && ok "and when" || bad "no time: $(val "s.get('${APP}_at')")"
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('current') and s.get('result') != 'running'" 60 && runs_on "$P-app" "$REG/$P-app:v2" &&
  ok "again: up to date, nothing downloaded" || bad "again: $(val "s.get('$APP')")"

say "a version that doesn't start"
publish broken
t0=$(date +%s)
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('rolled_back') and s.get('result') != 'running'" 400 && runs_on "$P-app" "$REG/$P-app:v2" &&
  ok "back on v2, not pulled again on the way (pull_policy: always)" || bad "not back: $(val "s.get('$APP')"), runs $(docker inspect -f '{{.Image}}' "$P-app")"
[ "$(val "len(s.get('${APP}_failed', '').split())")" = 2 ] && ok "the broken one is left out, by its id and its digest" ||
  bad "left out: $(val "s.get('${APP}_failed')")"
until_true "int(s.get('checked', 0)) >= $t0 and s.get('${APP}_available', '').startswith('failed')" 120 && ok "its card says so" ||
  bad "its card: $(val "s.get('${APP}_available')")"
broken=$(id_of "$REG/$P-app:broken")
docker rmi "$REG/$P-app:broken" > /dev/null 2>&1
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('skipped_failed') and s.get('result') != 'running'" 120 && runs_on "$P-app" "$REG/$P-app:v2" &&
  ok "not tried again" || bad "tried again: $(val "s.get('$APP')")"
docker image inspect "$broken" > /dev/null 2>&1 && bad "downloaded again to see it's the one left out" || ok "not even downloaded"
# (as an updater before this one noted it: only its id)
in_updater "status ${APP}_failed $broken"
t0=$(date +%s)
post "now=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('skipped_failed') and int(s.get('${APP}_at', 0)) >= $t0 and int(s.get('checked', 0)) >= $t0" 120 &&
  runs_on "$P-app" "$REG/$P-app:v2" && ok "one left out by its id only: the same" || bad "by its id only: $(val "s.get('$APP')")"

say "the mower out of the dock"
publish v3
mower out
checked=$(val "s.get('checked')")
post "now=$APP" > /dev/null
until_true "s.get('result') == 'waiting'" 60 && runs_on "$P-app" "$REG/$P-app:v2" && ok "it waits, nothing changed" || bad "it didn't wait: $(val "s.get('result')")"
[ "$(val "s.get('$APP')")" = "error not_docked" ] && ok "its card says why" || bad "its card says: $(val "s.get('$APP')")"
sleep 5
[ "$(val "s.get('checked')")" = "$checked" ] && ok "nothing done: no tidying up, no look after it" || bad "it looked after a run that did nothing"

say "the mower leaves during a download"
mower docked
publish dl
n=$(backs "$APP")
hold app
post "now=$APP" > /dev/null
until_sh '[ "$(backs "$APP")" -gt "$n" ]' 60 || bad "it never got to the download"
sleep 2
mower out
until_true "s.get('result') == 'waiting'" 120 && ok "the download stopped" || bad "not stopped: $(val "s.get('result')"), $(val "s.get('progress')")"
release
sleep 5
[ "$(backs "$APP")" -eq "$n" ] && ok "the way back made for it gone" || bad "rollback tags: $(backs "$APP"), $n before"
runs_on "$P-app" "$REG/$P-app:v2" && [ "$(id_of "$REG/$P-app:latest")" = "$(id_of "$REG/$P-app:v2")" ] && ok "its tag still on what runs" ||
  bad "its tag on $(id_of "$REG/$P-app:latest")"
[ "$(val "s.get('$APP')")" = "error not_docked" ] && ok "its card says why" || bad "its card says: $(val "s.get('$APP')")"
mower docked
publish v3

say "stopped halfway"
# (and what a stop left of files being written: the ones a minute old go at its next start)
docker exec "$P-updater" sh -c 'cd "$1" && for f in status.aaaaaa log.bbbbbb conf.cccccc room.dddddd; do
  echo x > "$f" && touch -d "@$(($(date +%s) - 300))" "$f"; done && echo x > status.eeeeee' sh "$STATE"
post "now=$APP" > /dev/null
until_true "s.get('progress', '').startswith('$APP wait')" 120 || bad "it never got to the wait"
docker restart -t 1 "$P-updater" > /dev/null
until_true "s.get('$APP', '').startswith('updated') and s.get('result') != 'running'" 240 && runs_on "$P-app" "$REG/$P-app:v3" &&
  ok "after the restart it looked again: v3 runs" || bad "after the restart: $(val "s.get('$APP')"), result $(val "s.get('result')")"
[ "$(log_has 'stopped halfway')" = True ] && ok "it says so in its log" || bad "the log doesn't say it was stopped"
r=$(docker exec "$P-updater" sh -c 'cd "$1" && ls status.aaaaaa log.bbbbbb conf.cccccc room.dddddd status.eeeeee 2> /dev/null' sh "$STATE" | tr '\n' ' ')
[ "$r" = "status.eeeeee " ] && ok "what's left of files being written is gone, the one just written stays" || bad "left: $r"
docker exec "$P-updater" rm -f "$STATE/status.eeeeee"

say "picked by hand"
post conf "picked $P-plain" > /dev/null
post check > /dev/null
until_true "any(p['container'] == '$P-plain' for p in d.get('parts', []))" 60 && ok "added" || bad "not added"
PLAIN=$(part "$P-plain")
[ "$(val "s.get('${PLAIN}_picked')")" = yes ] && ok "marked as picked" || bad "not marked as picked"
post conf 'picked none' > /dev/null
post check > /dev/null
until_true "not any(p['container'] == '$P-plain' for p in d.get('parts', [])) and not any(k.endswith('_picked') for k in s)" 60 &&
  ok "taken out again" || bad "still there"

say "stable older than what runs"
post conf "$APP2 stable" > /dev/null
post "now=$APP2" > /dev/null
until_true "s.get('$APP2', '').startswith('stable_older') and s.get('result') != 'running'" 120 && runs_on "$P-app2" "$REG/$P-app:9.9.9" &&
  ok "stays on 9.9.9 ($(val "s.get('$APP2')"))" || bad "stable: $(val "s.get('$APP2')"), runs $(docker inspect -f '{{.Image}}' "$P-app2")"

say "stable, another tag"
if [ -n "$REL" ]; then
  f=$STACKS/app3/compose.yaml
  mode=$(perm "$f")
  post conf "$APP3 stable" > /dev/null
  post "now=$APP3" > /dev/null
  until_true "s.get('$APP3', '').startswith('updated') and s.get('result') != 'running'" 180 && runs_on "$P-app3" "$REG/$P-app:a3new" &&
    grep -q "^ *image: $REG/$P-app:$REL\$" "$f" && ok "on stable $REL, its compose file says so" || bad "stable: $(val "s.get('$APP3')"), $(grep image: "$f")"
  [ "$(perm "$f")" = "$mode" ] && [ ! -e "$f.before-update" ] && ok "the file with its owner and rights, no copy left" || bad "the file: $(perm "$f")"
  docker image inspect "$REG/$P-app:0.0.1" > /dev/null 2>&1 && bad "the tag 0.0.1 is still here" || ok "the tag it ran from is gone, nothing names it"
  # (a compose file of another stack names the stable tag)
  printf 'name: %s-names\nservices:\n  names:\n    image: %s/%s-app:%s\n' "$P" "$REG" "$P" "$REL" > "$STACKS/names/compose.yaml"
  post conf "$APP3 beta" > /dev/null
  post "now=$APP3" > /dev/null
  until_true "s.get('$APP3', '').startswith('updated') and s.get('result') != 'running' and not s.get('${APP3}_beta')" 180 &&
    runs_on "$P-app3" "$REG/$P-app:a3old" && grep -q "^ *image: $REG/$P-app:0.0.1\$" "$f" && ok "back on beta: 0.0.1" ||
    bad "beta: $(val "s.get('$APP3')"), $(grep image: "$f")"
  docker image inspect "$REG/$P-app:$REL" > /dev/null 2>&1 && ok "the tag $REL stays, another compose file names it" || bad "the tag $REL is gone"
else
  bad "no stable release of MowBite (github?)"
fi

say "back by hand, two apps from one repository"
post "back=$APP" > /dev/null
until_true "s.get('$APP', '').startswith('back') and s.get('result') != 'running'" 180 && runs_on "$P-app" "$REG/$P-app:v2" &&
  ok "back on v2, its own way back (not the newer one of the other app)" || bad "back: $(val "s.get('$APP')"), runs $(docker inspect -f '{{.Image}}' "$P-app")"
case " $(val "s.get('${APP}_failed', '')") " in *" $(id_of "$REG/$P-app:v3") "*) ok "v3 left out from now on" ;; *) bad "left out: $(val "s.get('${APP}_failed')")" ;; esac

say "MowBite, its version"
until_true "s.get('mowbite_running', '').startswith('9.0.0-beta.1')" 60 && ok "the version it says" || bad "its version: $(val "s.get('mowbite_running')")"
docker exec "$P-mowbite" touch /tmp/quiet
post conf 'mowbite stable' > /dev/null
post now=mowbite > /dev/null
until_true "s.get('mowbite', '').startswith('stable_older') and s.get('result') != 'running'" 120 && runs_on "$P-mowbite" "$REG/$P-mowbite:m1" &&
  ok "it doesn't answer: the version it said before counts, stable $REL doesn't take it back" || bad "stable: $(val "s.get('mowbite')")"
docker exec "$P-mowbite" rm -f /tmp/quiet
post conf 'mowbite beta' > /dev/null

say "OpenMower, its .env saved with another version, the mower leaves during the download"
mode=$(perm "$OMENV")
# (one only in the registry: its download has something to hold)
move om latest o9
hold om
post now=openmower > /dev/null
until_true "any('-> $REG/$P-om:latest (needs' in l for l in d.get('log', []))" 120 || bad "it never got to the download"
sleep 2
mower out
until_true "s.get('result') == 'waiting'" 120 && runs_on "$P-om" "$REG/$P-om:o1" && ok "the download stopped" ||
  bad "not stopped: $(val "s.get('result')"), $(val "s.get('progress')")"
release
move om latest ox
[ "$(envv)" = '"latest"' ] && [ -z "$(val "s.get('openmower_saved')")" ] && ok "its .env with the version it was saved with again" ||
  bad "its .env: $(envv)"
[ "$(perm "$OMENV")" = "$mode" ] && [ ! -e "$OMENV.before-update" ] && ok "with its owner and rights, no copy left" || bad "the file: $(perm "$OMENV")"
mower docked

say "OpenMower, its .env saved with another version (one that doesn't start)"
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('rolled_back') and s.get('result') != 'running'" 240 && runs_on "$P-om" "$REG/$P-om:o1" &&
  ok "back on the version that ran" || bad "openmower: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
[ "$(envv)" = '"v1"' ] && ok "its .env says that one, not the one it was saved with" || bad "its .env: $(envv)"
grep -qx 'OM_PLANNER=external' "$OMENV" && grep -qx '# made-up OpenMower' "$OMENV" && ok "the rest of its .env as it was" || bad "its .env: $(cat "$OMENV")"
[ "$(perm "$OMENV")" = "$mode" ] && [ ! -e "$OMENV.before-update" ] && ok "with its owner and rights, no copy left" || bad "the file: $(perm "$OMENV")"
[ "$(val "len(s.get('openmower_failed', '').split())")" = 2 ] && ok "that version left out" || bad "left out: $(val "s.get('openmower_failed')")"

say "OpenMower, another channel"
post conf 'openmower edge' > /dev/null
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('updated') and s.get('result') != 'running'" 240 && runs_on "$P-om" "$REG/$P-om:o2" &&
  ok "on edge" || bad "edge: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
[ "$(envv)" = '"edge"' ] && [ "$(perm "$OMENV")" = "$mode" ] && ok "its .env says edge, its owner and rights kept" || bad "its .env: $(envv), $(perm "$OMENV")"
docker image inspect "$REG/$P-om:v1" > /dev/null 2>&1 && bad "the tag v1 is still here" || ok "the tag it ran from is gone, nothing names it"
case $(val "s.get('openmower_prev', '')") in "$REG/$P-om@sha256:"*) ok "its way back noted" ;; *) bad "no way back: $(val "s.get('openmower_prev')")" ;; esac
[ "$(val "s.get('planner_base_id')")" = "$(id_of "$REG/$P-om:o2")" ] && ok "the planner built on it" || bad "the planner on $(val "s.get('planner_base_id')")"

say "OpenMower, back to the version before"
until_true "s.get('openmower_back') == 'yes'" 120 && ok "its card offers it" || bad "not offered: $(val "s.get('openmower_back')")"
mower out
post back=openmower > /dev/null
until_true "s.get('openmower') == 'error not_docked'" 60 && runs_on "$P-om" "$REG/$P-om:o2" && ok "not with the mower out" || bad "with the mower out: $(val "s.get('openmower')")"
mower docked
post back=openmower > /dev/null
until_true "s.get('openmower', '').startswith('back') and s.get('result') != 'running'" 240 && runs_on "$P-om" "$REG/$P-om:o1" &&
  [ "$(val "s.get('openmower', '').split(' ')[-1]")" = edge ] && ok "the version before runs, under its tag edge" ||
  bad "back: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
case " $(val "s.get('openmower_failed', '')") " in *" $(id_of "$REG/$P-om:o2") "*) ok "the one it left is left out" ;; *) bad "left out: $(val "s.get('openmower_failed')")" ;; esac
[ "$(envv)" = '"edge"' ] && ok "its .env as it was" || bad "its .env: $(envv)"
[ "$(val "s.get('planner_base_id')")" = "$(id_of "$REG/$P-om:o1")" ] && ok "the planner built on it again" || bad "the planner on $(val "s.get('planner_base_id')")"
until_true "s.get('openmower_back') == 'no' and not s.get('looking')" 120 && ok "no further way back" || bad "still offered: $(val "s.get('openmower_back')")"
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('skipped_failed') and s.get('result') != 'running'" 120 && runs_on "$P-om" "$REG/$P-om:o1" &&
  ok "edge isn't taken again" || bad "edge again: $(val "s.get('openmower')")"

say "OpenMower, the planner waits for the dock"
# (as one it never built, deployed in dockge. after the look that follows the run before: nothing writes its status
# meanwhile)
until_true "int(s.get('checked', 0)) >= int(s.get('openmower_at', 0)) and not s.get('looking')" 180
in_updater "status planner_base_id"
move om edge o3
post now=openmower > /dev/null
until_true "s.get('progress', '').startswith('openmower wait')" 120 || bad "it never got to the wait"
mower out
until_true "s.get('openmower', '').startswith('updated') and s.get('result') != 'running'" 240 && runs_on "$P-om" "$REG/$P-om:o3" &&
  ok "OpenMower updated (it answers, the mower out meanwhile)" || bad "openmower: $(val "s.get('openmower')")"
[ -z "$(val "s.get('planner_base_id')")" ] && [ "$(log_has 'new version later')" = True ] &&
  ok "the planner not built with the mower out" || bad "the planner on $(val "s.get('planner_base_id')")"
mower docked
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('current') and s.get('result') != 'running'" 240 &&
  [ "$(val "s.get('planner_base_id')")" = "$(id_of "$REG/$P-om:o3")" ] && [ "$(said planner)" = updated ] &&
  ok "later, OpenMower as it is: the planner built on it (also one it never built before)" ||
  bad "later: $(val "s.get('openmower')"), the planner $(val "s.get('planner')")"

say "OpenMower, a stopped planner"
docker stop -t 1 "$P-planner" > /dev/null
move om edge o4
post now=openmower > /dev/null
until_true "s.get('planner', '').startswith('stopped') and s.get('result') != 'running'" 240 && ok "built, its card says stopped" ||
  bad "the planner: $(val "s.get('planner')")"
[ "$(docker inspect -f '{{.State.Running}}' "$P-planner")" = false ] && runs_on "$P-planner" "$P-planner:edge" &&
  [ "$(val "s.get('planner_base_id')")" = "$(id_of "$REG/$P-om:o4")" ] && ok "made anew on its build, still stopped" ||
  bad "the planner: $(docker inspect -f '{{.State.Status}}' "$P-planner")"
docker start "$P-planner" > /dev/null

say "OpenMower, a planner that doesn't start on it"
move om edge o5
ran=$(docker inspect -f '{{.Image}}' "$P-planner")
t0=$(date +%s)
post now=openmower > /dev/null
until_true "s.get('planner', '').startswith('rolled_back') and s.get('result') != 'running'" 240 &&
  [ "$(docker inspect -f '{{.Image}} {{.State.Running}}' "$P-planner")" = "$ran true" ] && ok "the planner back on its build before" ||
  bad "the planner: $(val "s.get('planner')")"
f=$(val "s.get('planner_failed', '')")
[ "${#f}" -gt 41 ] && [ "${f#* }" = "$(id_of "$REG/$P-om:o5")" ] && ok "left out: its commit on that OpenMower" || bad "left out: $f"
until_true "int(s.get('checked', 0)) >= $t0 and s.get('planner_available', '').startswith('failed')" 120 && ok "its card says so" ||
  bad "its card: $(val "s.get('planner_available')")"
post now=openmower > /dev/null
until_true "s.get('planner', '').startswith('skipped_failed') and s.get('result') != 'running'" 120 && runs_on "$P-planner" "$ran" &&
  ok "not built again on the same OpenMower" || bad "the planner: $(val "s.get('planner')")"

say "OpenMower, its .env changed during the download"
move om latest o6
post conf 'openmower latest' > /dev/null
hold om
post now=openmower > /dev/null
until_sh '[ "$(envv)" = "\"latest\"" ]' 120 || bad "its .env never said latest"
sleep 2
sed -i 's/^VERSION=.*/VERSION="edge"/' "$OMENV"
release
until_true "s.get('openmower') == 'error env' and s.get('result') != 'running'" 120 && runs_on "$P-om" "$REG/$P-om:o5" &&
  ok "it stays as it is" || bad "openmower: $(val "s.get('openmower')")"
[ "$(envv)" = '"edge"' ] && [ ! -e "$OMENV.before-update" ] && ok "with the version saved meanwhile" || bad "its .env: $(envv)"
case " $(val "s.get('openmower_failed', '')") " in *" $O6 "*) bad "latest left out for it" ;; *) ok "latest not left out for it" ;; esac

say "OpenMower, stopped during the download, its .env changed meanwhile"
move om latest o8
hold om
post now=openmower > /dev/null
until_sh '[ "$(envv)" = "\"latest\"" ]' 120 || bad "its .env never said latest"
sleep 2
echo 'DEBUG=1' >> "$OMENV"
docker restart -t 1 "$P-updater" > /dev/null
release
until_true "any('only its own change put back' in l for l in d.get('log', [])) and s.get('result') != 'running'" 180 &&
  ok "at its start its own change put back" || bad "not put back: $(val "s.get('result')")"
[ "$(envv)" = '"edge"' ] && grep -qx 'DEBUG=1' "$OMENV" && ok "only its own line, the one saved meanwhile stays" || bad "its .env: $(cat "$OMENV")"
[ "$(perm "$OMENV")" = "$mode" ] && [ ! -e "$OMENV.before-update" ] && ok "with its owner and rights, no copy left" || bad "the file: $(perm "$OMENV")"
runs_on "$P-om" "$REG/$P-om:o5" && ok "OpenMower as it ran" || bad "OpenMower runs $(docker inspect -f '{{.Image}}' "$P-om")"
sed -i '/^DEBUG=1$/d' "$OMENV"

say "the night"
move om edge o7
move app 0.0.1 a3n1
updater_img b2 b200000test label && move updater latest b2
# (its window began a minute ago, the container's clock is utc)
since=$(($(date +%s) - 60))
DAY=$(date -u -d "@$since" +%F)
wd=$(date -u -d "@$since" +%u)
post conf "$(printf 'openmower edge\nopenmower_auto 1\nplanner_auto 1\n%s_auto 1\nat %s\ndays %s' "$APP3" "$(date -u -d "@$since" +%H:%M)" $((wd % 7 + 1)))" > /dev/null
t0=$(date +%s)
post room > /dev/null
until_true "not d.get('requested') and not s.get('taken')" 120
sleep 5
[ -z "$(val "s.get('night_done')")" ] && [ "$(val "int(s.get('${APP3}_at', 0)) < $t0")" = True ] && ok "not on a day it isn't set for" ||
  bad "on another day: $(val "s.get('night_done')"), $(val "s.get('$APP3')")"
mower out
post conf "days $wd" > /dev/null
post room > /dev/null
until_true "s.get('updater', '').startswith('restarting')" 300 && ok "with the mower out it waits, and updates itself meanwhile" ||
  bad "itself at night: $(val "s.get('updater')"), result $(val "s.get('result')")"
mower docked
until_true "s.get('updater', '').startswith('updated') and 'b200000' in s.get('updater_running', '')" 300 && ok "its new version runs" ||
  bad "itself: $(val "s.get('updater')") $(val "s.get('updater_running')")"
until_true "s.get('night_done') == '$DAY' and s.get('result') != 'running'" 420 && ok "the mower back, the night's run" ||
  bad "the night: $(val "s.get('night_done')"), result $(val "s.get('result')")"
[ "$(log_has 'waiting (night)')" = True ] && ok "it had waited" || bad "its log doesn't say it waited"
runs_on "$P-om" "$REG/$P-om:o7" && runs_on "$P-app3" "$REG/$P-app:a3n1" && ok "OpenMower and the app updated" ||
  bad "OpenMower $(val "s.get('openmower')"), the app $(val "s.get('$APP3')")"
[ "$(said planner)" = updated ] && [ "$(val "s.get('planner_base_id')")" = "$(id_of "$REG/$P-om:o7")" ] &&
  ok "the planner built on it, once (not again as a part of the night)" || bad "the planner: $(val "s.get('planner')")"

say "a restart in its window"
move app 0.0.1 a3n2
updater_img b3 b300000test label && move updater latest b3
at=$(val "s.get('${APP3}_at')")
t0=$(date +%s)
docker restart -t 1 "$P-updater" > /dev/null
until_true "int(s.get('checked', 0)) >= $t0" 120
sleep 10
runs_on "$P-app3" "$REG/$P-app:a3n1" && [ "$(val "s.get('${APP3}_at')")" = "$at" ] && ok "the night's run isn't done again" ||
  bad "again: $(val "s.get('$APP3')")"
case $(val "s.get('updater_running', '')") in b200000*) ok "nor its own update" ;; *) bad "itself again: $(val "s.get('updater_running')")" ;; esac
move updater latest b2

say "the night without an answer from the registry"
in_updater "status night_done; status self_night"
registry_down
t0=$(date +%s)
docker restart -t 1 "$P-updater" > /dev/null
until_true "s.get('night_done') == '$DAY' and int(s.get('${APP3}_at', 0)) >= $t0 and s.get('result') != 'running'" 300 ||
  bad "the night: $(val "s.get('night_done')"), result $(val "s.get('result')")"
[ "$(val "s.get('$APP3')")" = "error registry" ] && [ "$(val "s.get('openmower')")" = "error registry" ] &&
  runs_on "$P-app3" "$REG/$P-app:a3n1" && runs_on "$P-om" "$REG/$P-om:o7" && ok "not taken for built here: an error, nothing changed" ||
  bad "the app $(val "s.get('$APP3')"), OpenMower $(val "s.get('openmower')")"
r=$(val "' '.join(p['id'] + ':' + p['kind'] for p in d.get('parts', []) if p['id'] in ('openmower', 'mowbite', 'planner'))")
[ "$r" = "openmower:openmower mowbite:image planner:build" ] && ok "what each part is stays" || bad "found: $r"
[ "$(said "${APP3}_available")" = unknown ] && ok "no telling whether there's something new" || bad "its card: $(val "s.get('${APP3}_available')")"
registry_up
post conf "$(printf 'openmower_auto 0\nplanner_auto 0\n%s_auto 0\nat %s\ndays daily' "$APP3" "$FAR")" > /dev/null

say "making room"
dir=$WORK/img/junk
mkdir -p "$dir"
printf 'FROM busybox:1.37-musl\nLABEL mbt.run=%s mbt.junk=%s\n' "$P" "$(date +%s)" > "$dir/Dockerfile"
docker build -q -t "$P-junk:1" "$dir" > /dev/null
junk=$(id_of "$P-junk:1" | sed 's/^sha256://' | cut -c1-12)
post room > /dev/null
until_true "not d.get('requested') and not s.get('taken') and any(i['id'] == '$junk' for i in d.get('room', {}).get('items', []))" 120 &&
  ok "an image nothing uses is on the list" || bad "not on the list: $junk"
rb=$(val "next((i['id'] + ' ' + r for i in d.get('room', {}).get('items', []) for r in i['refs'].split(',') if ':rb-$APP-' in r), '')")
if [ -n "$rb" ]; then
  # (as if the app had just been restarted on a new version and not seen running yet)
  in_updater "status pending_$APP ${rb#* } $REG/$P-app:latest"
  post room > /dev/null
  until_true "not d.get('requested') and not s.get('taken')" 60
  sleep 2
  until_true "not d.get('requested') and not s.get('taken')" 60
  [ "$(val "any(i['id'] == '${rb%% *}' for i in d.get('room', {}).get('items', []))")" = False ] &&
    ok "the way back of an app not seen running yet isn't on it" || bad "on the list: ${rb#* }"
  in_updater "status pending_$APP"
else
  bad "no way back of the app on the list"
fi
post "free=img:$junk" > /dev/null
until_sh '! docker image inspect "$P-junk:1" > /dev/null 2>&1' 120 && ok "deleted when asked" || bad "not deleted"
[ "$(post free=img:000000000000)" = bad ] && ok "only what's on the list" || bad "something not on the list taken"

say "built from github with pull_policy: build"
if docker compose -f "$STACKS/build/compose.yaml" up -d > /dev/null 2>&1; then
  post check > /dev/null
  until_true "any(p['container'] == '$P-build' and p['kind'] == 'build' for p in d.get('parts', []))" 120 || bad "not found as a build"
  BUILD=$(part "$P-build")
  post "now=$BUILD" > /dev/null
  until_true "s.get('$BUILD', '').split(' ')[0] in ('updated', 'rolled_back', 'error') and s.get('result') != 'running'" 600
  r=$(val "s.get('$BUILD')")
  case $r in updated*) ok "updated without going back" ;; *) bad "build: $r" ;; esac
  runs_on "$P-build" "$P-build:edge" && ok "runs the image it checked" || bad "runs another image than its tag"

  say "built again with the same content"
  # (what it built last forgotten: it builds again, the same as what runs, which only gets another id)
  in_updater "status ${BUILD}_built; status $BUILD"
  ran=$(docker inspect -f '{{.Image}} {{.State.StartedAt}}' "$P-build")
  post "now=$BUILD" > /dev/null
  until_true "s.get('$BUILD') and s.get('result') != 'running'" 600
  r=$(val "s.get('$BUILD')")
  case $r in updated*) ok "updated without going back" ;; *) bad "same content: $r" ;; esac
  [ "$(docker inspect -f '{{.Image}} {{.State.StartedAt}}' "$P-build")" = "$ran" ] && ok "not started again" || bad "started again"
  [ "$(log_has 'the same image as before')" = True ] && ok "its log says so" || bad "its log doesn't say the same image"

  say "the image it runs gone"
  # built again by hand: its tag goes on to the same content with another id, docker drops the one the container runs
  docker compose -f "$STACKS/build/compose.yaml" build > /dev/null 2>&1
  docker image inspect "$(docker inspect -f '{{.Image}}' "$P-build")" > /dev/null 2>&1 && echo "   (this docker kept the image, the case runs as a plain one)"
  in_updater "status ${BUILD}_built; status ${BUILD}_image; status $BUILD"
  post "now=$BUILD" > /dev/null
  until_true "s.get('$BUILD') and s.get('result') != 'running'" 600
  r=$(val "s.get('$BUILD')")
  case $r in updated*) ok "updated, its tag as the way back" ;; *) bad "image gone: $r" ;; esac
  docker image inspect "$(docker inspect -f '{{.Image}}' "$P-build")" > /dev/null 2>&1 && ok "runs on an image that's there" ||
    bad "still on an image that's gone"
  runs_on "$P-build" "$P-build:edge" && ok "the one its tag names" || bad "runs another image than its tag"
else
  bad "the build stack doesn't come up (github?)"
fi

say "itself"
t0=$(date +%s)
post self > /dev/null
until_true "s.get('updater', '').startswith('current') and int(s.get('updater_at', 0)) >= $t0" 120 && ok "up to date: nothing downloaded" ||
  bad "itself: $(val "s.get('updater')")"
updater_img c c000000test broken && move updater latest c && forget updater:c
# (its download held: a request comes in while it updates itself)
hold updater
post self > /dev/null
until_true "s.get('progress', '').startswith('updater ')" 60 || bad "it never got to its download"
sleep 2
post "now=$APP3" > /dev/null
release
until_true "s.get('updater', '').startswith('rolled_back') and 'b200000' in s.get('updater_running', '')" 420 &&
  ok "a broken version of itself: back on the one before" || bad "broken self: $(val "s.get('updater')") $(val "s.get('updater_running')")"
until_true "int(s.get('${APP3}_at', 0)) >= int(s.get('updater_at', 0)) and s.get('result') != 'running'" 240 &&
  runs_on "$P-app3" "$REG/$P-app:a3n2" && ok "a request meanwhile waited for the one that came up" ||
  bad "the request: $(val "s.get('$APP3')"), at $(val "s.get('${APP3}_at')")"
post self > /dev/null
until_true "s.get('updater', '').startswith('skipped_failed')" 60 && ok "not tried again" || bad "itself again: $(val "s.get('updater')")"
[ "$(docker inspect -f '{{.State.Running}}' "$P-updater" 2> /dev/null)" = true ] && ok "and it runs" || bad "the updater doesn't run any more"

say "done"
finished=1
if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
[ $fails -eq 0 ]
