"""Downloads the CC0 material scans behind the street-prop / landmark shader
(assets/shaders/street_props.gdshader) and packs them into three texture
arrays (4 x 4 = 16 layers of 512 x 512 each, one atlas image per map):

    assets/textures/props/props_albedo.jpg   detail albedo, see below
    assets/textures/props/props_normal.png   tangent-space normals (OpenGL, Y+)
    assets/textures/props/props_orm.png      R = AO, G = roughness, B = metallic

Godot imports each atlas as a Texture2DArray (importer `2d_array_texture`,
4 x 4 slices; see the .import files). The shader picks a layer from the
material class stored in the mesh's vertex colour alpha, so a whole lamp
post or a block of roof clutter is still one draw call.

The albedo is NOT the scan's colour: every channel is divided by its own mean
(in linear light), so what is stored is the *variation* of the material
(grain, scratches, dirt, weave) around 1.0, encoded as ratio / 5 in sRGB.
The shader multiplies it into the colour that comes from the mesh's vertex
colours, so one scan serves every paint colour. Roughness is remapped to the
ART_BIBLE.md section 6 ranges (target mean + scaled contrast).

Run from the project root (needs Pillow + numpy):  python3 tools/textures/fetch_props.py
Models (hydrant, buoys...) are fetched by tools/blender/fetch_props_models.py.
Layer order here == LAYER table in street_props.gdshader. Keep them in sync.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from fetch_common import (ambientcg, polyhaven, polyhaven_info, credit, out, write_sources, ROOT)  # noqa: E402

SIZE = 512
COLS = 4
RATIO_SCALE = 5.0     # stored value = ratio / RATIO_SCALE (in linear), see header

# name, source ("acg"/"ph", id), roughness target (mean, contrast), chroma kept
# (0 = only the luminance variation, 1 = per-channel variation), use.
# index == layer in the texture arrays.
LAYERS = [
    ("paint",     ("acg", "Metal029"),             (0.52, 1.0), 0.2, "painted steel / powder coat: poles, cabinets, signal heads"),
    ("galv",      ("acg", "Metal011"),             (0.44, 0.8), 0.2, "galvanised and bare steel: guardrails, gantries, frames"),
    ("concrete",  ("acg", "Concrete034"),          (0.88, 0.8), 0.3, "cast concrete and render: bases, piers, towers, cottages"),
    ("plastic",   ("acg", "Plastic013B"),          (0.55, 1.0), 0.1, "moulded plastic: cones, markers, bins"),
    ("rubber",    ("acg", "Rubber004"),            (0.88, 0.6), 0.1, "rubber and black trim: tyres, bumpers, mounts"),
    ("fabric",    ("acg", "Fabric035"),            (0.92, 0.5), 0.0, "canvas: awnings, windsock"),
    ("wood",      ("ph",  "silver_oak_veneer_01"), (0.78, 0.8), 0.5, "timber grain: bench slats, crates, battens"),
    ("deck",      ("ph",  "plywood"),              (0.66, 0.8), 0.4, "plywood face under paint: ramp decks, signs"),
    ("corrug_a",  ("ph",  "container_side"),       (0.5, 0.9),  0.2, "corrugated steel: shipping containers"),
    ("corrug_b",  ("ph",  "box_profile_metal_sheet"), (0.46, 0.9), 0.2, "box-profile steel cladding: hangars"),
    ("plate",     ("acg", "DiamondPlate001"),      (0.42, 0.9), 0.2, "diamond tread plate: ramp skins, walkways, loop"),
    ("timber",    ("ph",  "rough_wood"),           (0.88, 0.7), 0.6, "weathered timber: piers, piles, decking"),
    ("rust",      ("ph",  "rusty_metal_04"),       (0.62, 1.0), 1.0, "oxidised steel: old harbour ironwork"),
    ("worn",      ("acg", "PaintedMetal003"),      (0.55, 1.0), 0.0, "paint with chips and scuffs: crane, hydrants, kerb-side steel"),
    ("brushed",   ("acg", "Metal009"),             (0.34, 0.9), 0.1, "brushed stainless / aluminium: rails, trim, fittings"),
    ("slate",     ("acg", "RoofingTiles003"),      (0.72, 0.7), 0.2, "roof slate: keeper's cottage, kiosks"),
]



def srgb_to_lin(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(l):
    l = np.clip(l, 0.0, 1.0)
    return np.where(l <= 0.0031308, l * 12.92, 1.055 * np.power(l, 1 / 2.4) - 0.055) * 255.0


def load(path, mode):
    img = Image.open(path).convert(mode)
    if img.size != (SIZE, SIZE):
        img = img.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(img).astype(np.float32)


def fetch(src):
    kind, ident = src
    if kind == "acg":
        got = ambientcg(ident, "1K")
        return {"diff": got["Color"], "nor": got["NormalGL"], "rough": got.get("Roughness"),
                "ao": got.get("AmbientOcclusion"), "metal": got.get("Metalness")}
    got = polyhaven(ident, "1k", maps=("Diffuse", "nor_gl", "Rough", "AO", "Metal"))
    return {"diff": got["diff"], "nor": got["nor_gl"], "rough": got.get("rough"),
            "ao": got.get("ao"), "metal": got.get("metal")}


def process(name, src, rough_t, chroma):
    files = fetch(src)
    rgb = srgb_to_lin(load(files["diff"], "RGB"))
    mean = rgb.reshape(-1, 3).mean(axis=0)
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    lum_ratio = (lum / max(float(lum.mean()), 1e-4))[..., None]
    chan_ratio = rgb / np.maximum(mean, 1e-4)
    ratio = np.clip(lum_ratio * (1.0 - chroma) + chan_ratio * chroma, 0.0, RATIO_SCALE)
    alb = lin_to_srgb(ratio / RATIO_SCALE)
    nor = load(files["nor"], "RGB")
    rough = load(files["rough"], "L") / 255.0 if files["rough"] else np.full((SIZE, SIZE), 0.6, np.float32)
    rough = np.clip(rough_t[0] + (rough - rough.mean()) * rough_t[1], 0.06, 1.0)
    ao = load(files["ao"], "L") / 255.0 if files["ao"] else np.ones((SIZE, SIZE), np.float32)
    metal = load(files["metal"], "L") / 255.0 if files["metal"] else np.zeros((SIZE, SIZE), np.float32)
    orm = np.stack([ao * 255.0, rough * 255.0, metal * 255.0], axis=-1)
    return alb, nor, orm


def main():
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()   # keep Godot out of the download cache
    atlas ={k: Image.new("RGB", (SIZE * COLS, SIZE * COLS)) for k in ("alb", "nor", "orm")}
    for i, (name, src, rough_t, chroma, use) in enumerate(LAYERS):
        print("layer %2d %-9s %s" % (i, name, src))
        alb, nor, orm = process(name, src, rough_t, chroma)
        x, y = (i % COLS) * SIZE, (i // COLS) * SIZE
        atlas["alb"].paste(Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8)), (x, y))
        atlas["nor"].paste(Image.fromarray(np.clip(nor, 0, 255).astype(np.uint8)), (x, y))
        atlas["orm"].paste(Image.fromarray(np.clip(orm, 0, 255).astype(np.uint8)), (x, y))
        kind, ident = src
        if kind == "acg":
            credit("props", ident, "ambientCG (Lennart Demes)", "https://ambientcg.com/a/%s" % ident, "CC0 1.0", "layer %d %s: %s" % (i, name, use))
        else:
            info = polyhaven_info(ident)
            credit("props", info.get("name", ident), ", ".join(info.get("authors", {}).keys()) or "Poly Haven",
                   "https://polyhaven.com/a/%s" % ident, "CC0 1.0", "layer %d %s: %s" % (i, name, use))
    atlas["alb"].save(out("props", "props_albedo.jpg"), quality=90, optimize=True)
    atlas["nor"].save(out("props", "props_normal.png"), optimize=True)
    atlas["orm"].save(out("props", "props_orm.png"), optimize=True)
    write_props_imports()
    write_sources("props")
    print("done")


IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://assets/textures/props/%(file)s"

[params]

compress/mode=2
compress/high_quality=%(hq)s
compress/lossy_quality=0.8
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=4
slices/vertical=4
"""


def write_props_imports():
    """Godot .import files, only when missing (Godot rewrites them on import,
    adding the cache paths). The array importer has no normal-map flag: the
    shader rebuilds Z itself. NOTE: Godot must be started once from the
    project root so the imports run (`godot --headless --path . --import`);
    build/ needs a .gdignore or Godot imports the download cache too."""
    for fn, hq in (("props_albedo.jpg", "true"), ("props_normal.png", "true"), ("props_orm.png", "false")):
        path = out("props", fn) + ".import"
        if os.path.exists(path):
            continue
        with open(path, "w") as f:
            f.write(IMPORT % {"file": fn, "hq": hq})


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
