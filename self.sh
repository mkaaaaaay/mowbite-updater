#!/bin/sh
# the updater's own update (updater.sh, update_self): a container of its own on the image the updater ran so far, so it
# stays while the updater is replaced. $1 the updater's image tag, now on the new image, $2 the tag of the one it ran
# so far. starts it on the new one and sees it come up within three minutes: its status says the new start, then 45 s
# on that same start with its page answering it. else starts it on the one before again and leaves the new one out
. /lib.sh
ref=$1
old=$2
new=$(docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null)
[ -n "$new" ] && docker image inspect "$old" > /dev/null 2>&1 || exit 1
svc=$(label "$ME" service)
# (its start so far: the new one is another start, whatever the clock does meanwhile)
was=$(docker inspect -f '{{.State.StartedAt}}' "$ME" 2>/dev/null)

log "updater: starting its new version"
# (never pulled here: the new image is there, and the one before stays the way back)
# (compose itself failing says nothing about the new version: the one before again, the new one not left out)
if ! compose 300 "$ME" up -d --no-deps --pull never "$svc" > /dev/null 2>&1; then
  log "updater: its new version couldn't be started, the one before stays"
  docker tag "$old" "$ref"
  compose 300 "$ME" up -d --no-deps --pull never "$svc" > /dev/null 2>&1
  exit 1
fi
# (its page asked inside it, on its own port: it answers with that start)
answers() {
  docker exec "$ME" sh -c 'wget -q -T 5 -O - "http://127.0.0.1:${PORT:-8083}/cgi-bin/updater"' 2> /dev/null | grep -qF "\"started\":\"$1 $new\""
}
state() { docker inspect -f '{{.State.Running}} {{.State.StartedAt}}' "$ME" 2>/dev/null; }
end=$(($(up) + 180))
while [ "$(up)" -lt "$end" ]; do
  sleep 5
  # (started: its time and its image, written as it starts)
  # shellcheck disable=SC2046
  set -- $(get started)
  began=$(state)
  [ "$2" = "$new" ] && [ "${began%% *}" = true ] && [ "${began#* }" != "$was" ] || continue
  # (no crash loop, and its interface works: the same start all along, its page says it)
  ok=0
  while [ $ok -lt 9 ] && [ "$(state)" = "$began" ] && answers "$1"; do
    ok=$((ok + 1))
    sleep 5
  done
  if [ $ok -ge 9 ]; then
    log "updater: its new version runs and answers"
    exit 0
  fi
done

log "updater: its new version didn't come up or didn't answer, back to the one before"
# (left out: its id, and each digest its registry knows it by)
d=$(digests_in "$ref" "$(repo_of "$ref")")
status updater_failed "$new" ${d:+"$d"}
docker tag "$old" "$ref"
compose 300 "$ME" up -d --no-deps --pull never "$svc" > /dev/null 2>&1
