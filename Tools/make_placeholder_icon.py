#!/usr/bin/env python3
"""Generate the placeholder app icons.

An upload to App Store Connect is refused outright if the bundle carries no app
icon, so TestFlight is unreachable without one — and no production artwork
exists yet (`AssetsSource/ASSET_MANIFEST.md`). This draws a deliberately
characterless stand-in: a sky wash and a sun disc, no sloth, no face, no
proportions. `CLAUDE.md` forbids inventing a Sunnie design, and the surest way
to honour that is for the placeholder to contain no character at all.

Written against zlib and struct rather than Pillow so it runs on any machine
with a Python, including a CI runner with nothing installed.

Two rules the App Store enforces and this obeys:

  * No alpha channel. An icon with transparency is rejected at upload, which is
    why the output is RGB rather than RGBA.
  * Square, 1024x1024, no rounded corners. iOS applies the mask itself; baking
    one in produces visible double-rounding.

Usage:  python3 Tools/make_placeholder_icon.py
Writes the iOS and watchOS icons and reports what changed.
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SIZE = 1024

# Drawn from AccentColor (#A9C59F) so the placeholder at least sits in the
# app's own palette rather than announcing itself in an unrelated hue.
SKY_TOP = (253, 246, 232)      # warm cream
SKY_BOTTOM = (169, 197, 159)   # the accent sage
SUN = (242, 196, 107)          # warm gold

SUN_CENTRE = (0.5, 0.44)       # in unit coordinates
SUN_RADIUS = 0.20
SUN_FEATHER = 0.012            # soft edge, in the same units

TARGETS = [
    "Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Placeholder-1024.png",
    "Apps/Watch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Placeholder-1024.png",
]


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Linear blend, clamped, rounded to bytes."""
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    """Hermite interpolation, for a sun edge that is not a staircase."""
    if edge1 == edge0:
        return 0.0 if x < edge0 else 1.0
    t = (x - edge0) / (edge1 - edge0)
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return t * t * (3.0 - 2.0 * t)


def render() -> bytes:
    """The icon as raw PNG scanlines, each prefixed with filter type 0."""
    rows = bytearray()
    cx, cy = SUN_CENTRE
    inner = SUN_RADIUS - SUN_FEATHER
    outer = SUN_RADIUS + SUN_FEATHER

    for y in range(SIZE):
        rows.append(0)  # filter: None
        v = y / (SIZE - 1)
        sky = mix(SKY_TOP, SKY_BOTTOM, v)
        dy = v - cy
        for x in range(SIZE):
            u = x / (SIZE - 1)
            dx = u - cx
            distance = (dx * dx + dy * dy) ** 0.5
            # 1 inside the disc, 0 outside, smoothed across the feather band.
            coverage = 1.0 - smoothstep(inner, outer, distance)
            rows.extend(mix(sky, SUN, coverage) if coverage > 0.0 else sky)

    return bytes(rows)


def chunk(kind: bytes, payload: bytes) -> bytes:
    """One PNG chunk: length, type, payload, CRC over type+payload."""
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def encode(raw: bytes) -> bytes:
    header = struct.pack(
        ">IIBBBBB",
        SIZE, SIZE,
        8,      # bit depth
        2,      # colour type 2 = truecolour, no alpha
        0, 0, 0,  # deflate, adaptive filtering, no interlace
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    png = encode(render())

    for relative in TARGETS:
        path = ROOT / relative
        if not path.parent.is_dir():
            print(f"FAIL {relative}: {path.parent.name} does not exist")
            return 1
        unchanged = path.is_file() and path.read_bytes() == png
        path.write_bytes(png)
        print(f"{'ok  ' if unchanged else 'wrote'} {relative} ({len(png):,} bytes)")

    print(f"\n{SIZE}x{SIZE}, RGB, no alpha. Placeholder art — see AssetsSource/ASSET_MANIFEST.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
