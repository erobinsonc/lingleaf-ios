#!/usr/bin/env bash
# Local tests for verify-screenshots.sh and publish-screenshots.sh (symlink and size abuse).
# Usage: .github/scripts/test-screenshot-scripts.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
# Builds PNG fixtures (valid ones and the proofs of concept of attacks) with their right CRCs.
cat > "$t/mkpng.py" <<'PY'
import struct, sys, zlib
kind, out = sys.argv[1], sys.argv[2]
def chunk(name, body): return struct.pack(">I", len(body)) + name + body + struct.pack(">I", zlib.crc32(name + body))
def ihdr(w, h): return chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
idat = chunk(b"IDAT", zlib.compress(b"\x00\x00"))
end = chunk(b"IEND", b"")
sig = b"\x89PNG\r\n\x1a\n"
png = sig + ihdr(1, 1) + idat + end
files = {
    "good": png,
    "pad": sig + ihdr(1, 1) + chunk(b"prVt", bytes(4500000)) + idat + end,         # valid, 4.5 MB
    "bomb": sig + ihdr(16384, 16384) + idat + end,                                   # inflates to ~268 MB
    "wide": sig + ihdr(4097, 4096) + idat + end,                                     # one pixel row over the budget
    "edge": sig + ihdr(4096, 4096) + idat + end,                                     # exactly at the budget
    "zero": sig + ihdr(0, 1) + idat + end,
    "html": sig + ihdr(1, 1) + b"<html><script>alert(1)</script></html>",             # IHDR, then a lie
    "polyglot": png + b"PK\x03\x04" + bytes(40),                                     # a valid PNG, then a zip
    "badcrc": sig + ihdr(1, 1) + idat[:-1] + b"\x00" + end,
    "noidat": sig + ihdr(1, 1) + end,
    "noiend": sig + ihdr(1, 1) + idat,
    "ihdrlate": sig + chunk(b"tEXt", b"a\x00b") + ihdr(1, 1) + idat + end,
    "longchunk": sig + ihdr(1, 1) + struct.pack(">I", 10**6) + b"IDAT" + bytes(8),
    "magiconly": sig + b"xx",
}
open(out, "wb").write(files[kind])
PY
mk() { python3 -I -B "$t/mkpng.py" "$1" "$2"; }
png() { mk good "$1"; }
expect() { # <want-rc> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if { [ "$want" = 0 ] && [ $rc -eq 0 ]; } || { [ "$want" != 0 ] && [ $rc -ne 0 ]; }; then echo "ok   $label"
  else echo "FAIL $label (rc=$rc)"; fail=1; fi
}

mkdir "$t/good"; png "$t/good/en-light-01-a.png"
expect 0 "verify: good PNG" env GITHUB_OUTPUT="$t/o" "$here/verify-screenshots.sh" "$t/good"

mkdir "$t/link"; ln -s /proc/self/environ "$t/link/x.png"
expect 1 "verify: symlink to /proc/self/environ" "$here/verify-screenshots.sh" "$t/link"

mkdir "$t/big"; for i in $(seq 1 12); do mk pad "$t/big/f$i.png"; done
expect 1 "verify: total size over 50 MiB" "$here/verify-screenshots.sh" "$t/big"

mkdir "$t/inj"; png "$t/inj/$(printf 'a\n::error::pwned.png')"
out="$("$here/verify-screenshots.sh" "$t/inj" 2>&1)"
if printf '%s' "$out" | grep -q '^::error::pwned'; then echo "FAIL verify: file name injects a workflow command"; fail=1; else echo "ok   verify: file name cannot inject a workflow command"; fi

for kind in bomb wide zero html polyglot badcrc noidat noiend ihdrlate longchunk magiconly; do
  mkdir "$t/bad-$kind"; mk "$kind" "$t/bad-$kind/a.png"
  expect 1 "verify: PNG proof of concept '$kind'" "$here/verify-screenshots.sh" "$t/bad-$kind"
done
mkdir "$t/edge"; mk edge "$t/edge/a.png"
expect 0 "verify: a PNG exactly at the memory budget" env GITHUB_OUTPUT="$t/o" "$here/verify-screenshots.sh" "$t/edge"
mkdir "$t/emptyfile"; : > "$t/emptyfile/a.png"
expect 1 "verify: empty file named .png" "$here/verify-screenshots.sh" "$t/emptyfile"

# publish: runs in a scratch dir with a fake git so nothing is pushed.
mkdir "$t/pub" "$t/bin"; ln -s /proc/self/environ "$t/pub/x.png"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/git"; chmod +x "$t/bin/git"
expect 1 "publish: refuses symlink to /proc/self/environ" \
  env -C "$t" PATH="$t/bin:$PATH" GH_TOKEN=secret GITHUB_REPOSITORY=o/r GITHUB_SERVER_URL=https://x GITHUB_RUN_ID=1 \
  sh -c 'mkdir -p w && cd w && rm -rf screenshots && cp -a "$0/pub" screenshots && "$1/publish-screenshots.sh" ios br abcdef0' "$t" "$here"
exit $fail
