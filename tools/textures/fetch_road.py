#!/usr/bin/env python3
"""Roads and paved ground textures (realism experiment, ART_BIBLE.md §16).

Downloads CC0 scans (ambientCG, Poly Haven) with tools/textures/fetch_common.py,
processes them into game textures and writes assets/textures/road/ plus its
SOURCES.md. Run from the project root:

    python3 tools/textures/fetch_road.py

Godot import (VRAM compressed, mipmaps): after the first `godot --headless --path . --import`
run `python3 tools/textures/fetch_road.py --import-settings` and import again.

Outputs (all tileable, committed):

  road_asphalt_a_albedo.jpg / _nra.png   city + highway asphalt aggregate (ambientCG Asphalt015)
  road_asphalt_b_albedo.jpg / _nra.png   country road asphalt, sandier chip seal (ambientCG Asphalt032)
  road_concrete_s_albedo.jpg / _nra.png  sidewalk, kerb and plaza concrete (Poly Haven granular_concrete)
  road_concrete_c_albedo.jpg / _nra.png  cast concrete: barriers, piers, decks (ambientCG Concrete020)
  road_cracks.png     RGBA, 12 m tile (generated): R open cracks, G crack sealant,
                      B pits / ravelling, A mid-scale mottling
  road_macro.png      RGBA, 30 m tile: R scuffs and stains (Poly Haven Aerial Asphalt 01,
                      neutralised), G large-scale tone (generated), B oil drip spots
                      (generated), A fine film (generated)

Conventions shared by every *_albedo.jpg:
  * the colour is neutralised (mostly grey) and its low frequencies are flattened,
    then scaled so the mean linear luminance is exactly ALBEDO_MEAN (0.18). Shaders
    multiply by `base_colour / 0.18`, so the palette sets the average albedo and the
    scan only adds the texture. No lighting is baked in.
  * *_nra.png packs R,G = tangent-space normal x,y (OpenGL, Y+; z is rebuilt in the
    shader), B = roughness (remapped to a plausible range), A = ambient occlusion.
    It is a plain linear texture (not imported as a normal map).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_common import (CACHE, ambientcg, credit, out, polyhaven, write_sources)  # noqa: E402

ALBEDO_MEAN = 0.18       # mean linear luminance of every *_albedo.jpg
SIZE = 1024              # most maps
SEED = 20261002

# --- colour helpers -----------------------------------------------------------


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def lum(c):
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def blur_wrap(a, sigma):
    """Gaussian blur with wrap-around (so tileable maps stay tileable), via FFT."""
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g))
    return np.stack([np.real(np.fft.ifft2(np.fft.fft2(a[..., i]) * g)) for i in range(a.shape[2])], -1)


def load(path, size=None, mode="RGB", resample=Image.LANCZOS):
    im = Image.open(path).convert(mode)
    if size and im.size != (size, size):
        im = im.resize((size, size), resample)
    return np.asarray(im, dtype=np.float64) / 255.0


# --- scan processing --------------------------------------------------------------


def process_albedo(src, dst, size=SIZE, keep_sat=0.35, flatten=1.0, flat_sigma=0.09, contrast=1.0):
    """Neutralises, flattens and normalises a colour scan, writes a JPG."""
    c = to_linear(load(src, size))
    l = lum(c)[..., None]
    c = l + (c - l) * keep_sat                   # tame the white balance
    c = np.maximum(c, 1e-4)
    if flatten > 0:
        low = blur_wrap(lum(c), flat_sigma * size)[..., None]
        low = np.maximum(low, 1e-4)
        flat = c / low * low.mean()              # remove tile-scale blotches
        c = c * (1 - flatten) + flat * flatten
    if contrast != 1.0:
        m = lum(c).mean()
        c = np.maximum(m * (c / m) ** contrast, 1e-4)
    c = c * (ALBEDO_MEAN / lum(c).mean())
    Image.fromarray((to_srgb(c) * 255 + 0.5).astype(np.uint8)).save(dst, quality=90, optimize=True, subsampling=0)
    print("  %-34s mean lin %.3f max %.2f" % (os.path.basename(dst), lum(c).mean(), c.max()))


def cavity_ao(disp, size=SIZE, radius=5.0, gain=7.0):
    h = load(disp, size, "L")
    return 1.0 - np.clip((blur_wrap(h, radius) - h) * gain, 0.0, 0.85)


def process_nra(normal, rough, ao, dst, size=SIZE, normal_gain=1.0, rough_mean=0.85, rough_gain=0.8,
                rough_lo=0.55, rough_hi=1.0, ao_path=None, disp=None, ao_strength=1.0):
    n = load(normal, size) * 2.0 - 1.0
    n[..., :2] *= normal_gain
    z = np.sqrt(np.maximum(0.0, 1.0 - n[..., 0] ** 2 - n[..., 1] ** 2))
    v = np.stack([n[..., 0], n[..., 1], z], -1)
    v /= np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)
    r = load(rough, size, "L")
    r = np.clip(rough_mean + (r - r.mean()) * rough_gain, rough_lo, rough_hi)
    if ao_path:
        a = load(ao_path, size, "L")
    elif disp:
        a = cavity_ao(disp, size)
    else:
        a = np.ones_like(r)
    a = 1.0 - (1.0 - a) * ao_strength
    rgba = np.stack([v[..., 0] * 0.5 + 0.5, v[..., 1] * 0.5 + 0.5, r, np.clip(a, 0.02, 1.0)], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(dst, optimize=True)
    print("  %-34s rough mean %.2f ao mean %.2f" % (os.path.basename(dst), r.mean(), a.mean()))


# --- generated maps ---------------------------------------------------------------


def tile_noise(rng, size, cells):
    """Smooth tileable noise made by upsampling a wrapped grid with cubic interpolation."""
    g = rng.random((cells, cells))
    pad = np.pad(g, 2, mode="wrap")
    im = Image.fromarray((pad * 255).astype(np.uint8)).resize(((cells + 4) * (size // cells), (cells + 4) * (size // cells)), Image.BICUBIC)
    a = np.asarray(im, dtype=np.float64) / 255.0
    off = 2 * (size // cells)
    return a[off:off + size, off:off + size]


def tfbm(rng, size, base, octaves, persistence=0.55):
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        total += tile_noise(rng, size, base * (2 ** o)) * amp
        norm += amp
        amp *= persistence
    total /= norm
    lo, hi = np.percentile(total, 1), np.percentile(total, 99)
    return np.clip((total - lo) / (hi - lo), 0, 1)


def draw_wrapped(draw_fn, size):
    for ox in (-size, 0, size):
        for oy in (-size, 0, size):
            draw_fn(ox, oy)


def crack_path(rng, x, y, ang, length, step, wobble=0.07, bend=0.03):
    """A crack: a slow meander (mean-reverting, so it stays roughly straight) plus
    a fast zig-zag at the scale of a few centimetres."""
    pts = [(x, y)]
    dev = 0.0
    walked = 0.0
    while walked < length:
        dev = dev * 0.93 + rng.normal(0, wobble)
        a = ang + dev + rng.normal(0, 0.33)
        x += np.cos(a) * step
        y += np.sin(a) * step
        pts.append((x, y))
        walked += step
    return pts


def make_cracks(size=2048, tile_m=12.0):
    """Cracks, sealant bands, pits and mottling for one 12 m tile (tileable)."""
    rng = np.random.default_rng(SEED)
    ss = 2
    n = size * ss
    ppm = n / tile_m                      # supersampled pixels per metre
    openc = Image.new("L", (n, n), 0)
    seal = Image.new("L", (n, n), 0)
    od, sd = ImageDraw.Draw(openc), ImageDraw.Draw(seal)

    def polyline(pts, widths, img_draw):
        def d(ox, oy):
            for i in range(len(pts) - 1):
                w = max(1, int(round(widths[i] * ppm)))
                img_draw.line([(pts[i][0] + ox, pts[i][1] + oy), (pts[i + 1][0] + ox, pts[i + 1][1] + oy)], fill=255, width=w)
                if w > 2:
                    r = w / 2.0
                    img_draw.ellipse([pts[i][0] + ox - r, pts[i][1] + oy - r, pts[i][0] + ox + r, pts[i][1] + oy + r], fill=255)
        draw_wrapped(d, n)

    def axis_angle():
        base = rng.choice([0.0, np.pi / 2, np.pi, -np.pi / 2])
        return base + rng.normal(0, 0.12) if rng.random() < 0.7 else rng.uniform(0, 2 * np.pi)

    def add_crack(x, y, ang, length, sealed, depth=0):
        step = 0.04
        pts = crack_path(rng, x * ppm, y * ppm, ang, length * ppm, step * ppm, wobble=0.07 if not sealed else 0.045)
        k = len(pts) - 1
        taper = np.clip(np.minimum(np.arange(k), k - np.arange(k)) / 12.0, 0.35, 1.0)
        wiggle = 0.6 + 0.8 * rng.random(k)
        wiggle = np.convolve(wiggle, np.ones(5) / 5, mode="same")
        if sealed:
            widths = 0.034 * wiggle * taper                     # 3 cm sealant band
            polyline(pts, widths, sd)
            polyline(pts, widths * 0.18, od)                    # crack still visible in the middle
        else:
            widths = 0.011 * wiggle * taper                     # about 1 cm
            polyline(pts, widths, od)
        if depth < 2 and length > 1.0:
            for _ in range(rng.integers(0, 3 if depth == 0 else 2)):
                t = rng.integers(max(2, k // 8), max(3, k - 2))
                bx, by = pts[t]
                ba = np.arctan2(pts[min(t + 1, k)][1] - pts[t][1], pts[min(t + 1, k)][0] - pts[t][0])
                ba += rng.choice([-1, 1]) * rng.uniform(0.35, 1.0)
                add_crack(bx / ppm, by / ppm, ba, length * rng.uniform(0.15, 0.45), sealed and rng.random() < 0.5, depth + 1)

    # Long cracks (transverse and longitudinal), some sealed.
    for i in range(7):
        add_crack(rng.uniform(0, tile_m), rng.uniform(0, tile_m), axis_angle(), rng.uniform(4.0, 9.0), rng.random() < 0.55)
    # Short ones.
    for i in range(16):
        add_crack(rng.uniform(0, tile_m), rng.uniform(0, tile_m), axis_angle(), rng.uniform(0.6, 2.8), rng.random() < 0.25)
    # Alligator (fatigue) patches: polygonal networks inside a blob (Voronoi edges).
    for i in range(3):
        cx, cy, rad = rng.uniform(0, tile_m), rng.uniform(0, tile_m), rng.uniform(0.7, 1.3)
        cell = rng.uniform(0.14, 0.24)
        gm = int(rad * 2 * ppm)
        xs = np.arange(gm) / ppm
        X, Y = np.meshgrid(xs, xs)                      # metres inside the patch box
        gn = int(rad * 2 / cell) + 3
        seeds = (np.stack(np.meshgrid(np.arange(gn), np.arange(gn)), -1) + rng.uniform(0.1, 0.9, (gn, gn, 2))) * cell
        ci = np.clip((X / cell).astype(int), 1, gn - 2)
        cj = np.clip((Y / cell).astype(int), 1, gn - 2)
        ds = []
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                sx = seeds[cj + dj, ci + di, 0]
                sy = seeds[cj + dj, ci + di, 1]
                ds.append(np.hypot(X - sx, Y - sy))
        ds = np.sort(np.stack(ds, -1), axis=-1)
        edge = np.clip(1.0 - (ds[..., 1] - ds[..., 0]) / 0.007, 0, 1)
        blob = np.clip(1.0 - np.hypot(X - rad, Y - rad) / rad, 0, 1)
        blob = np.clip(blob * 3.0 - 0.25, 0, 1)
        pim = Image.fromarray((edge * blob * 255).astype(np.uint8))
        x0, y0 = int((cx - rad) * ppm), int((cy - rad) * ppm)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                openc.paste(255, (x0 + ox, y0 + oy, x0 + ox + gm, y0 + oy + gm), pim)

    openc = openc.filter(ImageFilter.GaussianBlur(0.9 * ss / 2))
    seal = seal.filter(ImageFilter.GaussianBlur(1.0 * ss))
    openc = openc.resize((size, size), Image.LANCZOS)
    seal = seal.resize((size, size), Image.LANCZOS)
    r = np.asarray(openc, dtype=np.float64) / 255.0
    g = np.asarray(seal, dtype=np.float64) / 255.0
    # Ragged sealant: modulate the band by fine noise so edges aren't clean.
    g = np.clip(g * (0.65 + 0.7 * tile_noise(rng, size, 256)) * 1.15, 0, 1)
    # Pits and ravelling: small dark spots, denser near the cracks.
    near = blur_wrap(np.maximum(r, g), 14.0)
    spots = tile_noise(rng, size, 512)
    thresh = 0.945 - np.clip(near * 5.0, 0, 0.2)
    b = np.clip((spots - thresh) / 0.05, 0, 1)
    b = blur_wrap(b, 0.8)
    b = np.clip(b * 1.4, 0, 1)
    a = tfbm(rng, size, 4, 5)
    rgba = np.stack([r, g, b, a], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(out("road", "road_cracks.png"), optimize=True)
    print("  road_cracks.png  crack cover %.3f seal %.3f" % (r.mean(), g.mean()))


def make_macro(src_diff, size=1024):
    """30 m tile: R scuffs and stains (real), G tone, B oil drip spots, A fine film."""
    rng = np.random.default_rng(SEED + 1)
    c = to_linear(load(src_diff, size))
    l = blur_wrap(lum(c), 2.2)                                          # drop the aggregate grain, keep scuffs
    low = blur_wrap(l, size * 0.12)
    ratio = l / np.maximum(blur_wrap(l, size * 0.02), 1e-4)             # scuffs and cracks vs local mean
    tone = l / np.maximum(l.mean(), 1e-4)                               # stains and wear, incl. low frequencies
    r = np.clip(0.5 * (0.55 * ratio + 0.45 * tone), 0, 1)
    g = tfbm(rng, size, 4, 5)
    # Oil spots: sparse blobs with a darker, softer halo; drip trails come from the lane mask in the shader.
    spots = np.zeros((size, size))
    yy, xx = np.mgrid[0:size, 0:size]
    for i in range(380):
        cx, cy = rng.uniform(0, size, 2)
        rad = rng.uniform(2.5, 9.0)
        dx = (xx - cx + size / 2) % size - size / 2
        dy = (yy - cy + size / 2) % size - size / 2
        d = np.hypot(dx, dy) / rad
        spots = np.maximum(spots, np.clip(1.0 - d, 0, 1) ** 0.8 * rng.uniform(0.4, 1.0))
    spots = np.clip(spots + (tfbm(rng, size, 32, 3) - 0.5) * 0.35 * (spots > 0.02), 0, 1)
    a = tfbm(rng, size, 64, 3)
    rgba = np.stack([r, g, spots, a], -1)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(out("road", "road_macro.png"), optimize=True)
    print("  road_macro.png  scuff mean %.2f" % r.mean())


IMPORT_PARAMS = {
    "compress/mode": "2",                 # VRAM compressed
    "compress/high_quality": "true",      # BC7
    "mipmaps/generate": "true",
    "process/fix_alpha_border": "false",  # the A channel is data (AO, masks)
}


def apply_import_settings():
    """Sets the Godot import parameters of our textures (needs the .import files
    Godot writes the first time it sees them). Run after `godot --import`, then
    import again."""
    folder = os.path.dirname(out("road", "x"))
    n = 0
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith(".import"):
            continue
        path = os.path.join(folder, fn)
        lines = open(path).read().split("\n")
        for i, line in enumerate(lines):
            key = line.split("=", 1)[0]
            if key in IMPORT_PARAMS:
                lines[i] = "%s=%s" % (key, IMPORT_PARAMS[key])
        open(path, "w").write("\n".join(lines))
        n += 1
    print("import settings applied to %d files; run `godot --headless --path . --import` again" % n)


def main():
    # Keep Godot from scanning the download cache (it would import every scan).
    os.makedirs(CACHE, exist_ok=True)
    open(os.path.join(CACHE, ".gdignore"), "a").close()
    print("asphalt A (city, highway)")
    s = ambientcg("Asphalt015", "2K")
    process_albedo(s["Color"], out("road", "road_asphalt_a_albedo.jpg"), keep_sat=0.25, flatten=1.0, flat_sigma=0.08)
    process_nra(s["NormalGL"], s["Roughness"], None, out("road", "road_asphalt_a_nra.png"),
                disp=s["Displacement"], rough_mean=0.8, rough_gain=0.9, rough_lo=0.58, rough_hi=0.98)
    credit("road", "Asphalt 015", "ambientCG", "https://ambientcg.com/a/Asphalt015", use="city and highway asphalt aggregate (colour, normal, roughness, cavity AO from displacement)")

    print("asphalt B (country)")
    s = ambientcg("Asphalt032", "2K")
    process_albedo(s["Color"], out("road", "road_asphalt_b_albedo.jpg"), keep_sat=0.45, flatten=1.0, flat_sigma=0.08)
    process_nra(s["NormalGL"], s["Roughness"], None, out("road", "road_asphalt_b_nra.png"),
                disp=s["Displacement"], rough_mean=0.82, rough_gain=0.8, rough_lo=0.6, rough_hi=0.98)
    credit("road", "Asphalt 032", "ambientCG", "https://ambientcg.com/a/Asphalt032", use="country road asphalt")

    print("concrete S (sidewalk, kerb, plaza)")
    s = polyhaven("granular_concrete", "2k")
    process_albedo(s["diff"], out("road", "road_concrete_s_albedo.jpg"), keep_sat=0.5, flatten=0.4, flat_sigma=0.1)
    process_nra(s["nor_gl"], s["rough"], None, out("road", "road_concrete_s_nra.png"), ao_path=s["ao"],
                normal_gain=0.9, rough_mean=0.9, rough_gain=0.7, rough_lo=0.7, rough_hi=0.99, ao_strength=0.45)
    credit("road", "Granular Concrete", "Dario Barresi, Michael Jenkins / Poly Haven", "https://polyhaven.com/a/granular_concrete", use="sidewalk slabs, kerbs, plaza")

    print("concrete C (cast)")
    s = ambientcg("Concrete020", "2K")
    process_albedo(s["Color"], out("road", "road_concrete_c_albedo.jpg"), keep_sat=0.5, flatten=0.45, flat_sigma=0.12)
    process_nra(s["NormalGL"], s["Roughness"], None, out("road", "road_concrete_c_nra.png"),
                disp=s["Displacement"], normal_gain=1.1, rough_mean=0.9, rough_gain=0.8, rough_lo=0.7, rough_hi=1.0, ao_strength=0.8)
    credit("road", "Concrete 020", "ambientCG", "https://ambientcg.com/a/Concrete020", use="cast concrete: barriers, piers, decks, retaining walls")

    print("macro (aerial asphalt)")
    s = polyhaven("aerial_asphalt_01", "2k", maps=("Diffuse",))
    make_macro(s["diff"])
    credit("road", "Aerial Asphalt 01", "Rob Tuytel / Poly Haven", "https://polyhaven.com/a/aerial_asphalt_01", use="scuffs and stains (R of road_macro.png, luminance only)")

    print("generated: cracks")
    make_cracks()
    credit("road", "Generated maps", "Turbo Town (tools/textures/fetch_road.py)", "-", licence="own work", use="road_cracks.png, the G/B/A channels of road_macro.png")
    write_sources("road")


if __name__ == "__main__":
    if "--import-settings" in sys.argv:
        apply_import_settings()
    else:
        main()
        print("next: godot --headless --path . --import, then python3 tools/textures/fetch_road.py --import-settings, then import again")
