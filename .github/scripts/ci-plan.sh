#!/usr/bin/env bash
# Decides how much of the iOS CI a pull request needs and writes mode=<full|same-tree|release>
# to $GITHUB_OUTPUT. Run from a checkout with full history of the pull request merge commit.
#   full       everything runs (pushes, any real change, hotfixes, a release whose base moved)
#   same-tree  the pull request head has exactly the tree of the base branch tip: nothing new to
#              test (a sync of main into develop). The base tip already passed its own push CI.
#   release    develop -> main from this repository where main is an ancestor of the head, so
#              merging yields the head tree. That head commit already ran the full CI as a push
#              on develop; the release-verify job checks that run instead of repeating it.
# Inputs come from the environment (branch names are untrusted, never interpolated into code):
#   EVENT_NAME BASE_REF HEAD_REF HEAD_SHA SAME_REPO(true|false)
set -euo pipefail
out="${GITHUB_OUTPUT:-/dev/null}"
decide() { echo "mode=$1" >> "$out"; echo "CI mode: $1 ($2)"; exit 0; }

[ "${EVENT_NAME:-}" = "pull_request" ] || decide full "not a pull request"
base="${BASE_REF:?}"; head_ref="${HEAD_REF:?}"; sha="${HEAD_SHA:?}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || decide full "unexpected head sha"
[[ "$base" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$base" != -* ]] || decide full "unexpected base name"

# Fresh base tip, by explicit refspec (no credentials needed: the repository is public).
git fetch --quiet --no-tags origin "+refs/heads/$base:refs/remotes/origin/$base" || decide full "could not fetch the base"
git cat-file -e "$sha^{commit}" 2>/dev/null || decide full "head commit not in the checkout"

if [ "$base" = "main" ] && [ "$head_ref" = "develop" ] && [ "${SAME_REPO:-false}" = "true" ]; then
  if git merge-base --is-ancestor "refs/remotes/origin/main" "$sha"; then
    decide release "main is an ancestor of the head: the merge tree is the head tree"
  fi
  decide full "main is not an ancestor of the head"
fi

if [ "$(git rev-parse "$sha^{tree}")" = "$(git rev-parse "refs/remotes/origin/$base^{tree}")" ]; then
  decide same-tree "head tree equals the tip tree of $base"
fi
decide full "the tree differs from $base"
