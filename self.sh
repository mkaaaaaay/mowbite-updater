#!/bin/sh
# the updater's own update (updater.sh, update_self): a container of its own on the image the updater ran so far, so it
# stays while the updater is replaced. $1 the updater's image tag, now on the new image, $2 the tag of the one it ran
# so far. starts it on the new one and sees it come up (it says so in its status within two minutes), else starts it
# on the one before again and leaves the new one out
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
compose 300 "$ME" up -d --no-deps --pull never "$svc" > /dev/null 2>&1
n=0
while [ $n -lt 24 ]; do
  sleep 5
  # (started: its time and its image, written as it starts. then still the same start half a minute later: no crash loop)
  # shellcheck disable=SC2046
  set -- $(get started)
  began=$(docker inspect -f '{{.State.Running}} {{.State.StartedAt}}' "$ME" 2>/dev/null)
  if [ "$2" = "$new" ] && [ "${began%% *}" = true ] && [ "${began#* }" != "$was" ]; then
    sleep 30
    if [ "$(docker inspect -f '{{.State.Running}} {{.State.StartedAt}}' "$ME" 2>/dev/null)" = "$began" ]; then
      log "updater: its new version runs"
      exit 0
    fi
  fi
  n=$((n + 1))
done

log "updater: its new version didn't come up, back to the one before"
# (left out: its id, and the digest its registry knows it by)
d=$(docker image inspect -f '{{join .RepoDigests " "}}' "$ref" 2>/dev/null | tr ' ' '\n' |
  awk -F@ -v r="$(printf '%s' "$ref" | sed 's/@.*//; s/:[^:/]*$//')" '$1 == r {print $2; exit}')
status updater_failed "$new" ${d:+"$d"}
docker tag "$old" "$ref"
compose 300 "$ME" up -d --no-deps --pull never "$svc" > /dev/null 2>&1
