#!/bin/sh
# the updater against a mower of its own on this docker: a registry, a broker with a made-up mower state, OpenMower with
# its .env, MowBite, the planner built on OpenMower, small apps in stacks. it starts from the updater that's out
# (ghcr.io, the run fails without it; MBT_FROM=checkout: from a build of this checkout) and updates that to this
# checkout (MBT_IMAGE: to that image, the ci's) the way each mower does, then each case through its interface, the way
# its page and MowBite use it, and a look at what runs and at the files it changed. only what's labelled mbt.run=<id> or
# named <id>-* is made here (MBT_ID, default mbt) and cleared away afterwards, also when it's stopped; a second run at
# the same time needs another MBT_ID and other MBT_*_PORTs. its folder in TMPDIR (or MBT_WORK, kept then), on a disk
# with 1.5 GB free. needs docker with compose and buildx, curl, python3 and the internet (ghcr.io, github for the builds
# and the stable channel). about 45 minutes, most of it waiting for versions that don't start
set -u
cd "$(dirname "$0")/.." || exit 1
SRC=$PWD
P=${MBT_ID:-mbt}
REG=127.0.0.1:${MBT_REGISTRY_PORT:-5077}
MQTT=${MBT_MQTT_PORT:-51877}
PAGE=${MBT_PAGE_PORT:-58077}
FEED=${MBT_FEED_PORT:-58177}
WORK=${MBT_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/mbt.XXXXXX")}
# the planner's repository on the made-up github (test/github.py): this one's
GH=$WORK/feed/gh/mkaaaaaay/mowbite-updater
STACKS=$WORK/stacks
STATE=$STACKS/updater/.updater
OMENV=$STACKS/om/.env
API=http://127.0.0.1:$PAGE/cgi-bin/updater
# the updater every mower runs right now: the update to this checkout starts from it
OUT=ghcr.io/mkaaaaaay/mowbite-updater:latest
fails=0
finished=
gate=
feed=

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
log_has() {
  st | N="$1" python3 -c "import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(any(os.environ['N'] in l for l in d.get('log', [])))" 2> /dev/null
}
# what its card says last, its first word
said() { val "s.get('$1', '').split(' ')[0]"; }
# the rollback tags of a part in the app's repository
backs() { docker images --format '{{.Tag}}' "$REG/$P-app" | grep -c "^rb-$1-"; }
# a file's owner and rights, and the version in OpenMower's .env
perm() { stat -c %u:%g:%a "$1"; }
envv() { sed -n 's/^VERSION=//p' "$OMENV"; }
# its status written the way it writes it
in_updater() { docker exec "$P-updater" sh -c ". /lib.sh; $1"; }

# in the updater's folder of the data it kept (only root may look there), and in MowBite's /data
in_kept() { docker exec "$P-updater" sh -c "cd '$STATE/data' 2> /dev/null && $1"; }
in_data() { docker run --rm --label "mbt.run=$P" -v "$P-mowbite_data:/data" busybox:1.37-musl sh -c "$1"; }
# a part's copies of its data, newest first, and the newest
kept_of() { in_kept "ls -d $1-* 2> /dev/null" | sort -t- -k2 -nr; }
newest_of() { kept_of "$1" | grep -v '\.new$' | head -n1; }

# the broker, as MowBite's scheduler and the updater use it: what it keeps on a topic, a message kept on it
kept() { docker exec "$P-broker" mosquitto_sub -h 127.0.0.1 -t "$1" -C 1 -W 2 2> /dev/null; }
keep() {
  t=$1
  shift
  docker exec "$P-broker" mosquitto_pub -h 127.0.0.1 -t "$t" -r "$@"
}

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
  docker volume ls -q --filter "name=^$P-" | xargs -r docker volume rm > /dev/null 2>&1
  [ -n "$gate" ] && kill "$gate" 2> /dev/null
  [ -n "$feed" ] && kill "$feed" 2> /dev/null
  # (its folder in the stack is root's, the updater runs as root)
  [ -z "${MBT_WORK:-}" ] && docker run --rm --label "mbt.run=$P" -v "$WORK:/work" busybox:1.37-musl rm -rf /work/stacks > /dev/null 2>&1
  [ -z "${MBT_WORK:-}" ] && rm -rf "$WORK"
}

# a test image <repo>:<tag> in the registry: run (says ready and stays, with /start for a planner built on it), crash
# (ends at once), nostart (can't be started), bare (stays, nothing for a planner), mowbite (says its version $4), raise
# and touch (MowBite that changes a file in /data and doesn't answer, raise its schema too).
# OpenMower's with a rostopic that gives its emergency's reason from the file state/reason-<tag> and a rosparam that gives
# xbot_monitoring's parameters from state/xbot.yaml (none with state/xbot-fail)
img() {
  dir=$WORK/img/$1-$2
  mkdir -p "$dir"
  if [ "$1" = om ]; then
    printf '#!/bin/sh\nexec sh "$@"\n' > "$dir/bash"
    : > "$dir/setup.bash"
    printf '#!/bin/sh\nprintf '"'"'"%%s"\\n---\\n'"'"' "$(cat /state/reason-%s 2> /dev/null)"\n' "$2" > "$dir/rostopic"
    printf '#!/bin/sh\n[ -e /state/xbot-fail ] && exit 1\ncat /state/xbot.yaml 2> /dev/null\nexit 0\n' > "$dir/rosparam"
  fi
  {
    echo 'FROM busybox:1.37-musl'
    echo "LABEL mbt.run=$P mbt.version=$1:$2"
    case $3 in
    run) printf 'RUN printf "#!/bin/sh\\necho ready\\necho MowBite Planner answers\\nexec sleep 100000\\n" > /start && chmod 755 /start\nCMD ["/start"]\n' ;;
    crash) echo 'CMD ["sh", "-c", "exit 1"]' ;;
    nostart) echo 'CMD ["/nothing"]' ;;
    bare) echo 'CMD ["sleep", "100000"]' ;;
    raise) echo 'CMD ["sh", "-c", "echo 2 > /data/schema; echo changed > /data/notify.conf; exec sleep 100000"]' ;;
    touch) echo 'CMD ["sh", "-c", "echo changed > /data/notify.conf; exec sleep 100000"]' ;;
    mowbite)
      cat > "$dir/version" << EOF
#!/bin/sh
printf 'Content-Type: application/json\r\n\r\n'
[ -e /tmp/quiet ] || printf '{"version":"$4"}'
EOF
      printf 'COPY --chmod=755 version /www/cgi-bin/version\nCMD ["httpd", "-f", "-p", "8080", "-h", "/www"]\n'
      ;;
    esac
    [ "$1" = om ] && printf 'COPY --chmod=755 bash rostopic rosparam /bin/\nCOPY setup.bash /opt/open_mower_ros/devel/\n'
  } > "$dir/Dockerfile"
  docker build -q -t "$REG/$P-$1:$2" "$dir" > /dev/null && docker push -q "$REG/$P-$1:$2" > /dev/null
}
# an image only in the registry, not here: its download has something to hold (gate.py)
forget() { docker rmi "$REG/$P-$1" > /dev/null 2>&1; }
# the planner's repository on the made-up github: its branch main and tags (<main> [<tag> <commit>]...: a tag as git
# tells an annotated one, its own id and its commit under ^{}), its releases' feed (the tags, newest first) and where
# /releases/latest sends (gh_releases <tags> [-- <latest>], none: to the list of releases). gh_releases off: no answer
gh_refs() {
  local l
  {
    printf '001e# service=git-upload-pack\n0000'
    for l in "$1 HEAD" "$1 refs/heads/main"; do printf '%04x%s\n' $((${#l} + 5)) "$l"; done
    shift
    while [ $# -ge 2 ]; do
      for l in "$(printf '%s' "$1" | md5sum | cut -c1-32)00000000 refs/tags/$1" "$2 refs/tags/$1^{}"; do printf '%04x%s\n' $((${#l} + 5)) "$l"; done
      shift 2
    done
    printf '0000'
  } > "$GH.git/info/refs"
}
gh_releases() {
  local t latest=
  if [ "${1:-}" = off ]; then
    rm -f "$GH/releases.atom" "$GH/releases/latest"
    return
  fi
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<feed xmlns="http://www.w3.org/2005/Atom">'
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
      printf '<entry><link rel="alternate" type="text/html" href="https://github.com/mkaaaaaay/mowbite-updater/releases/tag/%s"/></entry>\n' "$1"
      shift
    done
    echo '</feed>'
  } > "$GH/releases.atom"
  [ "${1:-}" = -- ] && latest=tag/$2
  echo "$latest" > "$GH/releases/latest"
}
# a tag in the registry moved to the image of another, nothing changed here (as on a mower: only the updater pulls)
move() { docker buildx imagetools create -t "$REG/$P-$1:$2" "$REG/$P-$1:$3" > /dev/null 2>&1; }
publish() { move app latest "$1"; }
# the updater built from this checkout (<tag> <revision>), or on top of that build (<tag> <revision> broken|label|mute:
# one that doesn't start, one with a release's version as a fourth, one that runs without its page)
updater_img() {
  # (the new version b is the image in MBT_IMAGE when it's set, the one the ci ships, with the test's labels on it)
  if [ -z "${3:-}" ] && { [ -z "${MBT_IMAGE:-}" ] || [ "$1" != b ]; }; then
    docker build -q --label "mbt.run=$P" --label "org.opencontainers.image.revision=$2" -t "$REG/$P-updater:$1" . > /dev/null
  else
    dir=$WORK/img/updater-$1
    mkdir -p "$dir"
    {
      if [ -z "${3:-}" ]; then echo "FROM $MBT_IMAGE"; else echo "FROM $REG/$P-updater:b"; fi
      echo "LABEL mbt.run=$P org.opencontainers.image.revision=$2"
      [ -n "${4:-}" ] && echo "LABEL org.opencontainers.image.version=$4"
      [ "${3:-}" = broken ] && echo 'ENTRYPOINT ["sh", "-c", "exit 1"]'
      [ "${3:-}" = mute ] && echo 'RUN rm /usr/sbin/httpd'
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
# OpenMower's releases on github, as their feed: none until its case writes them. and the planner's github (gh/): its
# repository's main as on github, no releases until their case
mkdir -p "$WORK/feed" "$GH.git/info" "$GH/releases"
python3 "$SRC/test/github.py" "$WORK/feed" "$FEED" > /dev/null 2>&1 &
feed=$!
MAIN=$(timeout 60 git ls-remote https://github.com/mkaaaaaay/mowbite-updater.git refs/heads/main | cut -f1)
[ ${#MAIN} = 40 ] || { bad "no main on github"; exit 1; }
gh_refs "$MAIN"
gh_releases

# the version it starts from, and this checkout
if [ "${MBT_FROM:-}" = checkout ]; then
  from="from a build of this checkout"
  updater_img a a000000test || { bad "the updater doesn't build"; exit 1; }
elif timeout 600 docker buildx imagetools create -t "$REG/$P-updater:a" "$OUT" > /dev/null 2>&1; then
  from="from $OUT"
else
  # (the mowers update from that one, a test from anything else says nothing about them)
  bad "$OUT can't be had, MBT_FROM=checkout starts from a build of this checkout instead"
  exit 1
fi
updater_img b b000000test || { bad "the updater doesn't build"; exit 1; }
move updater latest a
# the newest release of MowBite, the stable channel of the apps here
REL=$(curl -sI -m 15 https://github.com/mkaaaaaay/mowbite/releases/latest | tr -d '\r' |
  sed -n 's|^[Ll]ocation: .*/releases/tag/v\{0,1\}\([^[:space:]?]*\).*|\1|p' | tail -n1)
for v in v1 v2 v3 v4 v5 dl a3old a3new a3n1 a3n2; do img app "$v" run || bad "app:$v doesn't build"; done
for v in o1 o2 o3 o4 o6 o7 o8 o9; do img om "$v" run || bad "om:$v doesn't build"; done
img app broken crash && img om ox nostart && img om o5 bare && img mowbite m1 mowbite 9.0.0-beta.1 || bad "a test image doesn't build"
img mowbite m2 mowbite 9.0.0-beta.2 && img mowbite m3 raise && img mowbite m4 touch || bad "a test image of MowBite doesn't build"
# (made a second later than all before them: the first of another version line)
sleep 1
img om f1 run && img om f2 run || bad "om:f1 or f2 doesn't build"
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
      UPDATER_HOLD_WAIT: "2"
      UPDATER_CALIB_WAIT: "20"
      OPENMOWER_CONTAINER: $P-om
      OM_RELEASES: http://127.0.0.1:$FEED/releases.atom
      PLANNER_GITHUB: http://127.0.0.1:$FEED/gh
      MOWBITE_CONTAINER: $P-mowbite
      PLANNER_CONTAINER: $P-planner
      PRUNE: "0"
      TEST_LABEL: mbt.run=$P
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
    volumes:
      - $WORK/state:/state:ro
      - $WORK/params:/data/params
      - $WORK/ros:/data/ros
    labels:
      mbt.run: $P
EOF
printf '# made-up OpenMower\nVERSION="v1"\nOM_PLANNER=external\n' > "$OMENV"
# its mower_params.yaml shaped like OpenMower 2's, with what a calibration may write and what it never may
mkdir -p "$WORK/params"
cat > "$WORK/params/mower_params.yaml" << 'PARAMS'
# made-up mower_params.yaml
ll:
  board: "YardForce"
  services:
    gps:
      baud_rate: 921600   # the receiver's
    diff_drive:
      wheel_distance_m: 0.3556  # measured on another model
      ticks_per_m: 2025.0
  list: [1, 2, 3]
xbot_positioning:
  antenna_offset_x: -0.10
  antenna_offset_y: 0.0
mower_logic:
  docking_approach_distance: 1.5
PARAMS
chmod 644 "$WORK/params/mower_params.yaml"
# its map, as OpenMower keeps it in /data/ros
mkdir -p "$WORK/ros"
echo '{"areas":["front"]}' > "$WORK/ros/map.json"
chmod 640 "$WORK/ros/map.json"
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
        COPY updater.sh /mbt-updater.sh
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
    volumes:
      - data:/data
    labels:
      mbt.run: $P
      mowbite.update.stable: github:mkaaaaaay/mowbite
volumes:
  data:
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
# MowBite's /data as the app keeps it: its schema, a push token, its stats, owned by its user
docker exec "$P-mowbite" sh -c 'echo 1 > /data/schema && printf "topic t\ntoken tok-data-31337\n" > /data/notify.conf && chmod 600 /data/notify.conf &&
  mkdir -p /data/stats && echo "1 2 3" > /data/stats/hours && chown -R 1000:1000 /data' || bad "MowBite's /data can't be filled"
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
# (the ci's build of main is labelled sha-<commit>, that's no release: none then, a tag's build has its own)
[ "$(val "s.get('updater_release', 'v0')[1:2].isdigit()")" = True ] && ok "a build of main shows no release" ||
  bad "its release: $(val "s.get('updater_release')")"
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
# is done again. (how long it takes is a step of the look, a step may wait for its registry. the planner's github slow
# meanwhile: a look here can be over within a second)
# (one still running before this one is over first: its end isn't this look's)
: > "$WORK/feed/slow"
until_true "not s.get('looking')" 60
sleep 3
until_true "not s.get('looking')" 60
c0=$(val "s.get('checked', '')")
t1=$(date +%s)
post check > /dev/null
until_true "s.get('looking')" 30
post room > /dev/null
t2=$(date +%s)
until_true "not d.get('requested')" 120 && [ "$(val "s.get('checked', '')")" = "$c0" ] &&
  ok "a request while it looks is taken at once, the look stops for it ($(($(date +%s) - t2)) s)" ||
  bad "a request while it looks waited: checked $(val "s.get('checked')") (before it $c0), the look from $t1"
rm -f "$WORK/feed/slow"
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
# (by each digest it has here: with docker's older image store one pushed under two tags has two)
d=$(docker buildx imagetools inspect "$REG/$P-app:latest" --format '{{.Manifest.Digest}}' 2> /dev/null)
[ -n "$d" ] && [ "$(val "{'$(id_of "$REG/$P-app:broken")', '$d'} <= set(s.get('${APP}_failed', '').split())")" = True ] &&
  ok "the broken one is left out, by its id and its digest" || bad "left out: $(val "s.get('${APP}_failed')"), the registry has $d"
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

say "data: kept before an update"
move mowbite latest m2
post now=mowbite > /dev/null
until_true "s.get('mowbite', '').startswith('updated') and s.get('result') != 'running'" 180 && runs_on "$P-mowbite" "$REG/$P-mowbite:m2" &&
  ok "MowBite updated to m2" || bad "MowBite: $(val "s.get('mowbite')"), runs $(docker inspect -f '{{.Image}}' "$P-mowbite")"
K1=$(newest_of mowbite)
r=$(in_kept "stat -c %a . '$K1' && cat '$K1/why' '$K1/1.schema' && (cd '$K1' && sha256sum -c -s sha256 && echo sums) && tar -xOf '$K1/1.tar' ./notify.conf | grep -c tok-data-31337" | tr '\n' ' ')
[ -n "$K1" ] && [ "$r" = "700 700 update 1 sums 1 " ] && ok "its /data kept as a tar with its schema and sha256, only root may look" || bad "kept: $K1, $r"
[ "$(kept_of mowbite | wc -l)" -eq 1 ] && ok "one copy" || bad "copies: $(kept_of mowbite | tr '\n' ' ')"
r=$(curl -s -m 10 "$API")
[ "$(val "[(k['part'], k['why'], k['what']) for k in d.get('data', [])]")" = "[('mowbite', 'update', '.')]" ] && ok "its page lists it" ||
  bad "the list: $(val "d.get('data')")"
case $r in *tok-data-31337*) bad "its answer has what's kept" ;; *) ok "its answer has nothing of what's kept" ;; esac
n=0
for u in ".updater/data/$K1/1.tar" "../.updater/data/$K1/1.tar" "cgi-bin/../../$STATE/data/$K1/1.tar" "$STATE/data/$K1/1.tar" "%2e%2e/%2e%2e/$STATE/data/$K1/sha256"; do
  c=$(curl -s -m 10 --path-as-is -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PAGE/$u")
  [ "$c" = 200 ] && n=$((n + 1))
done
[ $n -eq 0 ] && ok "the copies can't be had over its port" || bad "$n of its paths handed out a copy"

say "data: a new version that raises its schema doesn't run"
move mowbite latest m3
post now=mowbite > /dev/null
until_true "s.get('mowbite', '').startswith('rolled_back') and s.get('result') != 'running'" 400 && runs_on "$P-mowbite" "$REG/$P-mowbite:m2" &&
  [ "$(val "s.get('mowbite', '').split(' ')[1:]")" = "['data']" ] && ok "back on m2 with its data from before the update" ||
  bad "MowBite: $(val "s.get('mowbite')"), runs $(docker inspect -f '{{.Image}}' "$P-mowbite")"
[ "$(in_data 'cat /data/schema; grep -c tok-data-31337 /data/notify.conf; stat -c %u:%a /data/notify.conf' | tr '\n' ' ')" = "1 1 1000:600 " ] &&
  ok "schema 1 and the push token again, with owner and rights" || bad "/data: $(in_data 'cat /data/schema /data/notify.conf' | tr '\n' ' ')"
K2=$(newest_of mowbite)
r=$(in_kept "cat '$K2/why' '$K2/1.schema' && tar -xOf '$K2/1.tar' ./notify.conf" | tr '\n' ' ')
[ "$r" = "put 2 changed " ] && ok "what the new version made of it kept first, nothing gone" || bad "kept before putting back: $K2, $r"
[ "$(kept_of mowbite | wc -l)" -eq 2 ] && ok "the newest two copies" || bad "copies: $(kept_of mowbite | tr '\n' ' ')"
[ -z "$(val "s.get('data_put')")" ] && ok "nothing left to finish" || bad "data_put: $(val "s.get('data_put')")"

say "data: a new version with the same schema doesn't run"
move mowbite latest m4
t0=$(date +%s)
post now=mowbite > /dev/null
until_true "s.get('mowbite', '').startswith('rolled_back') and int(s.get('mowbite_at', 0)) >= $t0 and s.get('result') != 'running'" 400 &&
  runs_on "$P-mowbite" "$REG/$P-mowbite:m2" && [ "$(val "s.get('mowbite')")" = rolled_back ] && ok "back on m2, its data left as it is" ||
  bad "MowBite: $(val "s.get('mowbite')"), runs $(docker inspect -f '{{.Image}}' "$P-mowbite")"
[ "$(in_data 'cat /data/notify.conf')" = changed ] && ok "nothing put back without a higher schema" || bad "/data: $(in_data 'cat /data/notify.conf')"
K3=$(newest_of mowbite)
[ "$(in_kept "cat '$K3/why'")" = update ] && [ "$(kept_of mowbite | wc -l)" -eq 2 ] && ok "kept before it, still two copies" ||
  bad "copies: $(kept_of mowbite | tr '\n' ' ')"
move mowbite latest m2

say "data: the updater stopped while it put it back"
# (as a stop halfway leaves it: MowBite stopped, part of /data gone, something half unpacked, a copy half written)
docker stop -t 1 "$P-updater" > /dev/null
docker stop -t 1 "$P-mowbite" > /dev/null
in_data 'rm -rf /data/stats && echo junk > /data/junk && mkdir -p /data/.updater-put && echo half > /data/.updater-put/notify.conf'
docker run --rm --label "mbt.run=$P" -v "$STACKS:$STACKS" -e "STATE_DIR=$STATE" --entrypoint sh "$REG/$P-updater:b" -c \
  ". /lib.sh; status data_put mowbite '$STATE/data/$K2' '$STATE/data/$K3' && mkdir -m 700 '$STATE/data/mowbite-1.new' && echo x > '$STATE/data/mowbite-1.new/1.tar'"
docker start "$P-updater" > /dev/null
until_true "not s.get('data_put') and s.get('alive')" 180 && until_sh 'docker exec "$P-mowbite" true 2> /dev/null' 60 &&
  ok "at its next start it put it back again, MowBite runs" || bad "after the restart: data_put $(val "s.get('data_put')"), MowBite $(docker inspect -f '{{.State.Status}}' "$P-mowbite")"
[ "$(in_data 'cat /data/notify.conf /data/stats/hours; ls -A /data' | tr '\n' ' ')" = "changed 1 2 3 notify.conf schema stats " ] &&
  ok "/data whole as it was kept, nothing half of it" || bad "/data: $(in_data 'ls -A /data' | tr '\n' ' ')"
[ "$(val "[k['at'] for k in d.get('data', []) if k['at'] == 1]")" = "[]" ] && ok "a copy half written isn't on its list" || bad "listed: $(val "d.get('data')")"

say "data: put back by hand"
mower out
r=$(post "data=$K3")
until_true "s.get('mowbite') == 'error not_docked'" 60 && [ "$(in_data 'cat /data/notify.conf')" = changed ] && ok "not with the mower out" ||
  bad "with the mower out ($r): $(val "s.get('mowbite')")"
mower docked
[ "$(post "data=mowbite-1")$(post "data=nobody-${K3#*-}")$(post "data=mowbite-x;id")$(post "data=../${K3}")" = badbadbadbad ] &&
  ok "only a copy it has" || bad "a copy it doesn't have was taken"
post "data=$K3" > /dev/null
until_true "s.get('mowbite', '').startswith('data_back') and s.get('result') != 'running'" 180 && runs_on "$P-mowbite" "$REG/$P-mowbite:m2" &&
  [ "$(in_data 'grep -c tok-data-31337 /data/notify.conf; cat /data/schema; ls -A /data' | tr '\n' ' ')" = "1 1 notify.conf schema stats " ] &&
  ok "its data from before the last update back, MowBite runs" || bad "by hand: $(val "s.get('mowbite')"), /data $(in_data 'ls -A /data' | tr '\n' ' ')"
[ "$(log_has "doesn't answer after its data")" = False ] && ok "and answers" || bad "it doesn't answer after its data was put back"
K4=$(newest_of mowbite)
[ "$(in_kept "cat '$K4/why' && tar -xOf '$K4/1.tar' ./notify.conf" | tr '\n' ' ')" = "put changed " ] && ok "what it had kept first" ||
  bad "kept before: $K4"
! kept_of mowbite | grep -q '\.new$' && ok "the copy half written is gone" || bad "left: $(kept_of mowbite | tr '\n' ' ')"
# (a copy that doesn't match its sha256: nothing put back)
in_kept "echo x >> '$K4/1.tar'"
post "data=$K4" > /dev/null
until_true "s.get('mowbite') == 'error data_put' and s.get('result') != 'running'" 120 &&
  [ "$(in_data 'grep -c tok-data-31337 /data/notify.conf')" = 1 ] && runs_on "$P-mowbite" "$REG/$P-mowbite:m2" &&
  ok "a copy that changed isn't put back, MowBite runs on" || bad "a changed copy: $(val "s.get('mowbite')")"

say "data: the disk full while it keeps them"
# (its folder on a disk of 2 MB, the same path for the updater and its helpers: an updater of its own for this, /data
# bigger than that. OpenMower 1 GB to spare, MowBite: room enough said, the disk fills up during the tar)
docker volume create --label "mbt.run=$P" --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=2m "$P-small" > /dev/null
SMALL=$(docker volume inspect -f '{{.Mountpoint}}' "$P-small")
in_data 'dd if=/dev/urandom of=/data/big bs=1k count=3072 2> /dev/null'
move mowbite latest m1
small() {
  docker run --rm --label "mbt.run=$P" --network host -v /var/run/docker.sock:/var/run/docker.sock -v "$STACKS:$STACKS" -v "$P-small:$SMALL" \
    -e "STATE_DIR=$SMALL" -e "UPDATER_CONTAINER=$P-updater" -e "MOWBITE_CONTAINER=$P-mowbite" -e "OPENMOWER_CONTAINER=$P-om" -e "MQTT_PORT=$MQTT" \
    -e UPDATER_NO_LOOP=1 -e PRUNE=0 --entrypoint sh "$REG/$P-updater:b" -c "grep '^parts ' '$STATE/status' > '$SMALL/status'; . /updater.sh; $1"
}
r=$(small 'keep_data mowbite update; echo "$?|$(ls -A "$STATE/data" 2> /dev/null)|$(tail -n1 "$LOG")"')
case $r in "1||"*"not enough room"*) ok "not enough room: nothing kept, it says why" ;; *) bad "not enough room: $r" ;; esac
rb=$(docker images --format '{{.Tag}}' "$REG/$P-mowbite" | grep -c '^rb-')
r=$(small 'free_mb() { echo 900; }; MANUAL=1; update_part mowbite; echo "$?|$(get mowbite)|$(ls -A "$STATE/data" 2> /dev/null)|$(df -k "$STATE" | awk "NR == 2 {print \$4}")"')
case $r in
"1|error data||"[1-9]*) ok "the disk full during the tar: nothing kept, nothing left of it, the update not done" ;;
*) bad "the disk full: $r" ;;
esac
runs_on "$P-mowbite" "$REG/$P-mowbite:m2" && [ "$(id_of "$REG/$P-mowbite:latest")" = "$(id_of "$REG/$P-mowbite:m2")" ] &&
  [ "$(docker images --format '{{.Tag}}' "$REG/$P-mowbite" | grep -c '^rb-')" = "$rb" ] && ok "MowBite as it was, its tag on what runs, no way back left over" ||
  bad "MowBite runs $(docker inspect -f '{{.Image}}' "$P-mowbite"), tags $(docker images --format '{{.Tag}}' "$REG/$P-mowbite" | tr '\n' ' ')"
in_data 'rm -f /data/big'
docker volume rm "$P-small" > /dev/null
move mowbite latest m2

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

say "OpenMower, MowBite's schedule starts the mower soon"
# from here OpenMower sends to an external broker too, its prefix without the / (the test's broker under ext/)
cat > "$WORK/state/xbot.yaml" << EOF
external_mqtt_enable: true
external_mqtt_hostname: 127.0.0.1
external_mqtt_password: 'it''s secret'
external_mqtt_port: $MQTT
external_mqtt_topic_prefix: ext
external_mqtt_username: ext
software_version: ''
EOF
post conf 'openmower edge' > /dev/null
soon=$(($(date +%s) + 600))
# (MowBite on the external one: it says it there)
keep ext/mowbite/schedule/next -m "{\"from\":$soon,\"to\":$soon}"
post now=openmower > /dev/null
until_true "s.get('openmower', '') == 'error schedule $soon' and s.get('result') != 'running'" 120 && runs_on "$P-om" "$REG/$P-om:o1" &&
  [ "$(envv)" = '"v1"' ] && ok "left as it is, its card says when the schedule starts it" ||
  bad "openmower: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om"), its .env $(envv)"
keep ext/mowbite/schedule/next -n

say "OpenMower, it runs but its parameters don't come"
touch "$WORK/state/xbot-fail"
post now=openmower > /dev/null
until_true "s.get('openmower', '') == 'error hold' and s.get('result') != 'running'" 120 && runs_on "$P-om" "$REG/$P-om:o1" &&
  [ -z "$(kept mowbite/hold)" ] && ok "left as it is: whether it sends to an external broker too isn't known, nothing held" ||
  bad "openmower: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om"), held: $(kept mowbite/hold)"
rm -f "$WORK/state/xbot-fail"

say "OpenMower, another channel"
post conf 'openmower edge' > /dev/null
# (what the updater says on mowbite/hold meanwhile)
docker exec -d "$P-broker" sh -c 'mosquitto_sub -h 127.0.0.1 -v -t mowbite/hold -t ext/mowbite/hold > /tmp/hold.log'
t0=$(date +%s)
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('updated') and s.get('result') != 'running'" 240 && runs_on "$P-om" "$REG/$P-om:o2" &&
  ok "on edge" || bad "edge: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
u=$(docker exec "$P-broker" sed -n 's/^mowbite\/hold {"until":\([0-9]*\)}$/\1/p' /tmp/hold.log | head -n1)
[ -n "$u" ] && [ "$u" -ge $((t0 + 1500)) ] && [ "$u" -le $(($(date +%s) + 1500)) ] &&
  docker exec "$P-broker" grep -qx "ext/mowbite/hold {\"until\":$u}" /tmp/hold.log &&
  ok "MowBite's schedule held for 25 minutes before the restart, on the mower's broker and under OpenMower's external prefix" ||
  bad "the hold: $(docker exec "$P-broker" cat /tmp/hold.log | tr '\n' '|')"
[ "$(docker exec "$P-broker" grep -cx "mowbite/hold {\"until\":$u}" /tmp/hold.log)" -ge 2 ] &&
  ok "and set again right after the restart (a broker in OpenMower's container forgets it)" || bad "not set again: $(docker exec "$P-broker" cat /tmp/hold.log | tr '\n' '|')"
[ -z "$(kept mowbite/hold)$(kept ext/mowbite/hold)" ] && ok "and no more once it's done" ||
  bad "still held: $(kept mowbite/hold) $(kept ext/mowbite/hold)"
docker exec "$P-broker" pkill mosquitto_sub
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
left=$(val "s.get('openmower_failed', '')")
post now=openmower > /dev/null
if until_true "s.get('openmower', '').startswith('skipped_failed') and s.get('result') != 'running'" 120 && runs_on "$P-om" "$REG/$P-om:o1"; then
  ok "edge isn't taken again"
else
  bad "edge again: $(val "s.get('openmower')")"
  # (what it went by, for a failure on a machine of the ci)
  printf '      %s\n' "docker $(docker info -f '{{.Driver}} {{.ServerVersion}}' 2> /dev/null)" "left out: $left" \
    "edge in the registry: $(docker buildx imagetools inspect "$REG/$P-om:edge" --format '{{.Manifest.Digest}}' 2> /dev/null)" \
    "o2 here: $(docker image inspect -f '{{.Id}} {{join .RepoDigests " "}}' "$REG/$P-om:o2" 2> /dev/null)" \
    "o1 here: $(docker image inspect -f '{{.Id}} {{join .RepoDigests " "}}' "$REG/$P-om:o1" 2> /dev/null)"
  val "chr(10).join(d.get('log', [])[-15:])" | sed 's/^/      /'
fi

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

say "OpenMower, a version that needs newer firmware"
post conf 'openmower edge' > /dev/null
# (two lines: 7.0 with om:o1 as its first release, 7.1 with om:f1, made after all the others)
printf '<feed>\n<link rel="alternate" type="text/html" href="https://github.com/x/y/releases/tag/%s"/>\n</feed>\n' v7.1.0 7.0.0 7.0.1-beta.1 > "$WORK/feed/releases.atom"
move om 7.0.0 o1
move om 7.1.0 f1
move om edge f1
printf 'LATCH, FIRMWARE_INCOMPATIBLE' > "$WORK/state/reason-f1"
t0=$(date +%s)
post check > /dev/null
until_true "int(s.get('checked', 0)) >= $t0 and s.get('openmower_available', '').startswith('yes')" 120 &&
  [ "$(val "s.get('openmower_line')")" = "7.0 7.1" ] && ok "its card says it goes to another version line (7.0 -> 7.1)" ||
  bad "the line: $(val "s.get('openmower_line')"), $(val "s.get('openmower_available')")"
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('rolled_back') and s.get('result') != 'running'" 420 && runs_on "$P-om" "$REG/$P-om:o5" &&
  [ "$(said openmower)" = rolled_back ] && [ "$(val "s.get('openmower', '').split(' ')[-1]")" = firmware ] &&
  ok "the motors kept off: back on the version that ran, its card says it's the firmware" ||
  bad "openmower: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
[ "$(log_has 'it needs newer firmware (openmower update-firmware)')" = True ] && ok "its log says what to do" || bad "nothing in its log"
[ -n "$(val "s.get('openmower_fw')")" ] && [ -z "$(val "s.get('openmower_fw_check')")" ] && ok "left out for the firmware" ||
  bad "for the firmware: $(val "s.get('openmower_fw')"), check $(val "s.get('openmower_fw_check')")"
t0=$(date +%s)
post check > /dev/null
until_true "int(s.get('checked', 0)) >= $t0 and s.get('openmower_available', '').startswith('failed')" 120 &&
  [ -n "$(val "s.get('openmower_fw')")" ] && ok "a look leaves it out, still to be tried again" ||
  bad "after a look: $(val "s.get('openmower_available')"), $(val "s.get('openmower_fw')")"
# (openmower update-firmware)
rm -f "$WORK/state/reason-f1"
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('updated') and s.get('result') != 'running'" 300 && runs_on "$P-om" "$REG/$P-om:f1" &&
  ok "tapped again after the firmware update: it runs" || bad "again: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
[ -z "$(val "s.get('openmower_fw')")" ] && [ -z "$(val "s.get('openmower_fw_check')")" ] && ok "nothing left out for the firmware any more" ||
  bad "still: $(val "s.get('openmower_fw')"), check $(val "s.get('openmower_fw_check')")"

say "OpenMower, the motors off for the firmware already before"
printf 'FIRMWARE_INCOMPATIBLE' > "$WORK/state/reason-f1"
printf 'FIRMWARE_INCOMPATIBLE' > "$WORK/state/reason-f2"
move om edge f2
t0=$(date +%s)
post check > /dev/null
until_true "int(s.get('checked', 0)) >= $t0 and s.get('openmower_available', '').startswith('yes')" 120 &&
  [ -z "$(val "s.get('openmower_line')")" ] && ok "the same version line: nothing said" || bad "the line: $(val "s.get('openmower_line')")"
# (its card says updated from the tap before: this one's result by its time)
t0=$(date +%s)
post now=openmower > /dev/null
until_true "s.get('openmower', '').startswith('updated') and int(s.get('openmower_at', 0)) >= $t0 and s.get('result') != 'running'" 300 &&
  runs_on "$P-om" "$REG/$P-om:f2" &&
  [ "$(log_has 'off for the firmware already')" = True ] && ok "updated, the new version isn't blamed for it" ||
  bad "openmower: $(val "s.get('openmower')"), runs $(docker inspect -f '{{.Image}}' "$P-om")"
rm -f "$WORK/state/reason-f1" "$WORK/state/reason-f2" "$WORK/feed/releases.atom"

say "data: OpenMower's map put back by hand"
O=$(newest_of openmower)
[ "$(in_kept "stat -c %a '$O' && cat '$O/why' && sed 's/.*|//' '$O/what' && tar -xOf '$O/1.tar' map.json" | tr '\n' ' ')" = '700 update map.json mower_params.yaml {"areas":["front"]} ' ] &&
  ok "its map and mower_params.yaml kept before its update" || bad "kept: $O"
mode=$(perm "$WORK/ros/map.json")
echo '{"areas":["changed"]}' > "$WORK/ros/map.json"
soon=$(($(date +%s) + 600))
keep mowbite/schedule/next -m "{\"from\":$soon,\"to\":$soon}"
post "data=$O" > /dev/null
until_true "s.get('openmower', '').startswith('error schedule') and s.get('result') != 'running'" 60 && grep -q changed "$WORK/ros/map.json" &&
  ok "not in the 30 minutes before the schedule may start the mower" || bad "before the schedule: $(val "s.get('openmower')")"
keep mowbite/schedule/next -n
ran=$(docker inspect -f '{{.Image}}' "$P-om")
post "data=$O" > /dev/null
until_true "s.get('openmower', '').startswith('data_back') and s.get('result') != 'running'" 240 &&
  [ "$(cat "$WORK/ros/map.json")" = '{"areas":["front"]}' ] && [ "$(perm "$WORK/ros/map.json")" = "$mode" ] &&
  ok "its map back, with its owner and rights" || bad "by hand: $(val "s.get('openmower')"), $(cat "$WORK/ros/map.json") $(perm "$WORK/ros/map.json")"
[ "$(docker inspect -f '{{.Image}} {{.State.Running}}' "$P-om")" = "$ran true" ] && [ -z "$(kept mowbite/hold)" ] &&
  ok "OpenMower runs again on what it ran, the schedule free again" || bad "OpenMower: $(docker inspect -f '{{.Image}} {{.State.Running}}' "$P-om"), held $(kept mowbite/hold)"
O2=$(newest_of openmower)
[ "$(in_kept "cat '$O2/why' && tar -xOf '$O2/1.tar' map.json" | tr '\n' ' ')" = 'put {"areas":["changed"]} ' ] && ok "the map it had kept first" ||
  bad "kept before: $O2"
[ "$(kept_of openmower | wc -l)" -eq 2 ] && ok "the newest two copies" || bad "copies: $(kept_of openmower | tr '\n' ' ')"

say "the night"
move om edge o7
move app 0.0.1 a3n1
updater_img b2 b200000test label 9.8.7 && move updater latest b2
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
until_true "s.get('updater', '').startswith('restarting')" 300 && [ "$(log_has 'waiting (night)')" = False ] &&
  ok "itself first, also with the mower out" || bad "itself at night: $(val "s.get('updater')"), result $(val "s.get('result')")"
until_true "s.get('updater', '').startswith('updated') and 'b200000' in s.get('updater_running', '')" 300 && ok "its new version runs" ||
  bad "itself: $(val "s.get('updater')") $(val "s.get('updater_running')")"
[ "$(val "s.get('updater_release')")" = v9.8.7 ] && ok "its card shows its release" ||
  bad "its release: $(val "s.get('updater_release')")"
until_true "any('waiting (night)' in l for l in d.get('log', []))" 300 && [ "$(val "s.get('night_done')")" != "$DAY" ] &&
  ok "its new version runs the night, it waits for the dock" || bad "the night with the mower out: $(val "s.get('result')")"
# (it looks again in 10 minutes: started again in its window it doesn't wait for that)
mower docked
docker restart -t 1 "$P-updater" > /dev/null
until_true "s.get('night_done') == '$DAY' and s.get('result') != 'running'" 420 && ok "the mower back, the night's run" ||
  bad "the night: $(val "s.get('night_done')"), result $(val "s.get('result')")"
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

say "a calibration"
PF="$WORK/params/mower_params.yaml"
cp -p "$PF" "$WORK/params.orig"
post check > /dev/null
until_true "'ticks_per_m:ll/services/diff_drive/ticks_per_m:ticks/m:100:10000:2025.0' in s.get('calib_paths', '') and len(s.get('calib_paths', '').split()) == 4" 120 &&
  ok "what it may write, with the file's values" || bad "calib_paths: $(val "s.get('calib_paths')")"
[ "$(post calib "$(printf 'll/services/gps/baud_rate 1\n')")" = bad ] &&
  [ "$(post calib "$(printf 'll/services/diff_drive/ticks_per_m 99999\n')")" = bad ] &&
  [ "$(post calib "$(printf 'll/services/diff_drive/ticks_per_m 2030\nll/services/diff_drive/ticks_per_m 2031\n')")" = bad ] &&
  ok "nothing off its list, out of bounds or twice" || bad "took a path off its list, a value out of bounds or one twice"
was=$(docker inspect -f '{{.State.StartedAt}}' "$P-om")
mower out
[ "$(post calib "$(printf 'll/services/diff_drive/wheel_distance_m 0.3612\nxbot_positioning/antenna_offset_x -0.12\n')")" = ok ] ||
  bad "the calibration wasn't taken"
until_true "s.get('calib', '').startswith('waiting')" 60 && cmp -s "$PF" "$WORK/params.orig" && ok "the mower out: it waits, nothing written" ||
  bad "out: $(val "s.get('calib')")"
mower docked
until_true "s.get('calib', '').startswith('written')" 600 && ok "written once the mower is in the dock" || bad "docked: $(val "s.get('calib')")"
[ "$(diff "$WORK/params.orig" "$PF" | grep -c '^[<>]')" = 4 ] && grep -q '^      wheel_distance_m: 0.3612  # measured on another model$' "$PF" &&
  grep -q '^  antenna_offset_x: -0.12$' "$PF" && ok "only the two values, the comment kept" || bad "the file: $(diff "$WORK/params.orig" "$PF" | tr '\n' ' ')"
[ "$(stat -c '%u:%g %a' "$PF")" = "$(stat -c '%u:%g %a' "$WORK/params.orig")" ] && ok "its owner and mode as before" ||
  bad "owner and mode $(stat -c '%u:%g %a' "$PF")"
[ "$(docker inspect -f '{{.State.StartedAt}}' "$P-om")" != "$was" ] && ok "OpenMower started again on it" || bad "OpenMower not started again"
[ -n "$(val "s.get('calib_backup')")" ] && val "s.get('calib_last', '')" | grep -q 'll/services/diff_drive/wheel_distance_m 0.3556 0.3612' &&
  ok "the copy before and what it wrote, for apps" || bad "backup $(val "s.get('calib_backup')"), last $(val "s.get('calib_last')")"
[ -z "$(kept mowbite/hold)" ] && ok "MowBite's schedule free again" || bad "the schedule still held: $(kept mowbite/hold)"
post calib=back > /dev/null
until_true "s.get('calib', '').startswith('back')" 600 && cmp -s "$PF" "$WORK/params.orig" && ok "back: the file as it was, byte for byte" ||
  bad "back: $(val "s.get('calib')")"
# idle but driven by hand (MowBite OS): busy like mowing, given up after its wait
echo '{"current_state":"IDLE","current_sub_state":"DRIVING","is_charging":false}' > "$WORK/state/robot_state.json"
sleep 2
post calib "$(printf 'll/services/diff_drive/ticks_per_m 2030\n')" > /dev/null
until_true "s.get('calib', '').startswith('waiting') and s.get('mower') == '0 DRIVING'" 60 && ok "driven by hand: busy, it waits" ||
  bad "driven by hand: $(val "s.get('calib')"), mower $(val "s.get('mower')")"
until_true "s.get('calib', '').startswith('error') and s.get('calib', '').endswith('not_docked')" 120 && cmp -s "$PF" "$WORK/params.orig" &&
  ok "given up after its wait, nothing written" || bad "its wait: $(val "s.get('calib')")"
mower docked
# a file it can't change safely: left as it is
printf 'other: &a 1\n' >> "$PF"
cp -p "$PF" "$WORK/params.anchor"
post calib "$(printf 'll/services/diff_drive/ticks_per_m 2030\n')" > /dev/null
until_true "s.get('calib', '').startswith('refused')" 120 && cmp -s "$PF" "$WORK/params.anchor" && ok "an anchor in the file: refused, untouched" ||
  bad "anchor: $(val "s.get('calib')")"
cp -p "$WORK/params.orig" "$PF"

say "the planner's releases"
# (commits of this repository on github: OLD and NEW two before main, NEW's updater.sh differs from main's)
OLD=e99c27c897eb2094d46771bdb6bdf99913346d6a
NEW=5295ea58c10c6561263c26c7d3796c744989326f
mower docked
ran=$(docker inspect -f '{{.Image}}' "$P-planner")
[ "$(val "s.get('planner_built')")" = "$MAIN" ] && ok "built from main so far" || bad "built from $(val "s.get('planner_built')")"
# (a look, and its update by hand: "<what came of it> <what its card says>")
look() {
  local t0
  t0=$(date +%s)
  post check > /dev/null
  until_true "int(s.get('checked', 0)) >= $t0 and s.get('result') != 'running'" 120
  t0=$(date +%s)
  post now=planner > /dev/null
  until_true "int(s.get('planner_at', 0)) >= $t0 and s.get('result') != 'running'" 300
  val "s.get('planner', '').split(' ')[0] + ' ' + s.get('planner_available', '')"
}
gh_refs "$MAIN" v0.1.0-beta.7 "$OLD"
gh_releases v0.1.0-beta.7
[ "$(look)" = "current no main" ] && runs_on "$P-planner" "$ran" && [ "$(val "s.get('planner_stable')")" = no ] &&
  [ -z "$(val "s.get('planner_release')")" ] && ok "only its first tries before 0.2.0: main as before" ||
  bad "first tries: $(val "s.get('planner')") $(val "s.get('planner_available')") stable $(val "s.get('planner_stable')")"
gh_refs "$OLD" v0.1.0-beta.7 "$OLD"
gh_releases off
[ "$(look)" = "error unknown main" ] && runs_on "$P-planner" "$ran" &&
  ok "github without an answer: nothing built, also with main moved on" ||
  bad "no answer: $(val "s.get('planner')") $(val "s.get('planner_available')")"
gh_refs "$OLD" v0.1.0-beta.7 "$OLD" v0.2.0 "$MAIN"
gh_releases v0.2.0 v0.1.0-beta.7 -- v0.2.0
[ "$(look)" = "current no v0.2.0" ] && runs_on "$P-planner" "$ran" && [ "$(val "s.get('planner_release')")" = v0.2.0 ] &&
  [ "$(val "s.get('planner_stable')")" = yes ] && [ "$(val "s.get('planner_built')")" = "$MAIN" ] &&
  ok "its first release on the commit it runs: only the name, not built again, nor from main, which moved on" ||
  bad "v0.2.0: $(val "s.get('planner')") $(val "s.get('planner_available')") release $(val "s.get('planner_release')")"
gh_refs "$OLD" v0.1.0-beta.7 "$OLD" v0.2.0 "$MAIN" v0.3.0-beta.1 "$NEW"
gh_releases v0.3.0-beta.1 v0.2.0 v0.1.0-beta.7 -- v0.2.0
[ "$(look)" = "current no v0.2.0" ] && runs_on "$P-planner" "$ran" && [ "$(val "s.get('planner_built')")" = "$MAIN" ] &&
  [ "$(val "c.get('planner')")" = stable ] && ok "without a channel set the planner stays on stable, its beta isn't built" ||
  bad "default: $(val "s.get('planner')") $(val "s.get('planner_available')") channel $(val "c.get('planner')")"
post conf 'planner beta' > /dev/null
[ "$(look)" = "updated no v0.3.0-beta.1" ] && [ "$(val "s.get('planner_built')")" = "$NEW" ] &&
  [ "$(val "s.get('planner', '').split(' ')[-1]")" = v0.3.0-beta.1 ] && [ "$(val "s.get('planner_release')")" = v0.3.0-beta.1 ] &&
  ok "on beta its highest release, built" || bad "beta: $(val "s.get('planner')") $(val "s.get('planner_available')") built $(val "s.get('planner_built')")"
[ "$(docker cp "$P-planner:/mbt-updater.sh" - 2> /dev/null | tar -xO | md5sum | cut -c1-32)" = c81e0ba66d67ec4ff4d79e3d4af603b3 ] &&
  ok "from exactly its commit" || bad "not built from $NEW"
post conf 'planner stable' > /dev/null
[ "$(look)" = "updated no v0.2.0" ] && [ "$(val "s.get('planner_built')")" = "$MAIN" ] &&
  [ "$(val "s.get('planner_release')")" = v0.2.0 ] && ok "on stable the newest release without a dash" ||
  bad "stable: $(val "s.get('planner')") $(val "s.get('planner_available')") built $(val "s.get('planner_built')")"

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
updater_img e e000000test mute && move updater latest e && forget updater:e
t0=$(date +%s)
post self > /dev/null
until_true "s.get('updater', '').startswith('rolled_back') and int(s.get('updater_at', 0)) >= $t0 and 'b200000' in s.get('updater_running', '')" 420 &&
  [ "$(log_has "didn't come up or didn't answer")" = True ] && ok "a version of itself that runs but doesn't answer its page: back on the one before" ||
  bad "one without its page: $(val "s.get('updater')") $(val "s.get('updater_running')")"

say "update all: itself first"
updater_img d d000000test label && move updater latest d
publish v4
post now > /dev/null
until_true "s.get('updater', '').startswith('updated') and 'd000000' in s.get('updater_running', '')" 420 && ok "itself first, its new version runs" ||
  bad "itself: $(val "s.get('updater')") $(val "s.get('updater_running')")"
until_true "s.get('$APP', '').startswith('updated') and int(s.get('${APP}_at', 0)) >= int((s.get('updater', '') + ' 0 0').split(' ')[1]) and s.get('result') != 'running'" 420 &&
  runs_on "$P-app" "$REG/$P-app:v4" && ok "then the apps, by its new version" ||
  bad "the app: $(val "s.get('$APP')") at $(val "s.get('${APP}_at')"), the updater $(val "s.get('updater')")"
[ -z "$(val "s.get('after_self')")" ] && ok "nothing left waiting for it" || bad "still waiting: $(val "s.get('after_self')")"

say "what a pull by its digest leaves"
# (what OpenMower's way back leaves once its tag moved on: an image with only the digest it was pulled by. prune leaves
# it with containerd, one a container runs on stays)
img app dg run && img app dg2 run || bad "app:dg doesn't build"
dg=$(docker buildx imagetools inspect "$REG/$P-app:dg" --format '{{.Manifest.Digest}}' 2> /dev/null)
dg2=$(docker buildx imagetools inspect "$REG/$P-app:dg2" --format '{{.Manifest.Digest}}' 2> /dev/null)
forget app:dg
forget app:dg2
docker pull -q "$REG/$P-app@$dg" > /dev/null && docker pull -q "$REG/$P-app@$dg2" > /dev/null || bad "not pulled by their digests"
docker run -d --name "$P-pinned" --label "mbt.run=$P" "$REG/$P-app@$dg2" > /dev/null
t0=$(date +%s)
post "now=$APP" > /dev/null
until_true "int(s.get('${APP}_at', 0)) >= $t0 and s.get('result') != 'running' and not s.get('taken')" 180
until_sh '! docker image inspect "$REG/$P-app@$dg" > /dev/null 2>&1' 60 && ok "one with only its digest and nothing on it: gone after the run" ||
  bad "still there: $REG/$P-app@$dg"
docker image inspect "$REG/$P-app@$dg2" > /dev/null 2>&1 && ok "one a container runs on stays" || bad "the one a container runs on is gone"
docker rm -f "$P-pinned" > /dev/null

say "making room: all of it but the ways back"
dir=$WORK/img/junk2
mkdir -p "$dir"
printf 'FROM busybox:1.37-musl\nLABEL mbt.run=%s mbt.junk=%s\n' "$P" "$(date +%s)-2" > "$dir/Dockerfile"
docker build -q -t "$P-junk:2" "$dir" > /dev/null
printf 'FROM busybox:1.37-musl\nLABEL mbt.run=%s mbt.keep=%s\n' "$P" "$(date +%s)" > "$dir/Dockerfile"
docker build -q -t "$P-junk:keep-test" "$dir" > /dev/null
junk=$(id_of "$P-junk:2" | sed 's/^sha256://' | cut -c1-12)
kept=$(id_of "$P-junk:keep-test" | sed 's/^sha256://' | cut -c1-12)
post room > /dev/null
until_true "not d.get('requested') and not s.get('taken') and any(i['id'] == '$junk' for i in d.get('room', {}).get('items', [])) and any(i['id'] == '$kept' and i['kind'] == 'rollback' for i in d.get('room', {}).get('items', []))" 120 &&
  ok "one's own way back (keep-) is on the list as a way back" || bad "keep- not on the list as a way back: $kept"
# (the ways back of this run as they are before: its own rb-, previous and before- tags)
ways_back() { docker images --filter "label=mbt.run=$P" --format '{{.Repository}}:{{.Tag}}' | grep -E ':(rb-|previous$|before-|keep-)' | sort; }
before=$(ways_back)
post free=all > /dev/null
until_sh '! docker image inspect "$P-junk:2" > /dev/null 2>&1' 120 && ok "delete all: what nothing needs goes" || bad "not deleted: $P-junk:2"
until_true "not d.get('requested') and not s.get('taken')" 60
[ -n "$before" ] && [ "$(ways_back)" = "$before" ] && ok "the ways back stay" || bad "ways back before: $(echo "$before" | tr '\n' ' '), after: $(ways_back | tr '\n' ' ')"
docker rmi "$P-junk:keep-test" > /dev/null 2>&1

say "the stacks' containers: a list, a log without access data, a restart"
mkdir -p "$STACKS/talk"
cat > "$STACKS/talk/compose.yaml" << EOF
name: $P-talk
services:
  talk:
    image: busybox:1.37-musl
    container_name: $P-talk
    labels:
      mbt.run: "$P"
    environment:
      API_TOKEN: tok-31337x
      SOME_PASS: 'pa\\ss99x'
    command: ["sh", "-c", "echo 'token tok-31337x'; echo 'get http://anna:geheim7@caster.example/x'; echo 'get http://bob:ge@heim8@caster.example/y'; echo 'password: hunter22'; printf '%s\\n' 'seen pa\\\\ss99x'; echo 'all fine'; exec sleep 3600"]
EOF
docker compose -f "$STACKS/talk/compose.yaml" up -d > /dev/null 2>&1 || bad "the stack talk doesn't come up"
post containers > /dev/null
until_true "any(c['name'] == '$P-talk' and c['state'] == 'running' and c['stack'] == '$P-talk' for c in d.get('containers', [])) and any(c['name'] == '$P-updater' and c['self'] for c in d.get('containers', []))" 120 &&
  ok "the containers of the stacks are listed, itself marked" || bad "not listed: $(val "[c['name'] for c in d.get('containers', [])]")"
post "logs=$P-talk" > /dev/null
until_sh 'curl -s -m 10 "$API?logs" | head -n1 | grep -q "^#$P-talk "' 60 || bad "no log of $P-talk"
logs=$(curl -s -m 10 "$API?logs")
case $logs in
*tok-31337x* | *geheim7* | *heim8* | *hunter22* | *ss99x*) bad "access data in the log: $(echo "$logs" | tail -n 4 | tr '\n' ' ')" ;;
*"all fine"*'***'* | *'***'*"all fine"*) ok "the log without its token, the access in a url and the password" ;;
*) bad "the log: $(echo "$logs" | tail -n 4 | tr '\n' ' ')" ;;
esac
[ "$(post "logs=$P-updater")" = bad ] && [ "$(post "restart=$P-updater")" = bad ] && [ "$(post restart=nobody)" = bad ] &&
  ok "not itself, only containers of the list" || bad "itself or one not listed taken"
before=$(docker inspect -f '{{.State.StartedAt}}' "$P-talk")
mower out
post "restart=$P-talk" > /dev/null
until_true "s.get('restarted', '').startswith('$P-talk refused')" 60 && [ "$(docker inspect -f '{{.State.StartedAt}}' "$P-talk")" = "$before" ] &&
  ok "not restarted while OpenMower drives the mower" || bad "restart while mowing: $(val "s.get('restarted')")"
post "restart=$P-om" > /dev/null
until_true "s.get('restarted', '').startswith('$P-om refused') and s.get('restarted', '').endswith('not_docked')" 60 &&
  ok "OpenMower not restarted out of the dock" || bad "OpenMower out of the dock: $(val "s.get('restarted')")"
mower docked
post "restart=$P-talk" > /dev/null
until_true "s.get('restarted', '').startswith('$P-talk done')" 60 && [ "$(docker inspect -f '{{.State.StartedAt}}' "$P-talk")" != "$before" ] &&
  ok "restarted when asked" || bad "not restarted: $(val "s.get('restarted')")"
# (MowBite OS on the mower: OpenMower never started again next to it)
docker run -d --name "$P-oshost" --label "mbt.run=$P" --label mowbite.os=host busybox:1.37-musl sleep 3600 > /dev/null
post "restart=$P-om" > /dev/null
until_true "s.get('restarted', '').startswith('$P-om refused') and s.get('restarted', '').endswith('os_host')" 60 &&
  ok "OpenMower not restarted next to MowBite OS" || bad "OpenMower next to MowBite OS: $(val "s.get('restarted')")"
docker rm -f "$P-oshost" > /dev/null 2>&1
# (a stopped one isn't started from here)
docker stop -t 1 "$P-talk" > /dev/null
post containers > /dev/null
until_true "any(c['name'] == '$P-talk' and c['state'] == 'exited' for c in d.get('containers', []))" 60
post "restart=$P-talk" > /dev/null
until_true "s.get('restarted', '').startswith('$P-talk refused') and s.get('restarted', '').endswith('stopped')" 60 &&
  [ "$(docker inspect -f '{{.State.Running}}' "$P-talk")" = false ] && ok "a stopped container isn't started" ||
  bad "the stopped one: $(val "s.get('restarted')"), running $(docker inspect -f '{{.State.Running}}' "$P-talk")"

say "done"
finished=1
if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
[ $fails -eq 0 ]
