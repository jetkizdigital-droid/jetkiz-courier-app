#!/usr/bin/env python3
from __future__ import annotations

import base64
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"

GREEN = (78, 173, 53)
SOURCE_W = 95
SOURCE_H = 46
SOURCE_ALPHA_ZLIB_B64 = """eNq1V0uPFVUQPr8CDY9JwJAh4jCKjgpGlgohAcnoKAEcI1HDSx4Bkhl1QRhiCAFHjcE4ASWOouODRB5mXGhyEwIhN6Q3d9Gb3pxFbWpTi9rU5niefe9gX9MT6JPJPWeqT39dp+qrr7qVWsRArRocBUMDqIeS7yJ3HwpnWZV1Er8PCxI5uvDS8jP1wV9m4io78WdhwSILr7QIV9aGv28EK+HNu35+QoQWXtGGB2rDtwUGK8yrtAz5xZ7/wGO1P9VjTE5VmT+GGLJpNg+gdWDXIjL7eKU1S/Cz1AQvEWNIroFkjx7epFK9jjL36OEZCz+vLsR8+FA131WU3zRkMTLiIl7AeZWTGXG25wFida3BkIxiogZ6bhL8p1i8Mscu5GfZGJE83+hyjMaxfMI+kD6JZezTUiAOxTufhG/6oP/CicXouaLBB+WWMXkSNGN/T2l2+H6fMZ5UwmXOmdp94LVE+FnypzgSGHPQ8EdxAztNyNer1RhgrQZ9FarLyI+BXCKb+8Ezn4gi4Kej6J/2rdD6xFALj0/b1WGCAB8q4o1C0CbJShabvg0hpyBYyOGmjC676Z+y8JHscWbc6kCoL+LAKQWarNwZMXy2b2Z10Mu3QEKsKcDmkkqVMFd3Aq+8I2+SXInwSi3dfmkc6f9o6c6uHrMB9TQ711nXyw6fNq0CY/R01KDd/t8lS/000UpQX1d57x/ueL7WqRWNxowkHZtB4T+Csx0/3SRZFQ5TniH1gbQY6KqIBovzl7oi8r66qa+mgJuYP8cPc8POr+OmKOAckrXk1ZCrEmmq7DFFURoBQF0cU1MgcHdrMn5nO0YAmRQ7Nqjh6Lq7Nzav1gO+K+6+WHR6eh7uuOQqVvZ2d55WyftO2zhqEZfUg9g7vYe3X+gqeCrhP4Unu88UcX4cEr7eJatjuwdpqzlxyB+I7Ey+hXM5ng0WeU+TifNxlj1dqwQ3BwyXPen3a9Zd7+OKC+oc8rwnKpd14Fb79/mCF/o5mm/byI6hvRPkuR7mCGcxSPJ5dIM8HSUEoMUy7U+HP8XgeO/tngs261b6DGeWSR1HCgajrtLuXmKKXPTzuKWmk5Jnc4jvThZp2L0W0JRHFVwW61AGlQ5Zc2Xr/iTIhdppjzPTi36YJObhMqNlEcbDFIUQznviwr5YaBB5wVSc9FGyP0Noz2kfEQVqlO70ou9lI+/E9WiOjFkoWvUlEJ13ix+AtnjLFySzbh7RiP5Kivot2+uXJ8AtvegbCYxsr9nVLAmOVV8ZrjYPkDrIMly3a2aCI4t62VijNoCpv5+IWvO1d+vXlNoMshiHXqq/VTul2lZwM98cN7ygj3eagX8b/CfH8TY2Ah+9/rXdyGfZi/peIFvRbsb5Z2KJzzUBD7FTMx9oEP4poEYyi/yezyw2w0sMr0tkdaGJsQvI9smsmcjbcayNkP+9tSH0fwHt8Kbm"""

raw = zlib.decompress(base64.b64decode(SOURCE_ALPHA_ZLIB_B64))
if len(raw) != SOURCE_W * SOURCE_H:
    raise SystemExit("Invalid embedded JETKIZ wordmark alpha source")
SOURCE = list(raw)


def sample_bilinear(x: float, y: float) -> int:
    if x < 0 or y < 0 or x > SOURCE_W - 1 or y > SOURCE_H - 1:
        return 0
    x0 = int(math.floor(x))
    y0 = int(math.floor(y))
    x1 = min(x0 + 1, SOURCE_W - 1)
    y1 = min(y0 + 1, SOURCE_H - 1)
    dx = x - x0
    dy = y - y0
    p00 = SOURCE[y0 * SOURCE_W + x0]
    p10 = SOURCE[y0 * SOURCE_W + x1]
    p01 = SOURCE[y1 * SOURCE_W + x0]
    p11 = SOURCE[y1 * SOURCE_W + x1]
    top = p00 * (1.0 - dx) + p10 * dx
    bottom = p01 * (1.0 - dx) + p11 * dx
    return max(0, min(255, round(top * (1.0 - dy) + bottom * dy)))


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    rows = bytearray()
    stride = width * 4
    for y in range(height):
        rows.append(0)
        rows.extend(rgba[y * stride : (y + 1) * stride])
    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(
        chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0),
        )
    )
    png.extend(chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
    png.extend(chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(png))


def generate_icon(
    path: Path,
    size: int,
    *,
    round_icon: bool = False,
    foreground_only: bool = False,
) -> None:
    pixels = bytearray(size * size * 4)
    logo_width_ratio = 0.76 if round_icon else 0.82
    if foreground_only:
        logo_width_ratio = 0.80
    logo_w = max(1, round(size * logo_width_ratio))
    logo_h = max(1, round(SOURCE_H * logo_w / SOURCE_W))
    ox = (size - logo_w) // 2
    oy = (size - logo_h) // 2
    radius = size / 2.0

    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4
            if foreground_only:
                r = g = b = 255
                bg_alpha = 0
            else:
                r, g, b = GREEN
                if round_icon:
                    dx = x + 0.5 - radius
                    dy = y + 0.5 - radius
                    bg_alpha = (
                        255 if dx * dx + dy * dy <= radius * radius else 0
                    )
                else:
                    bg_alpha = 255

            logo_alpha = 0
            if ox <= x < ox + logo_w and oy <= y < oy + logo_h:
                sx = (x - ox + 0.5) * SOURCE_W / logo_w - 0.5
                sy = (y - oy + 0.5) * SOURCE_H / logo_h - 0.5
                logo_alpha = sample_bilinear(sx, sy)

            if foreground_only:
                pixels[idx : idx + 4] = bytes((255, 255, 255, logo_alpha))
            elif logo_alpha:
                a = logo_alpha / 255.0
                rr = round(255 * a + r * (1.0 - a))
                gg = round(255 * a + g * (1.0 - a))
                bb = round(255 * a + b * (1.0 - a))
                pixels[idx : idx + 4] = bytes((rr, gg, bb, bg_alpha))
            else:
                pixels[idx : idx + 4] = bytes((r, g, b, bg_alpha))

    write_png(path, size, size, bytes(pixels))


for density, size in (
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
):
    generate_icon(RES / f"mipmap-{density}" / "ic_launcher.png", size)
    generate_icon(
        RES / f"mipmap-{density}" / "ic_launcher_round.png",
        size,
        round_icon=True,
    )

generate_icon(
    RES / "drawable-xxxhdpi" / "ic_launcher_foreground.png",
    432,
    foreground_only=True,
)

print("JETKIZ courier launcher icons generated")
