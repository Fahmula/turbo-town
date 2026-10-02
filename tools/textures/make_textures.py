#!/usr/bin/env python3
"""Generates the world's small detail textures (ART_BIBLE.md §8).

Run from the project root:

    python3 tools/textures/make_textures.py

Needs NumPy and Pillow. Every texture is tileable and uses fixed seeds, so
re-running reproduces the same files. Outputs (PNG, committed):

  assets/textures/ground/ground_detail.png   512², linear data, tiles every 4 m
      R  fine aggregate grain (asphalt stones, concrete pores), mean ~0.5
      G  mid-size blotches (0.3-1.5 m): wear, stains, slab tint
      B  crack lines (1 on a crack) for crack sealing and old concrete
      A  soft large-scale variation inside the tile
  assets/textures/sky/clouds.png             512², linear data, tiles across the sky
      R  fair-weather cumulus coverage (billowy, mostly clear)
      G  fine detail used to erode the cloud edges
      B  thin high-altitude streaks (cirrus)
  assets/textures/water/water_normal.png     512², tangent-space normal map of
      gentle wind ripples (tileable; import as a normal map)
  assets/textures/foliage/leaves_broadleaf.png  512² RGBA, alpha-scissor leaf clusters
  assets/textures/foliage/leaves_conifer.png    512² RGBA, alpha-scissor needle sprays
  assets/textures/foliage/leaves_palm.png       512² RGBA, two palm fronds (one per
      half, base at the left, tip at the right)
      RGB  greyscale value variation (the tree's colour comes from vertex colour)
      A    leaf coverage (alpha scissor at 0.5)

Godot imports them VRAM compressed (BPTC) with mipmaps; the .import files
are committed next to the PNGs.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures"
SIZE = 512


# ---------------------------------------------------------------- noise kit --

def _lattice(size, cells):
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * f * (f * (f * 6 - 15) + 10)  # quintic fade
    return i0 % cells, (i0 + 1) % cells, f


def value_noise(size, cells, rng, cells_y=None):
    """Tileable smooth value noise: `cells` lattice cells across the tile
    (`cells_y` down it, for stretched noise)."""
    cy = cells if cells_y is None else cells_y
    grid = rng.random((cy, cells))
    x0, x1, fx = _lattice(size, cells)
    y0, y1, fy = _lattice(size, cy)
    # rows (y) then columns (x)
    a = grid[np.ix_(y0, x0)]
    b = grid[np.ix_(y0, x1)]
    c = grid[np.ix_(y1, x0)]
    d = grid[np.ix_(y1, x1)]
    fx = fx[None, :]
    fy = fy[:, None]
    top = a + (b - a) * fx
    bot = c + (d - c) * fx
    return top + (bot - top) * fy


def fbm(size, base_cells, octaves, rng, gain=0.5):
    out = np.zeros((size, size))
    amp = 1.0
    total = 0.0
    cells = base_cells
    for _ in range(octaves):
        out += value_noise(size, cells, rng) * amp
        total += amp
        amp *= gain
        cells *= 2
        if cells > size:
            break
    return out / total


def worley(size, cells, rng, jitter=0.9):
    """Tileable cellular noise: returns (F1, F2) distances in cell units."""
    pts = rng.random((cells, cells, 2)) * jitter + (1 - jitter) * 0.5
    ys, xs = np.mgrid[0:size, 0:size] * (cells / size)
    cx = np.floor(xs).astype(int)
    cy = np.floor(ys).astype(int)
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx = cx + ox
            gy = cy + oy
            p = pts[gy % cells, gx % cells]
            dx = gx + p[..., 0] - xs
            dy = gy + p[..., 1] - ys
            d = np.sqrt(dx * dx + dy * dy)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


def normalize(a, lo=0.0, hi=1.0):
    a = (a - a.min()) / max(a.max() - a.min(), 1e-9)
    return lo + a * (hi - lo)


def wrap_blur(a, radius):
    """Gaussian blur that wraps around the tile edges (FFT, so it's periodic)."""
    n = a.shape[0]
    f = np.fft.fftfreq(n)
    g = np.exp(-2.0 * (np.pi * radius) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def to_u8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def save_rgba(path, r, g, b, a):
    path.parent.mkdir(parents=True, exist_ok=True)
    img = np.stack([to_u8(r), to_u8(g), to_u8(b), to_u8(a)], axis=-1)
    Image.fromarray(img, "RGBA").save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


# ------------------------------------------------------------ ground detail --

def make_ground_detail():
    rng = np.random.default_rng(1234)
    # R: aggregate grain. Speckles from fine noise plus sparse brighter and
    # darker stones (cellular cells), lightly blurred so it isn't harsh.
    fine = fbm(SIZE, 128, 2, rng)
    f1, f2 = worley(SIZE, 96, rng)
    stones = np.clip(1.0 - f1 * 2.2, 0, 1)
    tone = value_noise(SIZE, 96, rng)  # each stone lighter or darker
    grain = 0.5 + (fine - 0.5) * 0.9 + (stones * (tone - 0.5)) * 0.9
    grain = wrap_blur(grain, 0.6)
    grain = normalize(grain, 0.08, 0.92)
    grain = 0.5 + (grain - grain.mean())
    # G: mid-size blotches.
    blot = fbm(SIZE, 6, 5, rng, gain=0.55)
    blot = normalize(blot)
    # B: crack lines along cell edges, wobbly, of varying strength.
    warp_x = fbm(SIZE, 8, 3, rng) - 0.5
    warp_y = fbm(SIZE, 8, 3, rng) - 0.5
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    wx = ((xs + warp_x * 40) % SIZE).astype(int)
    wy = ((ys + warp_y * 40) % SIZE).astype(int)
    c1, c2 = worley(SIZE, 5, rng)
    edge = (c2 - c1)[wy, wx]
    crack = np.clip(1.0 - edge / 0.035, 0, 1) ** 1.5
    strength = np.clip(fbm(SIZE, 4, 3, rng) * 2.2 - 0.6, 0, 1)
    crack = crack * strength
    # A: soft variation across the tile.
    soft = normalize(fbm(SIZE, 2, 4, rng, gain=0.6))
    save_rgba(OUT / "ground" / "ground_detail.png", grain, blot, crack, soft)


# ------------------------------------------------------------------- clouds --

def make_clouds():
    rng = np.random.default_rng(77)
    # Billowy cumulus: cellular blobs (inverted F1) shaped by fbm, then a
    # threshold-friendly curve so most of the sky stays clear.
    f1, _ = worley(SIZE, 7, rng)
    blobs = np.clip(1.0 - f1 * 1.15, 0, 1)
    f1b, _ = worley(SIZE, 15, rng)
    small = np.clip(1.0 - f1b * 1.2, 0, 1)
    shape = fbm(SIZE, 4, 5, rng, gain=0.55)
    cover = blobs * 0.65 + small * 0.25 + (shape - 0.5) * 0.6
    cover = normalize(wrap_blur(cover, 2.0))
    detail = normalize(fbm(SIZE, 16, 4, rng, gain=0.6))
    # Cirrus: stretched noise.
    streak = value_noise(SIZE, 4, rng, 24) * 0.6 + value_noise(SIZE, 8, rng, 64) * 0.4
    streak = normalize(streak)
    save_rgba(OUT / "sky" / "clouds.png", cover, detail, streak, np.ones_like(cover))


# -------------------------------------------------------------------- water --

def make_water_normal():
    rng = np.random.default_rng(91)
    # Ripples: stretched noise at a few scales (wind from one side), as height.
    h = value_noise(SIZE, 6, rng, 10) * 0.5 + value_noise(SIZE, 12, rng, 22) * 0.3 + fbm(SIZE, 24, 3, rng) * 0.2
    h = wrap_blur(h, 1.2)
    strength = 6.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * SIZE / 64.0 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * SIZE / 64.0 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgb = n * 0.5 + 0.5
    path = OUT / "water" / "water_normal.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(to_u8(rgb), "RGB").save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


# ------------------------------------------------------------------ foliage --

def _leaf_poly(cx, cy, length, width, ang):
    """A pointed leaf outline (list of points) centred on its stalk end."""
    pts = []
    for t in np.linspace(0, 1, 9):
        w = np.sin(np.pi * t) ** 0.8 * width * 0.5
        pts.append((t * length, w))
    for t in np.linspace(1, 0, 9)[1:-1]:
        w = np.sin(np.pi * t) ** 0.8 * width * 0.5
        pts.append((t * length, -w))
    ca, sa = np.cos(ang), np.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def make_leaves(name, seed, conifer):
    """A 2x2 atlas of leaf clusters (each a quarter of the texture), drawn at
    4x and downsampled for clean edges. Value varies leaf to leaf; colour comes
    from the tree's vertex colour."""
    rng = np.random.default_rng(seed)
    S = SIZE * 4
    cell = S // 2
    rgb = Image.new("L", (S, S), 0)
    alpha = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(rgb)
    da = ImageDraw.Draw(alpha)
    for qy in range(2):
        for qx in range(2):
            ox, oy = qx * cell, qy * cell
            cx, cy = ox + cell / 2, oy + cell / 2
            if conifer:
                # Needle sprays: a few twigs radiating from the bottom centre,
                # each lined with short needles.
                for twig in range(9):
                    ang = -np.pi / 2 + rng.uniform(-0.9, 0.9)
                    length = cell * rng.uniform(0.55, 0.8)
                    bx, by = cx + rng.uniform(-0.05, 0.05) * cell, oy + cell * 0.92
                    steps = 26
                    for s in range(steps):
                        t = s / steps
                        px = bx + np.cos(ang) * length * t
                        py = by + np.sin(ang) * length * t
                        for side in (-1, 1):
                            na = ang + side * rng.uniform(0.7, 1.1)
                            nl = cell * 0.11 * (1.0 - t * 0.55)
                            v = int(rng.uniform(150, 255))
                            poly = _leaf_poly(px, py, nl, cell * 0.022, na)
                            dr.polygon(poly, fill=v)
                            da.polygon(poly, fill=255)
            else:
                # Broadleaf cluster: many leaves around a loose round mass.
                for leaf in range(150):
                    r = cell * 0.40 * np.sqrt(rng.random())
                    a = rng.random() * 2 * np.pi
                    lx = cx + np.cos(a) * r
                    ly = cy + np.sin(a) * r
                    length = cell * rng.uniform(0.11, 0.17)
                    width = length * rng.uniform(0.45, 0.6)
                    ang = a + rng.uniform(-0.8, 0.8)
                    v = int(rng.uniform(140, 255))
                    poly = _leaf_poly(lx, ly, length, width, ang)
                    dr.polygon(poly, fill=v)
                    da.polygon(poly, fill=255)
    rgb = rgb.resize((SIZE, SIZE), Image.LANCZOS)
    alpha = alpha.resize((SIZE, SIZE), Image.LANCZOS)
    v = np.asarray(rgb).astype(np.float32) / 255.0
    a = np.asarray(alpha).astype(np.float32) / 255.0
    # Un-premultiply the edge pixels so the value doesn't darken at the rim.
    v = np.where(a > 0.01, v / np.maximum(a, 0.01), 0.75)
    v = np.clip(v, 0, 1)
    # Bleed colour into the empty area so mipmaps don't darken edges.
    v = np.where(a > 0.01, v, 0.75)
    save_rgba(OUT / "foliage" / f"leaves_{name}.png", v, v, v, a)


def make_palm():
    """Two palm fronds, each filling half the texture: a midrib from the left
    edge to the right, long leaflets angled toward the tip on both sides,
    drooping a little, shorter near the base and the tip."""
    rng = np.random.default_rng(57)
    S = SIZE * 4
    rgb = Image.new("L", (S, S), 0)
    alpha = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(rgb)
    da = ImageDraw.Draw(alpha)
    for half in range(2):
        cy = S * (0.25 + 0.5 * half)
        x0, x1 = S * 0.02, S * 0.98
        # Midrib.
        dr.line([(x0, cy), (x1, cy)], fill=120, width=int(S * 0.008))
        da.line([(x0, cy), (x1, cy)], fill=255, width=int(S * 0.008))
        n = 46
        for i in range(n):
            t = (i + 0.5) / n
            x = x0 + (x1 - x0) * t
            length = S * 0.22 * np.sin(np.pi * t) ** 0.6 + S * 0.015
            for side in (-1, 1):
                # Leaflets angled toward the tip (+x) and outward.
                dx = np.cos(0.55) * length
                dy = side * np.sin(0.75) * length * rng.uniform(0.85, 1.0)
                v = int(rng.uniform(150, 250))
                poly = _leaf_poly(x, cy, length, min(S * 0.018, length * 0.25), np.arctan2(dy, dx))
                dr.polygon(poly, fill=v)
                da.polygon(poly, fill=255)
    rgb = rgb.resize((SIZE, SIZE), Image.LANCZOS)
    alpha = alpha.resize((SIZE, SIZE), Image.LANCZOS)
    v = np.asarray(rgb).astype(np.float32) / 255.0
    a = np.asarray(alpha).astype(np.float32) / 255.0
    v = np.where(a > 0.01, v / np.maximum(a, 0.01), 0.75)
    v = np.clip(v, 0, 1)
    v = np.where(a > 0.01, v, 0.75)
    save_rgba(OUT / "foliage" / "leaves_palm.png", v, v, v, a)


if __name__ == "__main__":
    make_ground_detail()
    make_clouds()
    make_water_normal()
    make_leaves("broadleaf", 31, conifer=False)
    make_leaves("conifer", 32, conifer=True)
    make_palm()
