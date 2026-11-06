#!/bin/sh
# data.sh on its own, in the image the updater is built on (its last FROM), within a minute: a folder and a file kept
# with what they hold, a piece that isn't there, pieces outside its folder refused, the schema, all of it put back as it
# was kept (owner, rights, a link, gone and new files), done again after a stop halfway, a copy that changed refused,
# a full disk while it keeps. only inside a container, nothing written here. what failed a line, 1 then
set -u
cd "$(dirname "$0")/.." || exit 1
# (disks of 4 to 40 kB: full somewhere between the tar, what it holds and its schema)
SIZES='4 8 12 16 20 24 28 32 36 40'
if [ "${1:-}" != in ]; then
  img=$(sed -n 's/^FROM \([^ ]*\)$/\1/p' Dockerfile | tail -n1)
  docker image inspect "$img" > /dev/null 2>&1 || docker pull -q "$img" > /dev/null || { echo "no $img"; exit 1; }
  small=
  for k in $SIZES; do small="$small --tmpfs /small$k:size=${k}k"; done
  # (a run that hangs ends by itself)
  # shellcheck disable=SC2086
  exec docker run --rm --network none --tmpfs /small:size=64k $small -v "$PWD:/r:ro" --entrypoint timeout "$img" 120 sh /r/test/data.sh in
fi

ln -sf /r/data.sh /data.sh
fails=0
bad() { echo "data.sh: $*"; fails=$((fails + 1)); }
# (/s, /o and /b as the updater mounts them: the data, a new copy, the copy to put back)
at() { ln -sfn "$1" /s; ln -sfn "$2" /o; ln -sfn "$2" /b; }
run() { (cd / && sh /data.sh "$@"); }
look() {
  (cd "$1" && find . | sort | while read -r f; do
    if [ -L "$f" ]; then echo "link $(readlink "$f") $f"; else echo "$(stat -c %u:%g:%a "$f") $f"; [ -f "$f" ] && cat "$f"; fi
  done)
}
mkdir -p /w/s/stats /w/o /w/f /w/fo
cd /w/s && echo 1 > schema && echo token > notify.conf && chmod 600 notify.conf && echo 1 2 3 > stats/hours && ln -s stats lnk &&
  ln -s nowhere gone && echo d > .dot && chown -R 1000:1000 /w/s && echo "{}" > /w/f/map.json && chmod 640 /w/f/map.json
mkdir /w/s/.updater-put && echo half > /w/s/.updater-put/x
at /w/s /w/o
run keep 1 . || bad "a folder isn't kept"
tar -tf /w/o/1.tar | grep -q updater-put && bad "what it unpacks into is kept too"
rm -rf /w/s/.updater-put
[ "$(cat /w/o/1.schema)" = 1 ] || bad "its schema isn't kept"
grep -q "^1000:1000:600 [0-9a-f]\{64\} ./notify.conf$" /w/o/1.sums && grep -q "^link stats ./lnk$" /w/o/1.sums || bad "what it holds: $(cat /w/o/1.sums)"
before=$(look /w/s)
at /w/f /w/fo
run keep 1 map.json && [ ! -e /w/fo/1.schema ] || bad "a file isn't kept"
run keep 2 nothing.json
[ $? = 3 ] && [ ! -e /w/fo/2.tar ] || bad "a piece that isn't there isn't said"
at /w/s /w/o
echo x > /w/s/-v
for p in ../f/map.json /w/f/map.json f//map.json .. "" stats -v; do run keep 3 "$p" 2> /dev/null && bad "kept $p"; done
for n in x 1/../2 ""; do run keep "$n" schema 2> /dev/null && bad "kept as number $n"; done
rm -f /w/o/3.tar /w/o/x.tar /w/o/.tar /w/s/-v
run schema 1 .. > /dev/null 2>&1 && bad "a schema outside its folder"
run nonsense 1 . 2> /dev/null && bad "a word it doesn't know"
[ "$(run schema 1 .)" = 1 ] || bad "schema"
echo 7 > /w/s/schema && [ "$(run schema 1 .)" = 7 ] || bad "schema 7"
echo x7 > /w/s/schema && [ "$(run schema 1 .)" = 1 ] || bad "a schema that isn't a number"
# (changed since: a file gone, one new, other content and rights)
echo 2 > /w/s/schema && rm -rf /w/s/stats /w/s/gone /w/s/.dot && echo new > /w/s/junk && echo h > /w/s/.hidden &&
  echo other > /w/s/notify.conf && chmod 644 /w/s/notify.conf
run put 1 . || bad "a folder isn't put back"
[ "$(look /w/s)" = "$before" ] || bad "put back, but not as it was"
[ -e /w/s/.updater-put ] && bad "what it unpacked into stays"
echo X > /w/f/map.json
at /w/f /w/fo
run put 1 map.json && [ "$(cat /w/f/map.json)" = "{}" ] && [ "$(stat -c %a /w/f/map.json)" = 640 ] || bad "a file isn't put back as it was"
# (stopped halfway: half of it gone, something half unpacked)
at /w/s /w/o
rm -f /w/s/notify.conf && echo 3 > /w/s/schema && mkdir /w/s/.updater-put && echo half > /w/s/.updater-put/notify.conf &&
  echo stray > /w/s/.updater-put/stray
run put 1 . && [ "$(look /w/s)" = "$before" ] || bad "done again, but not as it was"
# (a copy that changed: refused before anything changed, it says why)
cp /w/o/1.sums /w/o/1.sums.ok
sed -i "s/^1000:1000:600/0:0:600/" /w/o/1.sums
echo other > /w/s/notify.conf
out=$(run put 1 . 2>&1) && bad "a changed copy is put back"
case $out in *"isn't what was kept"*) ;; *) bad "a changed copy: $out" ;; esac
[ "$(cat /w/s/notify.conf)" = other ] || bad "a changed copy changed something"
mv /w/o/1.sums.ok /w/o/1.sums
run put 1 . || bad "put back again"
# (its own folder isn't replaced: other rights on it stay, and put back all the same)
chmod 750 /w/s
run put 1 . && [ "$(stat -c %a /w/s)" = 750 ] || bad "its folder itself changed or refused"
chmod 755 /w/s
# (without a schema file no schema kept: nothing to go back by)
mkdir -p /w/n /w/no && echo x > /w/n/x
at /w/n /w/no
run keep 1 . && [ ! -e /w/no/1.schema ] || bad "a schema kept that isn't there"
# (a tar that can't be unpacked: nothing changed)
at /w/s /w/o
before=$(look /w/s)
cp /w/o/1.tar /w/o/1.tar.ok && head -c 1500 /w/o/1.tar.ok > /w/o/1.tar
run put 1 . 2> /dev/null && bad "a broken tar put back"
[ "$(look /w/s)" = "$before" ] || bad "a broken tar changed something"
mv /w/o/1.tar.ok /w/o/1.tar
# (a folder where the file was: the file moved into it, seen afterwards)
at /w/f /w/fo
rm /w/f/map.json && mkdir /w/f/map.json && echo x > /w/f/map.json/x
run put 1 map.json 2> /dev/null && bad "a file put back into a folder"
rm -rf /w/f/map.json
at /w/s /w/o
# (no folder to work in: it fails)
rm /s
run keep 1 . 2> /dev/null && bad "kept without its folder"
# (the disk full while it keeps: it fails, or what it says it kept is all there)
dd if=/dev/urandom of=/w/s/big bs=1k count=200 2> /dev/null
at /w/s /small
run keep 1 . 2> /dev/null && bad "kept on a full disk"
rm /w/s/big
at /w/s /w/o
run keep 9 . && ref=$(cat /w/o/9.sums)
for k in $SIZES; do
  at /w/s "/small$k"
  if run keep 1 . 2> /dev/null; then
    [ "$(cat "/small$k/1.sums")" = "$ref" ] && [ "$(cat "/small$k/1.schema")" = 1 ] || bad "said kept on $k kB, but not all of it"
  fi
done
[ $fails = 0 ]
