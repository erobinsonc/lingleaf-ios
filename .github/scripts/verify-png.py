#!/usr/bin/env python3
"""Checks that a file is a well-formed PNG of sane size, and nothing else: chunks walked end to end, every
length inside the file, every CRC right, IHDR first (13 bytes), at least one IDAT, IEND last with no byte after it,
and width * height * 4 within a memory budget (a few bytes of IDAT can inflate to gigabytes).
Usage: verify-png.py <file>. Prints the reason to stderr and exits 1 when the file is not acceptable."""
import re
import struct
import sys
import zlib

MAX_SIDE = 16384
MAX_BYTES = 64 * 1024 * 1024  # width * height * 4


def fail(reason):
    sys.exit(f"not an acceptable PNG: {reason}")


data = open(sys.argv[1], "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    fail("signature")
pos, first, idat, ended = 8, True, False, False
while pos < len(data):
    if ended:
        fail("data after IEND")
    if pos + 12 > len(data):
        fail("truncated chunk")
    length, kind = struct.unpack(">I4s", data[pos:pos + 8])
    if not re.fullmatch(rb"[A-Za-z]{4}", kind):
        fail("chunk type")
    if pos + 12 + length > len(data):
        fail("chunk longer than the file")
    body = data[pos + 8:pos + 8 + length]
    (crc,) = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])
    if zlib.crc32(kind + body) != crc:
        fail("CRC")
    if first:
        if kind != b"IHDR" or length != 13:
            fail("IHDR must come first")
        width, height = struct.unpack(">II", body[:8])
        if not (1 <= width <= MAX_SIDE and 1 <= height <= MAX_SIDE) or width * height * 4 > MAX_BYTES:
            fail("size")
        first = False
    elif kind == b"IHDR":
        fail("second IHDR")
    if kind == b"IDAT":
        idat = True
    if kind == b"IEND":
        if length != 0 or not idat:
            fail("IEND without image data")
        ended = True
    pos += 12 + length
if not ended:
    fail("no IEND")
