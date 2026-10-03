#!/usr/bin/env python3
"""Building facade textures (realism branch, ART_BIBLE.md §15 / facade.gdshader).

Downloads four CC0 Poly Haven wall scans and packs them into 2x2 atlases that
Godot imports as a Texture2DArray (assets/textures/building/*.png.import:
importer 2d_array_texture, 2 x 2 slices of 1024 px):

    layer 0  brick       brick_wall_006        3.0 m tile   Jan Burghardt
    layer 1  stucco      plastered_wall        2.0 m tile   Amal Kumar
    layer 2  limestone   sandstone_blocks_08   3.0 m tile   Rob Tuytel
    layer 3  concrete    concrete_wall_009     1.8 m tile   Charlotte Baglioni

Outputs (all in assets/textures/building/):

  facade_albedo.jpg   sRGB. NOT the raw scan: the scan is divided by its own
                      mean colour (in linear light) and stored as ratio * 0.2,
                      so "mean" = 0.2 linear. The shader multiplies it by the
                      building's wall colour (x5), which lets every palette
                      colour keep the scan's real detail without baked-in
                      hue or brightness (de-lit). Brick: bricks and mortar are
                      normalised separately (the shader gives mortar its own colour).
  facade_normal.png   OpenGL (Y+) tangent-space normals.
  facade_orm.png      R = ambient occlusion, G = roughness, B = mask (brick:
                      1 = mortar joint; others: cavities/joints from the
                      displacement map, used for weathering).
  facade_weather.png  generated (fixed seed): R vertical rain-streak noise,
                      G large blotches, B fine grain, A stain patches.

Run from the project root: python3 tools/textures/fetch_building.py
The interior room atlases are made by tools/blender/make_building_interiors.py
(+ tools/textures/pack_building_interiors.py) and the shop signs by
tools/textures/make_building_signs.py; this script only credits them.
After running any of them: godot --headless --path . --import (the .import
files are committed: 2d_array_texture 2 x 2 slices for the wall atlases,
VRAM compressed with mipmaps).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from fetch_common import (ambientcg, credit, download, out, polyhaven, polyhaven_files,  # noqa: E402,F401
                          write_sources)

FAMILY = "building"
SLICE = 1024

LAYERS = [
    # key, asset, author, mortar-style mask (True: low displacement = joint)
    ("brick", "brick_wall_006", "Jan Burghardt", True),
    ("stucco", "plastered_wall", "Amal Kumar", False),
    ("limestone", "sandstone_blocks_08", "Rob Tuytel", True),
    ("concrete", "concrete_wall_009", "Charlotte Baglioni", True),
]
MEAN = 0.2  # linear value the mean colour is stored as (shader multiplies by 1 / MEAN)


def to_linear(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb8(a):
    a = np.clip(a, 0.0, 1.0)
    s = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)
    return np.clip(s * 255.0 + 0.5, 0, 255).astype(np.uint8)


def load(path, mode="RGB", size=SLICE):
    im = Image.open(path).convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def process_layer(key, asset, mortar):
    src = polyhaven(asset, "2k", maps=("Diffuse", "nor_gl", "Rough", "AO", "Displacement"))
    diff = to_linear(load(src["diff"]).astype(np.float64))
    disp = load(src["disp"], "L").astype(np.float64) / 255.0
    # Mask. Brick: mortar is the low-saturation sandy part between the red
    # bricks (the displacement map is too noisy there). Others: the lowest
    # part of the displacement map (joints, pores), used for dirt in joints.
    srgb = load(src["diff"]).astype(np.float64) / 255.0
    sat = (srgb.max(axis=2) - srgb.min(axis=2)) / np.maximum(srgb.max(axis=2), 1e-4)
    dimg = Image.fromarray((disp * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    d = np.asarray(dimg).astype(np.float64) / 255.0
    if key == "brick":
        mask = 1.0 - smoothstep(0.37, 0.47, sat)
    elif mortar:
        lo, hi = np.quantile(d, [0.08, 0.2])
        mask = 1.0 - smoothstep(lo, hi, d)
    else:
        mask = np.zeros_like(d)
    if key == "brick":
        # Bricks and mortar normalised separately.
        sel = mask < 0.5
        mean_b = diff[sel].mean(axis=0)
        mean_m = diff[~sel].mean(axis=0)
        ratio = np.where(sel[..., None], diff / mean_b, diff / mean_m)
        print("  brick mean", mean_b, "mortar mean", mean_m)
    else:
        mean = diff.mean(axis=(0, 1))
        ratio = diff / mean
        print("  %s mean" % key, mean)
    albedo = to_srgb8(ratio * MEAN)
    nor = load(src["nor_gl"]).astype(np.float64) / 255.0 * 2 - 1
    nor[..., 2] = np.sqrt(np.clip(1 - nor[..., 0] ** 2 - nor[..., 1] ** 2, 0, 1))
    nor = ((nor + 1) * 0.5 * 255 + 0.5).astype(np.uint8)
    ao = load(src["ao"], "L")
    rough = load(src["rough"], "L")
    orm = np.dstack([ao, rough, (mask * 255).astype(np.uint8)])
    return albedo, nor, orm


def pack(tiles, cols=2):
    rows = (len(tiles) + cols - 1) // cols
    c = tiles[0].shape[2]
    atlas = np.zeros((rows * SLICE, cols * SLICE, c), np.uint8)
    for i, t in enumerate(tiles):
        r, cc = divmod(i, cols)
        atlas[r * SLICE:(r + 1) * SLICE, cc * SLICE:(cc + 1) * SLICE] = t
    return Image.fromarray(atlas)


# ------------------------------------------------------------- weather noise

def tileable_noise(rng, n, sx, sy):
    """Gaussian band-limited noise (tileable), std-dev of the filter in
    cycles per texture: sx across, sy down. Normalised to 0..1."""
    white = rng.standard_normal((n, n))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    filt = np.exp(-0.5 * ((fx / sx) ** 2 + (fy / sy) ** 2))
    filt[0, 0] = 0.0
    r = np.real(np.fft.ifft2(f * filt))
    r = (r - r.mean()) / (r.std() + 1e-9)
    return np.clip(r * 0.2 + 0.5, 0, 1)


def make_weather(n=512):
    rng = np.random.default_rng(20261002)
    # R: long vertical rain streaks: fine across (x), long down (y).
    streak = tileable_noise(rng, n, 70.0, 3.0)
    streak2 = tileable_noise(rng, n, 24.0, 2.0)
    streak = np.clip(streak * 0.65 + streak2 * 0.35, 0, 1)
    streak = smoothstep(0.38, 0.8, streak)
    # G: large blotches (mixed octaves).
    g = 0.6 * tileable_noise(rng, n, 3.0, 3.0) + 0.3 * tileable_noise(rng, n, 7.0, 7.0) + 0.1 * tileable_noise(rng, n, 16.0, 16.0)
    g = np.clip((g - 0.5) * 1.6 + 0.5, 0, 1)
    # B: fine grain.
    b = tileable_noise(rng, n, 150.0, 150.0)
    # A: stain patches (damp, efflorescence): mid frequency, high contrast.
    a = smoothstep(0.52, 0.68, 0.7 * tileable_noise(rng, n, 5.0, 6.0) + 0.3 * tileable_noise(rng, n, 12.0, 12.0))
    img = np.dstack([streak, g, b, a])
    return Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA")


def main():
    albedos, normals, orms = [], [], []
    for key, asset, author, mortar in LAYERS:
        print("layer", key, asset)
        a, n, o = process_layer(key, asset, mortar)
        albedos.append(a)
        normals.append(n)
        orms.append(o)
        credit(FAMILY, asset, author, "https://polyhaven.com/a/" + asset, "CC0 1.0",
               "facade_*.jpg/png layer %d (%s)" % (len(albedos) - 1, key))
    pack(albedos).save(out(FAMILY, "facade_albedo.jpg"), quality=93, optimize=True)
    pack(normals).save(out(FAMILY, "facade_normal.png"), optimize=True)
    pack(orms).save(out(FAMILY, "facade_orm.png"), optimize=True)
    make_weather().save(out(FAMILY, "facade_weather.png"), optimize=True)
    credit(FAMILY, "facade_weather.png", "Turbo Town", "tools/textures/fetch_building.py", "generated (CC0)",
           "rain streaks, blotches, grain, stains")
    credit(FAMILY, "facade_interiors_*.jpg", "Turbo Town", "tools/blender/make_building_interiors.py + tools/textures/pack_building_interiors.py",
           "generated (CC0)", "room atlases for interior mapping (Cycles renders of procedurally built rooms)")
    credit(FAMILY, "facade_signs.png", "Turbo Town", "tools/textures/make_building_signs.py",
           "generated (CC0); lettering set in Fira Sans and Noto Serif (SIL OFL 1.1)", "shop sign boards (generic trade words)")
    write_sources(FAMILY)
    print("done")


if __name__ == "__main__":
    main()
