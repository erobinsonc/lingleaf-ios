#!/usr/bin/env bash
# Local tests for verify-screenshots.sh and publish-screenshots.sh (symlink and size abuse).
# Usage: .github/scripts/test-screenshot-scripts.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
# A real PNG start: signature, IHDR chunk (length 13), width 1, height 1.
header() { printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01'; }
png() { { header; printf 'xx'; } > "$1"; }
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

mkdir "$t/big"; for i in $(seq 1 12); do { header; head -c 4500000 /dev/zero; } > "$t/big/f$i.png"; done
expect 1 "verify: total size over 50 MiB" "$here/verify-screenshots.sh" "$t/big"

mkdir "$t/inj"; png "$t/inj/$(printf 'a\n::error::pwned.png')"
out="$("$here/verify-screenshots.sh" "$t/inj" 2>&1)"
if printf '%s' "$out" | grep -q '^::error::pwned'; then echo "FAIL verify: file name injects a workflow command"; fail=1; else echo "ok   verify: file name cannot inject a workflow command"; fi

mkdir "$t/hdr"; printf '\x89PNG\r\n\x1a\nxxxxxxxxxxxxxxxxxxxx' > "$t/hdr/a.png"
expect 1 "verify: PNG signature without an IHDR chunk" "$here/verify-screenshots.sh" "$t/hdr"
mkdir "$t/zero"; { printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x00\x00\x00\x00\x01'; printf 'xx'; } > "$t/zero/a.png"
expect 1 "verify: IHDR with width 0" "$here/verify-screenshots.sh" "$t/zero"
mkdir "$t/huge"; { printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x7f\xff\xff\xff\x00\x00\x00\x01'; printf 'xx'; } > "$t/huge/a.png"
expect 1 "verify: IHDR with an absurd width" "$here/verify-screenshots.sh" "$t/huge"
mkdir "$t/short"; printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > "$t/short/a.png"
expect 1 "verify: IHDR cut before its size" "$here/verify-screenshots.sh" "$t/short"

# publish: runs in a scratch dir with a fake git so nothing is pushed.
mkdir "$t/pub" "$t/bin"; ln -s /proc/self/environ "$t/pub/x.png"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/git"; chmod +x "$t/bin/git"
expect 1 "publish: refuses symlink to /proc/self/environ" \
  env -C "$t" PATH="$t/bin:$PATH" GH_TOKEN=secret GITHUB_REPOSITORY=o/r GITHUB_SERVER_URL=https://x GITHUB_RUN_ID=1 \
  sh -c 'mkdir -p w && cd w && rm -rf screenshots && cp -a "$0/pub" screenshots && "$1/publish-screenshots.sh" ios br abcdef0' "$t" "$here"
exit $fail
