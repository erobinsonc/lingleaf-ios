#!/usr/bin/env bash
# Publishes ./screenshots to the `screenshots` branch under
# <platform>/<branch>/, replacing the previous run for that branch, so
# anyone (people or agents) can look at the app without running it.
# Usage: publish-screenshots.sh <platform> <branch> <commit>
set -euo pipefail
platform="$1"
branch="${2//\//-}"
commit="$3"
src="$PWD/screenshots"
[ -d "$src" ] && [ -n "$(ls -A "$src")" ] || { echo "No screenshots to publish"; exit 0; }
# Defence in depth (the workflow verifies first): only plain files, never a link that
# could point at the runner (/proc/self/environ would leak the write token).
for f in "$src"/*; do
  { [ -f "$f" ] && [ ! -L "$f" ]; } || { echo "::error::Refusing non-regular file: ${f##*/}"; exit 1; }
done

work="$(mktemp -d)"
cd "$work"
git init -q -b screenshots
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add origin "https://github.com/${GITHUB_REPOSITORY}.git"
# The token goes in a header for this process only, never into .git/config.
auth="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)"
git() { command git -c "http.extraheader=$auth" "$@"; }

for attempt in 1 2 3 4; do
  if git fetch -q --depth 1 origin screenshots; then git reset -q --hard FETCH_HEAD; fi
  rm -rf "${platform:?}/$branch"
  mkdir -p "$platform/$branch"
  cp --no-dereference "$src"/*.png "$platform/$branch/"
  printf 'commit %s\nrun %s/%s/actions/runs/%s\n' "$commit" "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID" > "$platform/$branch/SOURCE.txt"
  git add -A
  git commit -qm "Screenshots: $platform $branch @ ${commit:0:7}" || { echo "Nothing changed"; exit 0; }
  if git push -q origin HEAD:screenshots; then
    echo "Published to screenshots/$platform/$branch"
    exit 0
  fi
  sleep $((attempt * 3))
done
exit 1
