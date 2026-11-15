#!/usr/bin/env bash
# Checks the downloaded screenshots before the job that holds a write token sees them.
# Only flat, regular, real PNG files within sane limits pass; anything else fails the
# job. Writes ready=true|false to $GITHUB_OUTPUT (false: nothing to publish).
# Usage: verify-screenshots.sh <dir>
set -euo pipefail
dir="${1:?directory}"
out="${GITHUB_OUTPUT:-/dev/null}"
max_files=200
max_bytes=$((5 * 1024 * 1024))
max_total=$((50 * 1024 * 1024))
total=0

if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir")" ]; then
  echo "No screenshots to publish"
  echo "ready=false" >> "$out"
  exit 0
fi

count=0
while IFS= read -r -d '' entry; do
  name="${entry##*/}"
  # A file name is attacker data: show only a safe, short form in workflow commands.
  shown="$(printf '%s' "$name" | LC_ALL=C tr -c 'A-Za-z0-9._-' '?' | head -c 60)"
  [ -f "$entry" ] && [ ! -L "$entry" ] || { echo "::error::Not a regular file: $shown"; exit 1; }
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.png$ ]] || { echo "::error::Unexpected file name: $shown"; exit 1; }
  size="$(wc -c < "$entry")"
  [ "$size" -le "$max_bytes" ] || { echo "::error::Too large: $shown"; exit 1; }
  total=$((total + size))
  [ "$total" -le "$max_total" ] || { echo "::error::Total size over the limit"; exit 1; }
  # PNG signature, then the IHDR chunk (length 13, "IHDR") with a width and height that are neither 0 nor absurd.
  [ "$(head -c 16 "$entry" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a0000000d49484452" ] || { echo "::error::Not a PNG: $shown"; exit 1; }
  dims="$(dd if="$entry" bs=1 skip=16 count=8 2>/dev/null | od -An -tu1 | tr -s ' ')"
  read -r w1 w2 w3 w4 h1 h2 h3 h4 <<< "$dims"
  width=$(( (w1 << 24) | (w2 << 16) | (w3 << 8) | w4 )); height=$(( (h1 << 24) | (h2 << 16) | (h3 << 8) | h4 ))
  { [ "$width" -ge 1 ] && [ "$width" -le 16384 ] && [ "$height" -ge 1 ] && [ "$height" -le 16384 ]; } || { echo "::error::Unexpected PNG size: $shown"; exit 1; }
  count=$((count + 1))
done < <(find "$dir" -mindepth 1 -print0)
[ "$count" -le "$max_files" ] || { echo "::error::Too many files: $count"; exit 1; }
echo "Verified $count screenshots"
echo "ready=true" >> "$out"
