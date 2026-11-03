#!/bin/sh
# the checks that need no mower, on every push: shellcheck, the page's javascript, compose.yaml with the image, the name
# and the port the mowers and MowBite know it by, the contract (test/contract.txt), image.yml only building once the checks, the tests and the commit
# check passed, and a version's tag, release and names (test/release.sh).
# (shellcheck and yq come from their images, the same versions here and in the ci)
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "$1 ok"; }
bad() { echo "$1 FAILED${2:+: $2}"; fail=1; }

if docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:v0.11.0 -s sh -e SC1091,SC3043,SC2034,SC2015,SC2016,SC2153 \
  /mnt/updater.sh /mnt/lib.sh /mnt/self.sh /mnt/calib.sh /mnt/www/cgi-bin/updater /mnt/www/cgi-bin/index.cgi /mnt/test/run.sh /mnt/test/static.sh /mnt/test/contract.sh /mnt/test/release.sh; then
  ok shellcheck
else
  bad shellcheck
fi
if node --check www/app.js; then ok app.js; else bad app.js; fi
if python3 -c "import ast; ast.parse(open('test/gate.py').read())"; then ok gate.py; else bad gate.py; fi
if python3 -c "import ast; ast.parse(open('test/github.py').read())"; then ok github.py; else bad github.py; fi

# the image image.yml makes (named after the repo), the container self.sh and MowBite look for, its page's port
image=ghcr.io/${GITHUB_REPOSITORY:-mkaaaaaay/mowbite-updater}:latest
if ! c=$(docker compose -f compose.yaml config --format json); then
  bad compose.yaml "not valid compose"
else
  got=$(printf '%s' "$c" | jq -r '[.services.updater.image, .services.updater.container_name, .services.updater.labels["openmower.ui.port"]] | join(" ")')
  if [ "$got" = "$image mowbite-updater 8083" ]; then ok compose.yaml; else bad compose.yaml "image, container and port are $got"; fi
fi
grep -q 'httpd -p "${PORT:-8083}"' updater.sh && ok port || bad port "updater.sh serves on another port than 8083"

# what MowBite and other apps know it by (test/contract.sh), the same as in test/contract.txt
if sh test/contract.sh | cmp -s - test/contract.txt; then
  ok contract
else
  bad contract "it changed, test/contract.txt goes with it in the same commit (sh test/contract.sh > test/contract.txt):"
  sh test/contract.sh | diff test/contract.txt - | grep '^[<>]'
fi

yq=mikefarah/yq:4.53.6
docker image inspect "$yq" > /dev/null 2>&1 || docker pull -q "$yq" > /dev/null
needs=$(docker run --rm -i "$yq" '.jobs.image.needs[]' < .github/workflows/image.yml)
miss=
for job in check test commits; do printf '%s\n' "$needs" | grep -qx "$job" || miss="$miss $job"; done
if [ -z "$miss" ]; then ok image.yml; else bad image.yml "the image doesn't wait for:$miss"; fi
# a version's way out: the tag's check, its release and the image's names (test/release.sh)
if sh test/release.sh; then ok release; else bad release; fi

[ $fail = 0 ]
