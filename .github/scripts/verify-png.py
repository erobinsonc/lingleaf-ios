#!/usr/bin/env python3
"""Checks that a file is a well-formed PNG of sane size and content, and nothing else:
- chunks walked end to end: every length inside the file, every CRC right, IHDR first (13 bytes), IDAT present,
  IEND last with no byte after it;
- only the chunk types a screenshot has (IHDR PLTE IDAT IEND sRGB gAMA pHYs eXIf iTXt), ancillary ones small;
- 8-bit grey, grey+alpha, RGB or RGBA, no interlace, width and height 1..16384, width * height * 4 <= 64 MB;
- the IDAT stream inflates to exactly height * (1 + width * bytes per pixel) bytes, read with a limit, so a few
  bytes of IDAT cannot expand to gigabytes.
Usage: verify-png.py <file>. Prints the reason to stderr and exits 1 when the file is not acceptable."""
import re
import struct
import sys
import zlib

MAX_SIDE = 16384
MAX_BYTES = 64 * 1024 * 1024  # width * height * 4
ALLOWED = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"pHYs", b"eXIf", b"iTXt"}
MAX_ANCILLARY = 64 * 1024
BYTES_PER_PIXEL = {0: 1, 2: 3, 4: 2, 6: 4}  # colour type -> bytes per pixel at 8 bits


def fail(reason):
    sys.exit(f"not an acceptable PNG: {reason}")


data = open(sys.argv[1], "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    fail("signature")
pos, first, ended = 8, True, False
idat = []
expected = 0
while pos < len(data):
    if ended:
        fail("data after IEND")
    if pos + 12 > len(data):
        fail("truncated chunk")
    length, kind = struct.unpack(">I4s", data[pos:pos + 8])
    if not re.fullmatch(rb"[A-Za-z]{4}", kind):
        fail("chunk type")
    if kind not in ALLOWED:
        fail("chunk type not allowed")
    if pos + 12 + length > len(data):
        fail("chunk longer than the file")
    if kind not in (b"IDAT", b"PLTE") and length > MAX_ANCILLARY:
        fail("chunk too large")
    body = data[pos + 8:pos + 8 + length]
    (crc,) = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])
    if zlib.crc32(kind + body) != crc:
        fail("CRC")
    if first:
        if kind != b"IHDR" or length != 13:
            fail("IHDR must come first")
        width, height, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
        if not (1 <= width <= MAX_SIDE and 1 <= height <= MAX_SIDE) or width * height * 4 > MAX_BYTES:
            fail("size")
        if depth != 8 or colour not in BYTES_PER_PIXEL or compression or filtering or interlace:
            fail("image format")
        expected = height * (1 + width * BYTES_PER_PIXEL[colour])
        first = False
    elif kind == b"IHDR":
        fail("second IHDR")
    if kind == b"IDAT":
        idat.append(body)
    if kind == b"IEND":
        if length != 0 or not idat:
            fail("IEND without image data")
        ended = True
    pos += 12 + length
if not ended:
    fail("no IEND")
inflater = zlib.decompressobj()
try:
    out = inflater.decompress(b"".join(idat), expected + 1)
except zlib.error:
    fail("image data does not inflate")
if len(out) != expected or not inflater.eof or inflater.unconsumed_tail or inflater.unused_data:
    fail("image data length does not match the header")
