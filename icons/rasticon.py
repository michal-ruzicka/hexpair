#!/usr/bin/env python3
"""Tiny pure-stdlib vector rasterizer plus a PNG/ICO encoder.

Built for build.py, which renders icons/*.ico for the Explorer
context-menu entries in vimhex-contex-entry.add.reg. No Pillow or
ImageMagick dependency, on purpose - the plugin itself never reaches for an
external tool it can implement in what it already depends on, and asset
generation follows the same rule with what the standard library gives it.

Icons are defined as draw calls against a Canvas in 0..1 unit-square
coordinates (see design.py), so one spec renders cleanly at any pixel size:
each target size is rendered at 4x supersample resolution with simple
hard-edged primitives, then box-downsampled for antialiasing.
"""

import struct
import zlib

SUPERSAMPLE = 4


class Canvas:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.buf = [[0.0, 0.0, 0.0, 0.0] for _ in range(w * h)]

    def blend(self, x, y, rgba):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        r, g, b, a = rgba
        a /= 255.0
        px = self.buf[y * self.w + x]
        px[0] = r * a + px[0] * (1 - a)
        px[1] = g * a + px[1] * (1 - a)
        px[2] = b * a + px[2] * (1 - a)
        px[3] = a * 255 + px[3] * (1 - a)

    def to_rgba_bytes(self):
        out = bytearray(self.w * self.h * 4)
        i = 0
        for r, g, b, a in self.buf:
            out[i] = int(round(min(255, max(0, r))))
            out[i + 1] = int(round(min(255, max(0, g))))
            out[i + 2] = int(round(min(255, max(0, b))))
            out[i + 3] = int(round(min(255, max(0, a))))
            i += 4
        return bytes(out)

    def downsample(self, factor):
        w2, h2 = self.w // factor, self.h // factor
        out = Canvas(w2, h2)
        n = factor * factor
        for y in range(h2):
            for x in range(w2):
                r = g = b = a = 0.0
                for dy in range(factor):
                    row = (y * factor + dy) * self.w
                    for dx in range(factor):
                        px = self.buf[row + x * factor + dx]
                        r += px[0]
                        g += px[1]
                        b += px[2]
                        a += px[3]
                out.buf[y * w2 + x] = [r / n, g / n, b / n, a / n]
        return out


def _bbox_px(canvas, x0, y0, x1, y1):
    ix0 = max(0, int(x0 * canvas.w) - 1)
    iy0 = max(0, int(y0 * canvas.h) - 1)
    ix1 = min(canvas.w, int(x1 * canvas.w) + 2)
    iy1 = min(canvas.h, int(y1 * canvas.h) + 2)
    return ix0, iy0, ix1, iy1


def fill_rect(canvas, x0, y0, x1, y1, color):
    ix0, iy0, ix1, iy1 = _bbox_px(canvas, x0, y0, x1, y1)
    for py in range(iy0, iy1):
        for px in range(ix0, ix1):
            canvas.blend(px, py, color)


def fill_round_rect(canvas, x0, y0, x1, y1, r, color):
    """A rect, or - within r of a corner - a quarter-circle test there."""
    ix0, iy0, ix1, iy1 = _bbox_px(canvas, x0, y0, x1, y1)
    rx0, ry0, rx1, ry1 = x0 * canvas.w, y0 * canvas.h, x1 * canvas.w, y1 * canvas.h
    rr = r * canvas.w
    for py in range(iy0, iy1):
        cy = py + 0.5
        for px in range(ix0, ix1):
            cx = px + 0.5
            if cx < rx0 or cx > rx1 or cy < ry0 or cy > ry1:
                continue
            if cx < rx0 + rr and cy < ry0 + rr:
                if (cx - (rx0 + rr)) ** 2 + (cy - (ry0 + rr)) ** 2 > rr * rr:
                    continue
            elif cx > rx1 - rr and cy < ry0 + rr:
                if (cx - (rx1 - rr)) ** 2 + (cy - (ry0 + rr)) ** 2 > rr * rr:
                    continue
            elif cx < rx0 + rr and cy > ry1 - rr:
                if (cx - (rx0 + rr)) ** 2 + (cy - (ry1 - rr)) ** 2 > rr * rr:
                    continue
            elif cx > rx1 - rr and cy > ry1 - rr:
                if (cx - (rx1 - rr)) ** 2 + (cy - (ry1 - rr)) ** 2 > rr * rr:
                    continue
            canvas.blend(px, py, color)


def fill_triangle(canvas, p0, p1, p2, color):
    """Point-in-triangle via the sign of three edge cross products."""
    xs = [p0[0], p1[0], p2[0]]
    ys = [p0[1], p1[1], p2[1]]
    ix0, iy0, ix1, iy1 = _bbox_px(canvas, min(xs), min(ys), max(xs), max(ys))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    for py in range(iy0, iy1):
        fy = (py + 0.5) / canvas.h
        for px in range(ix0, ix1):
            fx = (px + 0.5) / canvas.w
            d1 = cross(p0, p1, (fx, fy))
            d2 = cross(p1, p2, (fx, fy))
            d3 = cross(p2, p0, (fx, fy))
            neg = d1 < 0 or d2 < 0 or d3 < 0
            pos = d1 > 0 or d2 > 0 or d3 > 0
            if not (neg and pos):
                canvas.blend(px, py, color)


# A tiny 5x7 dot-matrix font, just the glyphs the badges actually use - add a
# row here (7 strings of 5 '0'/'1' chars) before using a new character.
FONT_5X7 = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
}


def draw_glyph(canvas, ch, x0, y0, x1, y1, color):
    rows = FONT_5X7[ch]
    cw = (x1 - x0) / 5
    ch_ = (y1 - y0) / 7
    for ry, row in enumerate(rows):
        for rx, bit in enumerate(row):
            if bit == "1":
                gx0 = x0 + rx * cw
                gy0 = y0 + ry * ch_
                fill_rect(canvas, gx0, gy0, gx0 + cw, gy0 + ch_, color)


def draw_text(canvas, text, x0, y0, x1, y1, color, gap=0.08):
    n = len(text)
    total_gap = gap * (n - 1) if n > 1 else 0
    cw = (x1 - x0 - total_gap) / n
    x = x0
    for ch in text:
        draw_glyph(canvas, ch, x, y0, x + cw, y1, color)
        x += cw + gap


# --- PNG / ICO encoding, stdlib only ---------------------------------------
def png_encode(width, height, rgba_bytes):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type: None
        raw.extend(rgba_bytes[y * stride : (y + 1) * stride])
    idat = zlib.compress(bytes(raw), 9)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def ico_encode(images):
    """images: [(size, png_bytes), ...]. Vista+ PNG-in-ICO: each entry's
    data is simply a whole PNG file; size 256 is stored as 0 (the ICO
    format's own way of saying 256, since the field is one byte)."""
    n = len(images)
    header = struct.pack("<HHH", 0, 1, n)
    entries = bytearray()
    offset = 6 + 16 * n
    blob = bytearray()
    for size, png in images:
        w = h = 0 if size == 256 else size
        entries += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(png), offset)
        blob += png
        offset += len(png)
    return header + bytes(entries) + bytes(blob)


def render_png(spec_fn, size, supersample=SUPERSAMPLE):
    canvas = Canvas(size * supersample, size * supersample)
    spec_fn(canvas)
    small = canvas.downsample(supersample)
    return png_encode(small.w, small.h, small.to_rgba_bytes())
