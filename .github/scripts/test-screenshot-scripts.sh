#!/usr/bin/env bash
# Local tests for verify-screenshots.sh and publish-screenshots.sh (symlink and size abuse).
# Usage: .github/scripts/test-screenshot-scripts.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
png() { printf '\x89PNG\r\n\x1a\nxx' > "$1"; }
expect() { # <want-rc> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if { [ "$want" = 0 ] && [ $rc -eq 0 ]; } || { [ "$want" != 0 ] && [ $rc -ne 0 ]; }; then echo "ok   $label"
  else echo "FAIL $label (rc=$rc)"; fail=1; fi
}
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT

mkdir "$t/good"; png "$t/good/en-light-01-a.png"
expect 0 "verify: good PNG" env GITHUB_OUTPUT="$t/o" "$here/verify-screenshots.sh" "$t/good"

mkdir "$t/link"; ln -s /proc/self/environ "$t/link/x.png"
expect 1 "verify: symlink to /proc/self/environ" "$here/verify-screenshots.sh" "$t/link"

mkdir "$t/big"; for i in $(seq 1 12); do { printf '\x89PNG\r\n\x1a\n'; head -c 4500000 /dev/zero; } > "$t/big/f$i.png"; done
expect 1 "verify: total size over 50 MiB" "$here/verify-screenshots.sh" "$t/big"

# publish: runs in a scratch dir with a fake git so nothing is pushed.
mkdir "$t/pub" "$t/bin"; ln -s /proc/self/environ "$t/pub/x.png"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/git"; chmod +x "$t/bin/git"
expect 1 "publish: refuses symlink to /proc/self/environ" \
  env -C "$t" PATH="$t/bin:$PATH" GH_TOKEN=secret GITHUB_REPOSITORY=o/r GITHUB_SERVER_URL=https://x GITHUB_RUN_ID=1 \
  sh -c 'mkdir -p w && cd w && rm -rf screenshots && cp -a "$0/pub" screenshots && "$1/publish-screenshots.sh" ios br abcdef0' "$t" "$here"
exit $fail
