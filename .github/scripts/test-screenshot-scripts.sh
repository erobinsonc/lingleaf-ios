#!/usr/bin/env bash
# Local tests for verify-screenshots.sh and publish-screenshots.sh (symlink and size abuse).
# Usage: .github/scripts/test-screenshot-scripts.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
# Builds PNG fixtures (valid ones and the proofs of concept of attacks) with their right CRCs.
cat > "$t/mkpng.py" <<'PY'
import os, struct, sys, zlib
kind, out = sys.argv[1], sys.argv[2]
def chunk(name, body): return struct.pack(">I", len(body)) + name + body + struct.pack(">I", zlib.crc32(name + body))
def ihdr(w, h, colour=0): return chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, colour, 0, 0, 0))
def stream(total, fill=b"\x00"):   # a zlib stream of `total` bytes, compressed in pieces (a bomb stays small)
    comp, parts, left = zlib.compressobj(), [], total
    while left:
        n = min(left, 1 << 20); parts.append(comp.compress(fill * n)); left -= n
    parts.append(comp.flush()); return b"".join(parts)
def idat(w, h, bpp=1): return chunk(b"IDAT", stream(h * (1 + w * bpp)))
end = chunk(b"IEND", b"")
sig = b"\x89PNG\r\n\x1a\n"
tiny = idat(1, 1)                                   # 1x1 grey: 2 bytes
png = sig + ihdr(1, 1) + tiny + end
def pad():   # valid RGB image of incompressible rows, about 4.5 MB
    w, h = 1000, 1500
    rows = b"".join(b"\x00" + os.urandom(w * 3) for _ in range(h))
    return sig + ihdr(w, h, 2) + chunk(b"IDAT", zlib.compress(rows, 0)) + end
def make(kind):
    if kind == "good": return png
    if kind == "withexif": return sig + ihdr(1, 1) + chunk(b"sRGB", b"\x00") + chunk(b"eXIf", b"MM\x00*") + chunk(b"iTXt", b"k\x00\x00\x00\x00\x00v") + tiny + end
    if kind == "pad": return pad()
    if kind == "bomb": return sig + ihdr(1, 1) + chunk(b"IDAT", stream(1 << 30)) + end                     # inflates to 1 GiB
    if kind == "bigheader": return sig + ihdr(16384, 16384) + tiny + end                                   # 16384x16384 claimed
    if kind == "wide": return sig + ihdr(4097, 4096, 6) + tiny + end                                       # one column over the budget
    if kind == "edge": return sig + ihdr(4096, 4096, 6) + idat(4096, 4096, 4) + end                         # exactly the budget
    if kind == "zero": return sig + ihdr(0, 1) + tiny + end
    if kind == "html": return sig + ihdr(1, 1) + b"<html><script>alert(1)</script></html>"
    if kind == "polyglot": return png + b"PK\x03\x04" + bytes(40)
    if kind == "badcrc": return sig + ihdr(1, 1) + tiny[:-1] + b"\x00" + end
    if kind == "noidat": return sig + ihdr(1, 1) + end
    if kind == "noiend": return sig + ihdr(1, 1) + tiny
    if kind == "ihdrlate": return sig + chunk(b"tEXt", b"a\x00b") + ihdr(1, 1) + tiny + end
    if kind == "longchunk": return sig + ihdr(1, 1) + struct.pack(">I", 10**6) + b"IDAT" + bytes(8)
    if kind == "magiconly": return sig + b"xx"
    if kind == "shortdata": return sig + ihdr(2, 2) + tiny + end                                           # IDAT too short for 2x2
    if kind == "oversize": return sig + ihdr(1, 1) + chunk(b"IDAT", stream(100)) + end                    # inflates past the header
    if kind == "customchunk": return sig + ihdr(1, 1) + chunk(b"prVt", b"x") + tiny + end
    if kind == "bigancillary": return sig + ihdr(1, 1) + chunk(b"eXIf", bytes(70000)) + tiny + end
    if kind == "interlaced": return sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 1)) + tiny + end
    if kind == "sixteenbit": return sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 16, 0, 0, 0, 0)) + tiny + end
open(out, "wb").write(make(kind))
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

for kind in bomb bigheader wide zero html polyglot badcrc noidat noiend ihdrlate longchunk magiconly shortdata oversize customchunk bigancillary interlaced sixteenbit; do
  mkdir "$t/bad-$kind"; mk "$kind" "$t/bad-$kind/a.png"
  expect 1 "verify: PNG proof of concept '$kind'" "$here/verify-screenshots.sh" "$t/bad-$kind"
done
mkdir "$t/exif"; mk withexif "$t/exif/a.png"
expect 0 "verify: a PNG with sRGB, eXIf and iTXt like the real screenshots" env GITHUB_OUTPUT="$t/o" "$here/verify-screenshots.sh" "$t/exif"
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
