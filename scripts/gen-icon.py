#!/usr/bin/env python3
"""Generate assets/extension-icon.png (512x512 RGBA) with stdlib only."""
import struct
import zlib
import os

W = H = 512
R = 100  # corner radius

TOP = (13, 148, 136)   # teal
BOT = (37, 78, 216)    # indigo


def inside_rounded(x, y):
    cx = min(max(x, R), W - 1 - R)
    cy = min(max(y, R), H - 1 - R)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= R * R


def in_rect(x, y, x0, y0, x1, y1):
    return x0 <= x < x1 and y0 <= y < y1


def in_tri(x, y, p0, p1, p2):
    def sign(a, b, c):
        return (a[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (a[1] - c[1])

    p = (x, y)
    d1, d2, d3 = sign(p, p0, p1), sign(p, p1, p2), sign(p, p2, p0)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def glyph(x, y):
    # two opposing arrows (translate back and forth)
    if in_rect(x, y, 116, 183, 320, 227):
        return True
    if in_tri(x, y, (320, 151), (320, 259), (396, 205)):
        return True
    if in_rect(x, y, 192, 285, 396, 329):
        return True
    if in_tri(x, y, (192, 253), (192, 361), (116, 307)):
        return True
    return False


rows = []
for y in range(H):
    t = y / (H - 1)
    bg = tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOT))
    row = bytearray([0])
    for x in range(W):
        if not inside_rounded(x, y):
            row += bytes((0, 0, 0, 0))
        elif glyph(x, y):
            row += bytes((245, 250, 255, 255))
        else:
            row += bytes(bg + (255,))
    rows.append(bytes(row))

raw = b"".join(rows)


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")

out = os.path.join(os.path.dirname(__file__), "..", "assets", "extension-icon.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "wb") as f:
    f.write(png)
print(f"wrote {os.path.normpath(out)} ({len(png)} bytes)")
