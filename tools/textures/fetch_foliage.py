#!/usr/bin/env python3
"""Downloads CC0 leaf scans and bark textures and builds the tree textures in
assets/textures/foliage/ (run from the project root):

    python3 tools/textures/fetch_foliage.py            # everything
    python3 tools/textures/fetch_foliage.py broadleaf_a palm   # only some

Sources (all CC0): ambientCG leaf sets (LeafSet0xx, Foliage008) and Poly Haven
bark textures; see assets/textures/foliage/SOURCES.md (written by this script).

Leaves are photo scans on transparent backgrounds. This script cuts them into
single leaves and composes *branch cluster* sprites from them (a twig with
leaves along it), 16 to an atlas, so a tree is a few hundred cards of real
leaves instead of a texture of a canopy. The look comes from the real leaf
colour, variation and overlap; the game's shader adds the lighting.

Outputs (RGBA PNG: RGB = leaf colour, de-lit; A = cut-out mask. Colour from
transparent texels is bled outwards so mip-mapping doesn't darken edges):
  foliage_leaves_broadleaf_a.png   2048^2, 4x4 tiles of 512^2 (round leaves)
  foliage_leaves_broadleaf_b.png   2048^2, 4x4 tiles (lobed oak leaves)
  foliage_leaves_shrub.png         2048^2, 4x4 tiles (small dense leaves)
  foliage_leaves_conifer.png       2048^2, 2x4 tiles of 1024x512 (feathery sprays)
  foliage_leaves_palm.png          2048^2, two 2048x1024 fronds
  foliage_bark_<kind>_albedo.jpg / _normal.png   1024^2 trunk bark

Tile conventions (see scripts/world/tree_kit.gd): in a leaf tile the stem
enters at the bottom centre and the cluster grows upwards; in a conifer tile
the branch runs left (base) to right (tip); in the palm atlas the frond runs
left (base) to right (tip). Fixed seeds, so re-running reproduces the files.
"""
import colorsys
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_common import *  # noqa: E402,F403
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

FAMILY = "foliage"


# ------------------------------------------------------------ leaf library ---

def _label(mask):
    """4-connected component labels of a boolean array (BFS)."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    n = 0
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if labels[y0, x0]:
            continue
        n += 1
        labels[y0, x0] = n
        stack = [(y0, x0)]
        while stack:
            y, x = stack.pop()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not labels[yy, xx]:
                    labels[yy, xx] = n
                    stack.append((yy, xx))
    return labels, n


def _box(a, r):
    """Box blur of a float array (H x W or H x W x C), radius r, edge-clamped."""
    k = 2 * r + 1
    pad = [(r, r), (r, r)] + [(0, 0)] * (a.ndim - 2)
    p = np.pad(a, pad, mode="edge")
    c = np.cumsum(p, axis=0, dtype=np.float64)
    c = np.concatenate([np.zeros_like(c[:1]), c], 0)
    p = (c[k:] - c[:-k])
    c = np.cumsum(p, axis=1, dtype=np.float64)
    c = np.concatenate([np.zeros_like(c[:, :1]), c], 1)
    return ((c[:, k:] - c[:, :-k]) / (k * k)).astype(np.float32)


def _bleed(rgb, alpha, iters=8, radius=3):
    """Spreads the colour of opaque texels into transparent ones (premultiplied
    blur, repeated) so edges sample leaf colour, not black."""
    col = rgb.astype(np.float32)
    known = alpha > 128
    out = col.copy()
    for k in range(iters):
        wgt = known.astype(np.float32)
        cb = _box(out * wgt[..., None], radius)
        wb = _box(wgt, radius)
        fill = (wb > 1e-3) & ~known
        out[fill] = cb[fill] / wb[fill][..., None]
        known = known | fill
    return np.clip(out, 0, 255).astype(np.uint8)


class Leaf:
    """One cut-out leaf: RGBa (premultiplied) image, apex up, plus its length."""

    def __init__(self, img):
        self.img = img  # PIL "RGBa"
        self.w, self.h = img.size


def load_leaves(asset, res="2K", min_area=0.0015, rot=0.0, flip_v=False):
    """Every separate leaf (connected component of the opacity map) of an
    ambientCG leaf set as `Leaf`s, turned `rot` degrees counter-clockwise (the
    sets lay leaves out apex-up, apex-right or similar; we want apex up)."""
    src = ambientcg(asset, res)
    color = Image.open(src["Color"]).convert("RGB")
    op = Image.open(src["Opacity"]).convert("L")
    w, h = color.size
    k = 4
    small = np.array(op.resize((w // k, h // k), Image.BILINEAR)) > 60
    labels, n = _label(small)
    leaves = []
    big_op = np.array(op)
    for i in range(1, n + 1):
        ys, xs = np.nonzero(labels == i)
        if len(ys) < min_area * small.size:
            continue
        y0, y1, x0, x1 = ys.min() * k, (ys.max() + 1) * k, xs.min() * k, (xs.max() + 1) * k
        pad = 10
        y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
        y1, x1 = min(h, y1 + pad), min(w, x1 + pad)
        comp = np.kron((labels[y0 // k:(y1 + k - 1) // k, x0 // k:(x1 + k - 1) // k] == i).astype(np.uint8), np.ones((k, k), np.uint8))
        comp = comp[:y1 - y0, :x1 - x0]
        comp_img = Image.fromarray(comp * 255).filter(ImageFilter.MaxFilter(2 * k + 1))
        a = (np.array(comp_img) > 0) * big_op[y0:y1, x0:x1]
        rgb = np.array(color)[y0:y1, x0:x1]
        rgb = _bleed(rgb, a)
        rgba = np.dstack([rgb, a.astype(np.uint8)])
        img = Image.fromarray(rgba, "RGBA")
        if rot:
            img = img.rotate(rot, resample=Image.BICUBIC, expand=True)
        if flip_v:
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
        bbox = img.getbbox()
        img = img.crop(bbox)
        leaves.append(Leaf(img.convert("RGBa")))
    return leaves


def tint(img_rgba_a, mult=(1, 1, 1), sat=1.0):
    """Colour-grades a premultiplied-or-not RGBA PIL image (returns RGBA)."""
    arr = np.array(img_rgba_a.convert("RGBA")).astype(np.float32)
    rgb = arr[..., :3] / 255.0
    g = rgb.mean(-1, keepdims=True)
    rgb = g + (rgb - g) * sat
    rgb = rgb * np.array(mult, np.float32)
    arr[..., :3] = np.clip(rgb, 0, 1) * 255.0
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# ----------------------------------------------------------- composition ---

def over(canvas, img, px, py):
    """Composites RGBA `img` onto RGBA `canvas` at (px, py), clipping."""
    W, H = canvas.size
    sx0, sy0 = max(0, -px), max(0, -py)
    sx1, sy1 = min(img.size[0], W - px), min(img.size[1], H - py)
    if sx1 <= sx0 or sy1 <= sy0:
        return
    canvas.alpha_composite(img.crop((sx0, sy0, sx1, sy1)), (px + sx0, py + sy0))


def shaded(img, shade=1.0, warm=0.0):
    """RGBA image with colour scaled by `shade`, tilted towards yellow (warm > 0)
    or blue-green (warm < 0)."""
    arr = np.array(img).astype(np.float32)
    arr[..., :3] *= shade
    arr[..., 0] *= 1.0 + warm
    arr[..., 2] *= 1.0 - warm * 0.8
    arr[..., :3] = np.clip(arr[..., :3], 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def paste_leaf(canvas, leaf, bx, by, length, angle_deg, squash=1.0, shade=1.0, warm=0.0, width_scale=1.0):
    """Pastes `leaf` with its base (bottom centre) at (bx, by), `length` px
    long, pointing `angle_deg` clockwise from up; `squash` narrows it (a leaf
    turned away from the viewer)."""
    s = length / leaf.h
    w = max(2, int(leaf.w * s * squash * width_scale))
    h = max(2, int(leaf.h * s))
    img = leaf.img.resize((w, h), Image.BICUBIC).convert("RGBA")
    if shade != 1.0 or warm != 0.0:
        img = shaded(img, shade, warm)
    rot = img.rotate(-angle_deg, resample=Image.BICUBIC, expand=True)
    rw, rh = rot.size
    a = math.radians(angle_deg)
    px = bx - (rw / 2 - h / 2 * math.sin(a))
    py = by - (rh / 2 + h / 2 * math.cos(a))
    over(canvas, rot, int(round(px)), int(round(py)))


def draw_twig(draw, pts, w0, w1, col):
    n = len(pts) - 1
    for i in range(n):
        w = w0 + (w1 - w0) * i / max(n - 1, 1)
        draw.line([pts[i], pts[i + 1]], fill=col, width=max(1, int(round(w))))


def fit_tile(canvas, tw, th, margin=0.03, max_up=1.0, align_bottom=True):
    """Crops `canvas` to its opaque bounding box and fits it into a tw x th
    tile (never enlarging beyond `max_up`; centred, bottom-aligned)."""
    bbox = canvas.getbbox()
    c = canvas.crop(bbox)
    avail_w, avail_h = tw * (1 - 2 * margin), th * (1 - 2 * margin)
    s = min(avail_w / c.size[0], avail_h / c.size[1], max_up)
    c = c.resize((max(1, int(c.size[0] * s)), max(1, int(c.size[1] * s))), Image.LANCZOS)
    tile = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    x = (tw - c.size[0]) // 2
    y = th - c.size[1] - int(th * margin) if align_bottom else (th - c.size[1]) // 2
    tile.alpha_composite(c, (x, y))
    return tile


def make_round_cluster(leaves, rng, size=512, n_leaves=(110, 150), leaf_len=(0.085, 0.12), twig_col=(88, 68, 50),
                       fan=(20, 80), squash=(0.7, 1.0), depth_dark=0.3, main_len=(0.46, 0.58), grade=(1, 1, 1),
                       sat=1.0, n_side=(5, 7), side_len=(0.26, 0.4)):
    """A branch cluster as a sprite (see the module docstring): a curved twig
    from the bottom centre that forks into a few side twigs, with leaves along
    them, angled outward. Back leaves are darkened a little (cavity AO)."""
    u = size * 2  # supersampled tile size
    cw = int(u * 1.6)
    canvas = Image.new("RGBA", (cw, cw), (0, 0, 0, 0))
    twig = Image.new("RGBA", (cw, cw), (0, 0, 0, 0))
    td = ImageDraw.Draw(twig)
    nodes = []

    def grow(start, ang, length, nseg, width, level):
        pts = [start]
        x, y = start
        a = ang
        for i in range(nseg):
            a += rng.uniform(-9, 9)
            step = length / nseg
            x += math.sin(math.radians(a)) * step
            y -= math.cos(math.radians(a)) * step
            pts.append((x, y))
            nodes.append((x, y, a, level))
        draw_twig(td, pts, width, width * 0.55, twig_col + (255,))
        return pts, a

    base = (cw * 0.5, cw * 0.93)
    ml = u * rng.uniform(*main_len)
    main, end_a = grow(base, rng.uniform(-10, 10), ml, 7, u * 0.013, 0)
    for k in range(rng.randint(*n_side)):
        idx = rng.randint(2, len(main) - 1)
        side = rng.choice([-1, 1])
        ang = side * rng.uniform(22, 55)
        sub, _ = grow(main[idx], ang, u * rng.uniform(*side_len), 5, u * 0.008, 1)
        if rng.random() < 0.6:
            grow(sub[rng.randint(2, len(sub) - 1)], -side * rng.uniform(25, 60), u * rng.uniform(0.1, 0.18), 3, u * 0.005, 2)
    items = []
    count = rng.randint(*n_leaves)
    for i in range(count):
        x, y, a, lvl = rng.choice(nodes)
        side = rng.choice([-1, 1])
        la = a + side * rng.uniform(*fan)
        items.append((rng.random(), x, y, la))
    for i in range(3):  # leaves at the twig tips continue the twig
        x, y, a, lvl = nodes[min(len(nodes) - 1, 6 - i)]
        items.append((1.0, x, y, a + rng.uniform(-30, 30)))
    items.sort()
    for z, x, y, la in items:
        leaf = rng.choice(leaves)
        paste_leaf(canvas, leaf, x, y, u * rng.uniform(*leaf_len), la, squash=rng.uniform(*squash),
                   shade=1.0 - depth_dark * (1.0 - z), warm=rng.uniform(-0.05, 0.05))
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.alpha_composite(twig)
    out.alpha_composite(canvas)
    out = tint(out, grade, sat)
    return fit_tile(out, size * 2, size * 2, margin=0.025).resize((size, size), Image.LANCZOS)


def make_conifer_branch(sprays, rng, tw=1024, th=512, n_sprays=(32, 42), stem_col=(70, 52, 38), grade=(1, 1, 1), sat=1.0,
                        depth_dark=0.3, spray_len=(0.42, 0.62), sag=0.05):
    """A conifer branch card: a stem running left (base) to right (tip) with
    feathery sprays angled forward on both sides, shorter towards the tip."""
    u = 2.0
    W, H = int(tw * u), int(th * u)
    canvas = Image.new("RGBA", (int(W * 1.3), int(H * 1.6)), (0, 0, 0, 0))
    cw, ch = canvas.size
    twig = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(twig)
    x0 = cw * 0.06
    y0 = ch * 0.5
    pts = []
    n = 14
    stem_len = W * rng.uniform(0.86, 0.96)
    for i in range(n + 1):
        t = i / n
        pts.append((x0 + stem_len * t, y0 + H * sag * math.sin(t * math.pi) - H * 0.01 * t))
    draw_twig(td, pts, H * 0.028, H * 0.008, stem_col + (255,))
    items = []
    count = rng.randint(*n_sprays)
    for i in range(count):
        t = rng.uniform(0.02, 0.97) ** 0.9
        px, py = pts[min(n, int(t * n))]
        side = 1 if i % 2 == 0 else -1
        ang_from_stem = rng.uniform(38, 72)  # forward-swept
        la = 90 - side * ang_from_stem
        taper = 1.0 - 0.55 * t
        items.append((rng.random(), px, py, la, H * rng.uniform(*spray_len) * taper))
    # a terminal spray continues the branch
    items.append((1.0, pts[-1][0], pts[-1][1], 90 + rng.uniform(-12, 12), H * 0.38))
    items.sort()
    for z, x, y, la, ln in items:
        leaf = rng.choice(sprays)
        paste_leaf(canvas, leaf, x, y, ln, la, squash=rng.uniform(0.8, 1.15), shade=1.0 - depth_dark * (1.0 - z),
                   warm=rng.uniform(-0.04, 0.04))
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.alpha_composite(twig)
    out.alpha_composite(canvas)
    out = tint(out, grade, sat)
    return fit_tile(out, int(tw * u), int(th * u), margin=0.02, align_bottom=False).resize((tw, th), Image.LANCZOS)


def make_palm_frond(blades, rng, tw=2048, th=1024, n_pairs=84, grade=(1, 1, 1), sat=1.0, rachis_col=(98, 106, 60),
                    angle=(50, 66), reach=0.44, width=(1.7, 2.4)):
    """A pinnate palm frond: rachis along the middle from left (base) to right
    (tip), a leaflet on each side at every step, longest in the middle."""
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    twig = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    td = ImageDraw.Draw(twig)
    cy = th * 0.5
    x_start, x_end = tw * 0.02, tw * 0.985
    pts = [(x_start + (x_end - x_start) * i / 40, cy) for i in range(41)]
    draw_twig(td, pts, th * 0.026, th * 0.006, rachis_col + (255,))
    items = []
    for i in range(n_pairs):
        t = i / (n_pairs - 1)
        x = x_start + (x_end - x_start) * (0.12 + 0.86 * t)
        prof = max(math.sin(math.pi * min(1.0, 0.18 + 0.82 * t) ** 0.85), 0.18)
        for side in (-1, 1):
            th_deg = rng.uniform(*angle)
            ln = th * reach * prof / math.sin(math.radians(th_deg)) * rng.uniform(0.88, 1.08)
            ln = min(ln, th * 0.5 / math.sin(math.radians(th_deg)))
            # an up-pointing blade turned clockwise by (90 - th) points up and
            # forward (to the right); counter-clockwise (90 + th) points down-right.
            la = 90 - th_deg if side < 0 else 90 + th_deg
            items.append((rng.random(), x + rng.uniform(-4, 4), cy, la, ln))
    items.sort(key=lambda it: it[0])
    for z, x, y, la, ln in items:
        leaf = rng.choice(blades)
        paste_leaf(canvas, leaf, x, y, ln, la + rng.uniform(-6, 6), squash=1.0, width_scale=rng.uniform(*width),
                   shade=1.0 - 0.25 * (1.0 - z), warm=rng.uniform(-0.04, 0.05))
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.alpha_composite(twig)
    out.alpha_composite(canvas)
    return tint(out, grade, sat)


def bleed_and_save(img, dst):
    arr = np.array(img.convert("RGBA"))
    arr[..., :3] = _bleed(arr[..., :3], arr[..., 3])
    Image.fromarray(arr, "RGBA").save(dst, optimize=True)
    return dst


def atlas(tiles, cols, tw, th):
    rows = (len(tiles) + cols - 1) // cols
    a = Image.new("RGBA", (cols * tw, rows * th), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        a.paste(t, ((i % cols) * tw, (i // cols) * th))
    return a


# --------------------------------------------------------------- atlases ---

def build_round(sets, seed, **kw):
    rng = random.Random(seed)
    leaves = []
    for s, lkw in sets:
        leaves += load_leaves(s, **lkw)
    print("  %d leaves" % len(leaves))
    tiles = [make_round_cluster(leaves, rng, 512, **kw) for _ in range(16)]
    return atlas(tiles, 4, 512, 512)


BARKS = {
    # kind: (Poly Haven asset, use)
    "plane": ("bark_platanus", "street/park broadleaf trunks (beech / hornbeam / lilac types)"),
    "oak": ("bark_brown_02", "oak-type broadleaf trunks"),
    "cedar": ("chinese_cedar_bark", "conifer trunks"),
    "palm": ("palm_tree_bark", "palm trunks"),
}


def build_bark(kind, asset, use):
    src = polyhaven(asset, "1k", maps=("Diffuse", "nor_gl"))
    save_color(src["diff"], out(FAMILY, "foliage_bark_%s_albedo.jpg" % kind), 1024, quality=88)
    save_normal(src["nor_gl"], out(FAMILY, "foliage_bark_%s_normal.png" % kind), 512)
    info = polyhaven_info(asset)
    authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
    credit(FAMILY, info.get("name", asset), authors, "https://polyhaven.com/a/" + asset, use=use)


def patch_imports():
    """Godot import flags (ART_BIBLE.md §25): VRAM compressed (BPTC), mipmaps,
    normal maps flagged. Needs the .import files Godot writes on the first
    `godot --headless --path . --import`; run this script again afterwards."""
    d = os.path.join(ROOT, "assets", "textures", FAMILY)
    missing = 0
    for fn in sorted(os.listdir(d)):
        if not fn.startswith("foliage_") or not fn.endswith((".png", ".jpg")):
            continue
        path = os.path.join(d, fn + ".import")
        if not os.path.exists(path):
            missing += 1
            continue
        want = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true",
                "process/fix_alpha_border": "true", "detect_3d/compress_to": "0",
                "compress/normal_map": "1" if fn.endswith("_normal.png") else "0"}
        lines = open(path).read().split("\n")
        for i, line in enumerate(lines):
            k = line.split("=", 1)[0]
            if k in want:
                lines[i] = "%s=%s" % (k, want[k])
        open(path, "w").write("\n".join(lines))
    if missing:
        print("%d textures have no .import yet: run `godot --headless --path . --import`, then this script again" % missing)


def main(which):
    # Godot must not scan the download cache (build/ is gitignored).
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()
    todo = which or ["broadleaf_a", "broadleaf_b", "broadleaf_c", "shrub", "conifer", "palm", "bark"]
    if "broadleaf_a" in todo:
        print("broadleaf_a")
        a = build_round([("LeafSet024", {}), ("LeafSet014", {})], 11, grade=(0.74, 0.8, 0.68), sat=0.9)
        bleed_and_save(a, out(FAMILY, "foliage_leaves_broadleaf_a.png"))
        credit(FAMILY, "Leaf Set 024, Leaf Set 014", "ambientCG", "https://ambientcg.com/a/LeafSet024",
               use="broadleaf (street/park tree) leaf-cluster atlas")
    if "broadleaf_b" in todo:
        print("broadleaf_b")
        a = build_round([("LeafSet016", {})], 12, grade=(0.72, 0.78, 0.6), sat=0.9, leaf_len=(0.095, 0.13), n_leaves=(90, 120))
        bleed_and_save(a, out(FAMILY, "foliage_leaves_broadleaf_b.png"))
        credit(FAMILY, "Leaf Set 016", "ambientCG", "https://ambientcg.com/a/LeafSet016",
               use="broadleaf (oak type) leaf-cluster atlas")
    if "broadleaf_c" in todo:
        print("broadleaf_c")
        a = build_round([("LeafSet004", {}), ("LeafSet023", {"rot": 90})], 16, grade=(0.7, 0.8, 0.66), sat=0.9,
                        leaf_len=(0.1, 0.14), n_leaves=(80, 110))
        bleed_and_save(a, out(FAMILY, "foliage_leaves_broadleaf_c.png"))
        credit(FAMILY, "Leaf Set 004, Leaf Set 023", "ambientCG", "https://ambientcg.com/a/LeafSet004",
               use="broadleaf (heart-shaped leaves, lilac / linden type) leaf-cluster atlas")
    if "shrub" in todo:
        print("shrub")
        a = build_round([("LeafSet002", {})], 13, grade=(0.72, 0.8, 0.64), sat=0.9,
                        leaf_len=(0.15, 0.22), n_leaves=(45, 65), fan=(15, 55), n_side=(5, 7))
        bleed_and_save(a, out(FAMILY, "foliage_leaves_shrub.png"))
        credit(FAMILY, "Leaf Set 002", "ambientCG", "https://ambientcg.com/a/LeafSet002",
               use="shrub and hedge leaf-cluster atlas (box-type sprigs)")
    if "conifer" in todo:
        print("conifer")
        rng = random.Random(14)
        sprays = load_leaves("LeafSet019", rot=90)
        tiles = [make_conifer_branch(sprays, rng, grade=(0.62, 0.74, 0.6), sat=0.9) for _ in range(8)]
        bleed_and_save(atlas(tiles, 2, 1024, 512), out(FAMILY, "foliage_leaves_conifer.png"))
        credit(FAMILY, "Leaf Set 019", "ambientCG", "https://ambientcg.com/a/LeafSet019", use="conifer branch-spray atlas")
    if "palm" in todo:
        print("palm")
        rng = random.Random(15)
        blades = load_leaves("Foliage008", rot=90, min_area=0.0006)
        tiles = [make_palm_frond(blades, rng, grade=(0.8, 0.9, 0.62), sat=0.95),
                 make_palm_frond(blades, rng, n_pairs=64, angle=(56, 74), width=(2.0, 2.8), reach=0.4, grade=(0.78, 0.86, 0.6), sat=0.95)]
        bleed_and_save(atlas(tiles, 1, 2048, 1024), out(FAMILY, "foliage_leaves_palm.png"))
        credit(FAMILY, "Foliage 008", "ambientCG", "https://ambientcg.com/a/Foliage008", use="palm frond atlas (blades as leaflets)")
    if "bark" in todo:
        print("bark")
        for kind, (asset, use) in BARKS.items():
            build_bark(kind, asset, use)
    write_sources(FAMILY)
    patch_imports()


if __name__ == "__main__":
    main(sys.argv[1:])
