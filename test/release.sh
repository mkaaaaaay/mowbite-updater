#!/bin/sh
# a version's way out in image.yml, its own scripts run against a made-up repo: a tag only as vX.Y.Z or vX.Y.Z-beta.N,
# with a message and on a commit of main, its release a pre-release exactly for a version with a dash. and the names
# its image gets: build pushes sha-<commit> only, latest only for a tag without a dash, the version for each.
# (static.sh runs it, yq from its image as there)
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
bad() { echo "release: $*"; fail=1; }
yq=mikefarah/yq:4.53.6
y() { docker run --rm -i "$yq" "$1" < .github/workflows/image.yml; }

# the names
[ "$(y '.jobs.build.needs')" = ref ] || bad "build doesn't wait for the tag's check"
[ "$(y '.jobs.build.steps[] | select(.id == "push") | .with.tags')" = '${{ steps.sha.outputs.tags }}' ] &&
  [ "$(y '.jobs.build.steps[] | select(.id == "sha") | .with.tags')" = 'type=sha,format=short' ] ||
  bad "build pushes more than sha-<commit>"
[ "$(y '.jobs.build.steps[] | select(.id == "meta") | .with.tags' | grep -c .)" = 2 ] &&
  y '.jobs.build.steps[] | select(.id == "meta") | .with.tags' | grep -qx 'type=semver,pattern={{version}}' ||
  bad "the image's version label isn't the tag's version"
want="type=raw,value=latest,enable=\${{ github.ref_type == 'tag' && !contains(github.ref_name, '-') }}
type=semver,pattern={{version}}"
[ "$(y '.jobs.image.steps[] | select(.id == "meta") | .with.tags' | sed '/^$/d')" = "$want" ] &&
  [ "$(y '.jobs.image.steps[] | select(.id == "meta") | .with.flavor')" = latest=false ] ||
  bad "the image's names aren't latest for a tag without a dash and the version"
[ "$(y '.jobs.release.needs')" = image ] && [ "$(y '.jobs.release.if')" = "github.ref_type == 'tag'" ] ||
  bad "the release doesn't wait for the image or isn't only for a tag"

# the tag's check and the release, on a repo with main, a commit beside it and tags
ref=$(y '.jobs.ref.steps[] | select(.run) | .run')
rel=$(y '.jobs.release.steps[] | select(.run) | .run')
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
g() { git -C "$d/w" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@"; }
{
  git init -q --bare "$d/origin.git" && git clone -q "$d/origin.git" "$d/w" &&
    g commit -q --allow-empty -m one && g push -q origin HEAD:main && main=$(g rev-parse HEAD) &&
    g commit -q --allow-empty -m two && side=$(g rev-parse HEAD) &&
    g tag -a v1.2.0 -m note "$main" && g tag -a v1.2.0-beta.1 -m note "$main" && g tag v1.3.0 "$main" &&
    g tag -a v1.4.0 -m note "$side" && g tag -a v1.5 -m note "$main" && g tag -a v1.2.0-rc.1 -m note "$main" &&
    g push -q origin --tags && g fetch -q origin && g tag | while read -r t; do g tag -d "$t"; done > /dev/null
} 2> /dev/null || { echo "release: the made-up repo FAILED"; exit 1; }
mkdir "$d/bin"
printf '#!/bin/sh\n[ "$2" = view ] && exit 1\necho "$@" > "%s/gh"\n' "$d" > "$d/bin/gh"
chmod +x "$d/bin/gh"

# <tag> <commit> <ok or no>: whether the tag's check lets it through, and for one that's through how its release is made
tag() {
  if (cd "$d/w" && GITHUB_REF_NAME=$1 GITHUB_SHA=$2 bash -e -c "$ref") > /dev/null 2>&1; then got=ok; else got=no; fi
  [ "$got" = "$3" ] || { bad "tag $1: $got instead of $3"; return; }
  [ "$got" = ok ] || return 0
  rm -f "$d/gh"
  (cd "$d/w" && PATH="$d/bin:$PATH" GITHUB_REF_NAME=$1 bash -e -c "$rel") > /dev/null 2>&1 || { bad "tag $1: the release failed"; return; }
  case $1 in *-*) kind='--prerelease --latest=false' ;; *) kind=--latest ;; esac
  case $(cat "$d/gh" 2>/dev/null) in
  "release create $1 --verify-tag $kind --title MowBite Updater ${1#v} --notes-from-tag") ;;
  *) bad "tag $1: $(cat "$d/gh" 2>/dev/null)" ;;
  esac
}
tag v1.2.0 "$main" ok
tag v1.2.0-beta.1 "$main" ok
tag v1.3.0 "$main" no
tag v1.4.0 "$side" no
tag v1.5 "$main" no
tag v1.2.0-rc.1 "$main" no

[ $fail = 0 ]
