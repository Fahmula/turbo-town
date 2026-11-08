#!/usr/bin/env python3
"""Garage decals for car_paint_custom.gdshader (ART_BIBLE.md §12 liveries).

Writes two single-channel masks (white = ink; the shader colours them):

* assets/textures/vehicle/decals.png: the side graphics, one 4:1 strip per
  row (1024 x 256 each), in PartsCatalog.DECALS row order. Each strip's left
  edge is its anchor (the nose for mode 0, the tail for mode 1; mode 2
  strips are stretched nose to tail), so graphics flow from left to right.
* assets/textures/vehicle/digits.png: race-number digits 0-9 in one row,
  each cell as wide as 0.652 x its height (the shader's glyph box,
  gw / gh in pc_digits).

All shapes are made up (no real liveries, logos or brands). The digits are
set in Fira Sans ExtraBold (SIL OFL 1.1) from the system font folder; only
the glyph shapes end up in the PNG, no font file is shipped.

Run from the project root: python3 tools/textures/make_decals.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "vehicle")
FONT = "/usr/share/fonts/TTF/FiraSans-ExtraBold.ttf"

W, H = 1024, 256          # one strip
SS = 3                    # supersampling for smooth edges
ROWS = ["flames", "lightning", "stars", "checker", "speed", "splash"]


def canvas():
    img = Image.new("L", (W * SS, H * SS), 0)
    return img, ImageDraw.Draw(img)


def P(x, y):
    """Strip coordinates (0..1 along, 0..1 down) to supersampled pixels."""
    return (x * W * SS, y * H * SS)


def finish(img):
    return img.resize((W, H), Image.LANCZOS)


# ---------------------------------------------------------------- flames ---

def flames():
    """Hot-rod flames: fat tongues from the nose that thin out as they lick
    back, each with a wave and a tip that kicks up."""
    img, d = canvas()
    # (root centre height, length, root width, wave phase)
    tongues = [(0.28, 0.56, 0.34, 0.3), (0.50, 0.92, 0.44, 1.6), (0.70, 0.70, 0.36, 2.9),
               (0.40, 0.74, 0.30, 4.1), (0.84, 0.42, 0.24, 5.0)]
    for (yc, length, w0, ph) in tongues:
        top, bot = [], []
        n = 80
        for k in range(n + 1):
            t = k / n
            x = t * length
            y = yc + 0.07 * math.sin(t * math.pi * 2.2 + ph) * min(t * 3.0, 1.0) - 0.12 * t ** 3
            half = w0 * 0.5 * (1.0 - t) ** 0.8
            top.append(P(x, y - half))
            bot.append(P(x, y + half))
        d.polygon(top + bot[::-1], fill=255)
    return finish(img)


# ------------------------------------------------------------- lightning ---

def lightning():
    """A long bolt zigzagging along the side, with a thin stripe under it."""
    img, d = canvas()
    xs = [0.0, 0.16, 0.26, 0.44, 0.53, 0.72, 0.80, 1.0]
    ys = [0.50, 0.36, 0.58, 0.38, 0.60, 0.40, 0.58, 0.46]
    top, bot = [], []
    for i, (x, y) in enumerate(zip(xs, ys)):
        t = i / (len(xs) - 1)
        half = 0.13 * (1.0 - 0.75 * t) + 0.01
        top.append(P(x, y - half))
        bot.append(P(x, y + half))
    d.polygon(top + bot[::-1], fill=255)
    d.rectangle([P(0.0, 0.80), P(0.97, 0.84)], fill=255)
    return finish(img)


# ----------------------------------------------------------------- stars ---

def _star(d, cx, cy, r, rot=0.0):
    pts = []
    for k in range(10):
        ang = rot - math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.42
        pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
    d.polygon(pts, fill=255)


def stars():
    """Stars, big at the tail, getting smaller toward the front."""
    img, d = canvas()
    rng = random.Random(7)
    x = 0.07
    r = 0.62
    while x < 0.95 and r > 0.06:
        y = 0.5 + rng.uniform(-0.22, 0.22) * (1.0 - r)
        _star(d, *P(x, y), r * H * SS * 0.5, rng.uniform(-0.3, 0.3))
        x += r * 0.3 + 0.03
        r *= 0.8
    return finish(img)


# --------------------------------------------------------------- checker ---

def checker():
    """A checkered band at the tail that breaks up toward the front."""
    img, d = canvas()
    rng = random.Random(3)
    s = H // 5                          # square size in strip pixels
    cols = W // s
    for c in range(cols):
        keep = 1.0 if c < 6 else max(0.0, 1.0 - (c - 5) / 7.0)
        for r in range(1, 4):
            if (c + r) % 2:
                continue
            if rng.random() > keep:
                continue
            x0, y0 = c * s * SS, r * s * SS
            d.rectangle([x0, y0, x0 + s * SS - 1, y0 + s * SS - 1], fill=255)
    return finish(img)


# ----------------------------------------------------------------- speed ---

def speed():
    """Three speed stripes, pointed at the front, along the whole side."""
    img, d = canvas()
    for (y, half, x0, x1) in ((0.36, 0.055, 0.10, 0.97), (0.55, 0.075, 0.04, 0.97), (0.73, 0.03, 0.22, 0.97)):
        d.polygon([P(x0, y), P(x0 + 0.08, y - half), P(x1, y - half), P(x1, y + half), P(x0 + 0.08, y + half)], fill=255)
    return finish(img)


# ---------------------------------------------------------------- splash ---

def splash():
    """A paint splat with drops flying toward the front."""
    import numpy as np
    w, h = W * SS, H * SS
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    field = np.zeros((h, w), np.float32)
    rng = random.Random(11)

    def blob(cx, cy, r):
        nonlocal field
        cxp, cyp, rp = cx * w, cy * h, r * h
        field += np.exp(-(((xx - cxp) ** 2 + (yy - cyp) ** 2) / (rp * rp)))

    blob(0.3, 0.5, 0.32)
    for _ in range(14):
        a = rng.uniform(0, 2 * math.pi)
        dist = rng.uniform(0.18, 0.36)
        blob(0.3 + math.cos(a) * dist * 0.28, 0.5 + math.sin(a) * dist, rng.uniform(0.06, 0.12))
    x = 0.44
    while x < 0.9:
        blob(x, 0.5 + rng.uniform(-0.25, 0.25), rng.uniform(0.03, 0.08) * (1.1 - x))
        x += rng.uniform(0.04, 0.09)
    mask = np.clip((field - 0.5) * 40.0, 0, 1) * 255
    return finish(Image.fromarray(mask.astype("uint8")))


# ---------------------------------------------------------------- digits ---

def digits():
    cell_h = 256
    cell_w = int(round(cell_h * 0.652))
    img = Image.new("L", (cell_w * 10 * SS, cell_h * SS), 0)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(cell_h * SS * 1.08))
    for n in range(10):
        ch = str(n)
        box = d.textbbox((0, 0), ch, font=font)
        gw, gh = box[2] - box[0], box[3] - box[1]
        x = n * cell_w * SS + (cell_w * SS - gw) / 2 - box[0]
        y = (cell_h * SS - gh) / 2 - box[1]
        d.text((x, y), ch, font=font, fill=255)
    return img.resize((cell_w * 10, cell_h), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    makers = {"flames": flames, "lightning": lightning, "stars": stars, "checker": checker, "speed": speed, "splash": splash}
    atlas = Image.new("L", (W, H * len(ROWS)), 0)
    for i, name in enumerate(ROWS):
        strip = makers[name]()
        # Keep a clear border so mipmaps never bleed between rows or wrap.
        border = Image.new("L", (W, H), 0)
        border.paste(strip.crop((0, 4, W - 4, H - 4)), (0, 4))
        atlas.paste(border, (0, i * H))
    atlas.save(os.path.join(OUT_DIR, "decals.png"))
    digits().save(os.path.join(OUT_DIR, "digits.png"))
    print("wrote decals.png", atlas.size, "and digits.png")


if __name__ == "__main__":
    main()
