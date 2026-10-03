#!/usr/bin/env python3
"""Terrain, ground cover and sea textures (realism experiment).

Downloads CC0 ground scans (Poly Haven, ambientCG), conditions them for the
game (de-lit albedo at a physically plausible brightness, tileable, 1024^2)
and writes them to assets/textures/terrain/. Also generates, with fixed seeds:
  * sea_normal.png   tileable wave normal map (spectral synthesis)
  * sea_foam.png     tileable foam / lace noise (R lace, G bubbles, B fbm)
  * grass_cards.png  RGBA atlas of grass tuft sprites (2x2 cells) for the
                     3D grass tufts (assets/shaders/grass.gdshader)
  * grass_noise.png  small tileable noise used to place and tint things

Run from the project root:   python3 tools/textures/fetch_terrain.py
Downloads are cached in build/texture_sources/ (gitignored).
Outputs are committed; SOURCES.md is written next to them.
"""
import glob
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_common import (ROOT, ambientcg, credit, out, polyhaven, polyhaven_model,  # noqa: E402
                          save_normal, write_sources)

FAMILY = "terrain"
LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


# ------------------------------------------------------------- colour maths --

def to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def load_linear(path, size):
    im = Image.open(path).convert("RGB")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return to_linear(np.asarray(im).astype(np.float32) / 255.0)


def wrap_blur(a2d, radius):
    """Gaussian blur of a (H, W) float array that wraps around (keeps tiling)."""
    h, w = a2d.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    # Fourier transform of a Gaussian: exp(-2 pi^2 sigma^2 f^2). Periodic, so tiling is kept.
    kernel = np.exp(-2.0 * (math.pi * radius) ** 2 * (fx * fx + fy * fy))
    return np.fft.ifft2(np.fft.fft2(a2d) * kernel).real.astype(np.float32)


def condition(lin, target_lum, flatten=0.6, sat=1.0, tint=(1.0, 1.0, 1.0), blur=0.1):
    """De-lights the large-scale brightness (flatten 0..1), sets the average
    luminance (linear) and optionally desaturates / tints. Keeps hue detail."""
    lum = (lin * LUMA).sum(axis=2)
    low = wrap_blur(lum, lin.shape[0] * blur)
    gain = (low.mean() / np.maximum(low, 1e-4)) ** flatten
    lin = lin * gain[..., None]
    lum = (lin * LUMA).sum(axis=2)
    lin = lum[..., None] + (lin - lum[..., None]) * sat
    lin = lin * np.array(tint, dtype=np.float32)
    lin = lin * (target_lum / max((lin * LUMA).sum(axis=2).mean(), 1e-4))
    return np.clip(lin, 0.0, 1.0)


def save_linear_jpg(lin, dst, quality=90):
    img = Image.fromarray((to_srgb(lin) * 255.0 + 0.5).astype(np.uint8), "RGB")
    img.save(dst, quality=quality, optimize=True)


def pack_orm(ao_path, rough_path, dst, size):
    r = Image.open(rough_path).convert("L")
    r = r.resize((size, size), Image.LANCZOS) if r.size != (size, size) else r
    if ao_path:
        a = Image.open(ao_path).convert("L")
        a = a.resize((size, size), Image.LANCZOS) if a.size != (size, size) else a
    else:
        a = Image.new("L", (size, size), 255)
    Image.merge("RGB", (a, r, Image.new("L", (size, size), 0))).save(dst, optimize=True)


# --------------------------------------------------------- CC0 ground scans --

def scan_set(key, kind, asset, size, target_lum, flatten=0.6, sat=1.0, tint=(1, 1, 1),
             orm=True, normal=True, author="", use=""):
    if kind == "ph":
        m = polyhaven(asset, "1k")
        diff, nor, rough, ao = m["diff"], m.get("nor_gl"), m.get("rough"), m.get("ao")
        url = "https://polyhaven.com/a/" + asset
    else:
        m = ambientcg(asset, "1K")
        diff, nor, rough, ao = m["Color"], m.get("NormalGL"), m.get("Roughness"), m.get("AmbientOcclusion")
        url = "https://ambientcg.com/a/" + asset
    lin = condition(load_linear(diff, size), target_lum, flatten, sat, tint)
    save_linear_jpg(lin, out(FAMILY, "terrain_%s_albedo.jpg" % key))
    if normal and nor:
        save_normal(nor, out(FAMILY, "terrain_%s_normal.png" % key), size)
    if orm and rough:
        pack_orm(ao, rough, out(FAMILY, "terrain_%s_orm.png" % key), min(size, 512))
    credit(FAMILY, asset, author, url, "CC0 1.0", use)
    print("  %-10s %-18s lum -> %.2f" % (key, asset, target_lum))


def make_scans():
    print("scans")
    # Grass: the meadow. Tile ~2 m.
    scan_set("grass", "acg", "Grass004", 1024, 0.155, flatten=0.7, sat=0.95, author="ambientCG (Lennart Demes)",
             use="meadow ground texture")
    # Dry turf: dry patches, hill tops, field edges. Tile 2.5 m.
    scan_set("dry", "ph", "grass_ground", 1024, 0.20, flatten=0.8, sat=1.1, tint=(1.04, 1.0, 0.9), author="Poly Haven (Rob Tuytel)",
             use="dry grass patches")
    # Soil: loose dry earth. Tile 1.3 m.
    scan_set("dirt", "ph", "brown_mud_dry", 1024, 0.17, flatten=0.8, sat=0.7, author="Poly Haven (Rob Tuytel)", use="dirt fields, soil")
    # Rock: cliff face. Tile 2.7 m.
    scan_set("rock", "ph", "rock_face_03", 1024, 0.19, flatten=0.4, sat=0.7, tint=(1.0, 0.99, 0.97), author="Poly Haven (Rob Tuytel)",
             use="rock faces on steep slopes, boulders")
    # Beach sand: tile 1.5 m.
    scan_set("sand", "ph", "sand_01", 1024, 0.40, flatten=0.8, sat=0.6, tint=(1.0, 0.99, 0.95), author="Poly Haven (Rob Tuytel)",
             use="beach sand")
    # Macro tint for the dirt fields: scuffed patches and tracks. 20 m tile.
    print("  dirt macro")
    m = polyhaven("dirt_aerial_02", "1k")
    lin = condition(load_linear(m["diff"], 512), 0.20, flatten=0.3, sat=1.0)
    save_linear_jpg(lin, out(FAMILY, "terrain_dirt_macro_albedo.jpg"), 88)
    credit(FAMILY, "dirt_aerial_02", "Poly Haven (Rob Tuytel)", "https://polyhaven.com/a/dirt_aerial_02", "CC0 1.0",
           "macro tint and wear patches of the dirt fields")
    # Tyre-churned mud: tread prints and ruts (8 m tile), laid over the dirt fields.
    print("  churn")
    m = polyhaven("aerial_mud_1", "1k")
    lin = condition(load_linear(m["diff"], 512), 0.05, flatten=0.5, sat=0.8)
    save_linear_jpg(lin, out(FAMILY, "terrain_churn_albedo.jpg"), 88)
    save_normal(m["nor_gl"], out(FAMILY, "terrain_churn_normal.png"), 1024)
    credit(FAMILY, "aerial_mud_1", "Poly Haven (Rob Tuytel)", "https://polyhaven.com/a/aerial_mud_1", "CC0 1.0",
           "tyre tracks and ruts in the churned dirt fields")
    # Macro ripples for the beach sand: 30 m tile.
    print("  sand macro")
    m = polyhaven("aerial_beach_01", "1k")
    lin = condition(load_linear(m["diff"], 512), 0.40, flatten=0.4, sat=0.4)
    save_linear_jpg(lin, out(FAMILY, "terrain_sand_macro_albedo.jpg"), 88)
    credit(FAMILY, "aerial_beach_01", "Poly Haven (Rob Tuytel)", "https://polyhaven.com/a/aerial_beach_01", "CC0 1.0",
           "macro ripples and tone of the beach sand")


# ------------------------------------------------------- procedural: the sea --

def _kgrid(n):
    k = np.fft.fftfreq(n) * n
    kx, ky = np.meshgrid(k, k)
    return kx, ky, np.sqrt(kx * kx + ky * ky)


def spectral_height(n, rng, kmin, kmax, power, wind_deg=20.0, aniso=0.5):
    """Tileable random height field with a power-law spectrum, wind-aligned."""
    kx, ky, k = _kgrid(n)
    ang = math.radians(wind_deg)
    dirdot = (kx * math.cos(ang) + ky * math.sin(ang)) / np.maximum(k, 1e-6)
    spec = np.where((k >= kmin) & (k <= kmax), k ** (-power), 0.0)
    spec = spec * (1.0 - aniso + aniso * dirdot ** 2)
    noise = rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))
    h = np.fft.ifft2(noise * spec).real
    return h / max(h.std(), 1e-9)


def make_sea():
    print("sea")
    n = 1024
    rng = np.random.default_rng(1207)
    # Two bands summed so the map has both long ripples and fine chop.
    h = spectral_height(n, rng, 1, 30, 2.3, 20.0, 0.6) * 1.0
    h += spectral_height(n, rng, 14, 150, 1.8, 35.0, 0.4) * 0.30
    kx, ky, _ = _kgrid(n)
    H = np.fft.fft2(h)
    sx = np.fft.ifft2(1j * kx * H).real
    sy = np.fft.ifft2(1j * ky * H).real
    s = max(np.sqrt((sx ** 2 + sy ** 2)).std(), 1e-9)
    sx, sy = sx / s * 0.5, sy / s * 0.5  # about 0.5 rms slope: the shader scales it
    nz = np.ones_like(sx)
    ln = np.sqrt(sx * sx + sy * sy + nz * nz)
    rgb = np.stack([(-sx / ln) * 0.5 + 0.5, (sy / ln) * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=-1)
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(out(FAMILY, "sea_normal.png"), optimize=True)

    # Foam: R = lace (cell walls of a Worley pattern, F2 - F1), G = bubbles (F1),
    # B = soft cloudy fbm. The shader thresholds them.
    n2 = 512
    rng = np.random.default_rng(88)
    pts = rng.random((700, 2)) * n2
    yy, xx = np.mgrid[0:n2, 0:n2]
    f1 = np.full((n2, n2), 1e9, dtype=np.float32)
    f2 = np.full((n2, n2), 1e9, dtype=np.float32)
    for (px, py) in pts:
        dx = np.abs(xx - px)
        dx = np.minimum(dx, n2 - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, n2 - dy)
        d = np.sqrt(dx * dx + dy * dy).astype(np.float32)
        f2 = np.minimum(f2, np.maximum(f1, d))
        f1 = np.minimum(f1, d)
    lace = np.clip(1.0 - (f2 - f1) / 7.0, 0, 1) ** 1.5
    bub = np.clip(1.0 - f1 / 12.0, 0, 1)
    f3 = spectral_height(n2, rng, 2, 40, 1.4, 0.0, 0.0)
    soft = np.clip(f3 * 0.28 + 0.5, 0, 1)
    img = np.stack([lace, bub, soft], axis=-1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB").save(out(FAMILY, "sea_foam.png"), optimize=True)
    print("  sea_normal.png, sea_foam.png")


# ------------------------------------------------------ procedural: grass ----

def _bezier(p0, p1, p2, t):
    return ((1 - t) ** 2)[:, None] * p0 + (2 * (1 - t) * t)[:, None] * p1 + (t ** 2)[:, None] * p2


def draw_tuft(draw, cell, ss, rng, kind):
    """One grass tuft inside a cell of `cell` px (drawn at supersampling `ss`).
    Returns nothing; draws RGBA blades (sRGB colour, dark root to light tip)."""
    W = cell * ss
    cx = W * 0.5
    base_y = W * 0.97
    if kind == 0:      # meadow tuft: many medium blades
        n, hmin, hmax, spread, wmax, lean = 40, 0.45, 0.92, 0.10, 8, 0.55
    elif kind == 1:    # tall wispy grass with a few seed heads
        n, hmin, hmax, spread, wmax, lean = 22, 0.6, 0.98, 0.07, 8, 0.45
    elif kind == 2:    # short dense patch
        n, hmin, hmax, spread, wmax, lean = 46, 0.25, 0.55, 0.16, 9, 0.5
    else:              # lush broad blades
        n, hmin, hmax, spread, wmax, lean = 18, 0.4, 0.8, 0.07, 14, 0.5
    blades = []
    for i in range(n):
        x0 = cx + rng.normal(0, spread * W * 0.5)
        ln = rng.uniform(hmin, hmax) * W * (0.92 if kind != 1 else 1.0)
        side = rng.normal(0, lean)
        tip_x = x0 + side * ln * 0.55 + rng.normal(0, 0.05) * ln
        tip_y = base_y - ln * math.sqrt(max(1 - min(abs(tip_x - x0) / ln, 0.95) ** 2, 0.1))
        ctrl = np.array([x0 + (tip_x - x0) * 0.15, base_y - ln * 0.62])
        blades.append((x0, base_y, ctrl, np.array([tip_x, tip_y]), rng.uniform(0.6, 1.0) * wmax * ss * 0.5, rng.random()))
    blades.sort(key=lambda b: b[3][1])  # tall ones first (behind)
    for (x0, y0, ctrl, tip, hw, v) in blades:
        t = np.linspace(0, 1, 28)
        pts = _bezier(np.array([x0, y0]), ctrl, tip, t)
        tang = np.gradient(pts, axis=0)
        tang /= np.maximum(np.linalg.norm(tang, axis=1, keepdims=True), 1e-6)
        nrm = np.stack([-tang[:, 1], tang[:, 0]], axis=1)
        width = hw * (1 - t ** 1.6) * (0.35 + 0.65 * np.minimum(t * 6, 1.0)) + 0.4
        left = pts + nrm * width[:, None]
        right = pts - nrm * width[:, None]
        poly = [tuple(p) for p in left] + [tuple(p) for p in right[::-1]]
        # colour: dark root -> mid -> light tip, blade-to-blade variation, a bit of straw
        base = np.array([0.03, 0.065, 0.015]) * rng.uniform(0.85, 1.15)
        mid = np.array([0.10, 0.17, 0.04]) * rng.uniform(0.85, 1.2)
        tipc = np.array([0.21, 0.29, 0.08]) * rng.uniform(0.85, 1.2)
        straw = np.array([0.34, 0.28, 0.12])
        if v > 0.88:
            tipc = tipc * 0.5 + straw * 0.5
        # draw the blade as a few shaded segments
        segs = 7
        for s in range(segs):
            a, b = s * (len(t) - 1) // segs, (s + 1) * (len(t) - 1) // segs
            f = (s + 0.5) / segs
            col = base * (1 - f) + mid * min(f * 2, 1.0) if f < 0.5 else mid * (1 - (f - 0.5) * 2) + tipc * ((f - 0.5) * 2)
            seg = [tuple(p) for p in left[a:b + 2]] + [tuple(p) for p in right[a:b + 2][::-1]]
            if len(seg) >= 3:
                draw.polygon(seg, fill=tuple(int(c * 255) for c in to_srgb(col)) + (255,))
    if kind == 1:  # seed heads on a couple of stems
        for i in range(4):
            x0 = cx + rng.normal(0, spread * W * 0.4)
            top = base_y - rng.uniform(0.7, 0.98) * W
            sway = rng.normal(0, 0.05) * W
            draw.line([(x0, base_y), (x0 + sway * 0.4, base_y - (base_y - top) * 0.6), (x0 + sway, top)], fill=(120, 140, 70, 255), width=max(1, ss))
            for k in range(7):
                yy = top + k * W * 0.014
                draw.ellipse([x0 + sway - ss * 1.6, yy, x0 + sway + ss * 1.6, yy + ss * 3.6], fill=(176, 160, 90, 255))


def make_grass_cards():
    print("grass cards")
    cell = 512
    ss = 4
    rng = np.random.default_rng(5)
    atlas = Image.new("RGBA", (cell * 2, cell * 2), (0, 0, 0, 0))
    for idx in range(4):
        tile = Image.new("RGBA", (cell * ss, cell * ss), (0, 0, 0, 0))
        draw_tuft(ImageDraw.Draw(tile), cell, ss, rng, idx)
        # Downsample colour premultiplied so edges don't get dark fringes.
        a = np.asarray(tile).astype(np.float32) / 255.0
        alpha = a[..., 3]
        rgb = a[..., :3] * alpha[..., None]
        def down(x):
            return x.reshape(cell, ss, cell, ss, -1).mean(axis=(1, 3))
        alpha_d = down(alpha[..., None])[..., 0]
        rgb_d = down(rgb)
        rgb_d = rgb_d / np.maximum(alpha_d[..., None], 1e-4)
        # Bleed colour outwards into transparent texels (clean mip-mapped alpha edges).
        col = Image.fromarray((np.clip(rgb_d, 0, 1) * 255).astype(np.uint8), "RGB")
        mask = alpha_d > 0.02
        filled = np.array(col)
        for r in (3, 8, 20):
            blurred = np.asarray(col.filter(ImageFilter.GaussianBlur(r))).astype(np.float32)
            wmask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255.0
            est = (blurred / np.maximum(wmask[..., None], 0.02))
            filled = np.where(mask[..., None], filled, np.clip(est, 0, 255).astype(np.uint8))
        out_a = (np.clip(alpha_d * 1.15, 0, 1) * 255).astype(np.uint8)
        cellimg = Image.fromarray(np.dstack([filled, out_a]), "RGBA")
        atlas.paste(cellimg, ((idx % 2) * cell, (idx // 2) * cell))
    atlas.save(out(FAMILY, "grass_cards.png"), optimize=True)
    print("  grass_cards.png")


def make_noise():
    """Tileable value-noise map: R/G/B = three octave bands, A = soft."""
    n = 256
    rng = np.random.default_rng(31)
    chans = []
    for (lo, hi, p) in [(1, 8, 1.2), (6, 30, 1.2), (20, 100, 1.0), (1, 4, 1.0)]:
        h = spectral_height(n, rng, lo, hi, p, 0.0, 0.0)
        chans.append(np.clip(h * 0.18 + 0.5, 0, 1))
    img = np.stack(chans, axis=-1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(out(FAMILY, "grass_noise.png"), optimize=True)
    print("  grass_noise.png")


# ---------------------------------------------------------------- boulders --

ROCK_SETS = {"rock_moss_set_01": "a", "rock_moss_set_02": "b"}


def make_rocks():
    """Boulder models (Poly Haven rock sets, CC0): downloads them, lets Blender
    split and decimate them (tools/blender/make_nature_rocks.py ->
    assets/models/nature/rocks_a.glb, rocks_b.glb) and conditions their textures."""
    print("rocks")
    for asset, key in ROCK_SETS.items():
        polyhaven_model(asset, "1k")
        folder = os.path.join(ROOT, "build", "texture_sources", "models", asset + "_1k", "textures")
        diff = glob.glob(os.path.join(folder, "*_diff_1k.*"))[0]
        nor = glob.glob(os.path.join(folder, "*_nor_gl_1k.*"))[0]
        rough = glob.glob(os.path.join(folder, "*_rough_1k.*"))[0]
        arm = glob.glob(os.path.join(folder, "*_arm_1k.*"))
        lin = condition(load_linear(diff, 1024), 0.17, flatten=0.0, sat=0.85)
        save_linear_jpg(lin, out(FAMILY, "rocks_%s_albedo.jpg" % key))
        save_normal(nor, out(FAMILY, "rocks_%s_normal.png" % key), 1024)
        pack_orm(arm[0] if arm else None, rough, out(FAMILY, "rocks_%s_orm.png" % key), 1024)
        credit(FAMILY, asset, "Poly Haven", "https://polyhaven.com/a/" + asset, "CC0 1.0",
               "boulder models (assets/models/nature/rocks_%s.glb) and their textures" % key)
    subprocess.run(["blender", "-b", "-P", os.path.join(ROOT, "tools", "blender", "make_nature_rocks.py")], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)


def main():
    make_scans()
    make_rocks()
    make_sea()
    make_grass_cards()
    make_noise()
    credit(FAMILY, "sea_normal, sea_foam, grass_cards, grass_noise", "Turbo Town (generated)", "tools/textures/fetch_terrain.py",
           "n/a (own work)", "procedural, fixed seeds")
    write_sources(FAMILY)
    print("done")


if __name__ == "__main__":
    main()
