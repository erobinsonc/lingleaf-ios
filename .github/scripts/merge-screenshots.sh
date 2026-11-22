#!/usr/bin/env bash
# Flattens the per-shard screenshot artifacts (<parts>/<artifact>/<file>.png) into <out>, and fails on
# anything but plain files one level down, or on a file name two shards both produced (a silent
# overwrite would hide a screenshot). The result still goes through verify-screenshots.sh.
# Usage: merge-screenshots.sh <parts dir> <out dir>
set -euo pipefail
parts="${1:?parts}"; out="${2:?out}"
mkdir -p "$out"
[ -d "$parts" ] || { echo "No screenshots downloaded"; exit 0; }
while IFS= read -r -d '' entry; do
  name="${entry##*/}"
  shown="$(printf '%s' "$name" | LC_ALL=C tr -c 'A-Za-z0-9._-' '?' | head -c 60)"
  { [ -f "$entry" ] && [ ! -L "$entry" ]; } || { echo "::error::Not a regular file in a shard artifact: $shown"; exit 1; }
  [ ! -e "$out/$name" ] || { echo "::error::Two shards produced the same screenshot: $shown"; exit 1; }
  cp --no-dereference "$entry" "$out/$name"
done < <(find "$parts" -mindepth 2 -print0)
# Files sitting directly in <parts> (not inside an artifact folder) are not expected either.
if [ -n "$(find "$parts" -mindepth 1 -maxdepth 1 -not -type d -print -quit)" ]; then
  echo "::error::Unexpected file next to the shard artifact folders"; exit 1
fi
