#!/usr/bin/env python3
"""Turns the Downtown City MegaKit's textures into the few texture arrays the
game's one megakit material samples (assets/shaders/megakit.gdshader).

    python3 tools/megakit/build_megakit_textures.py

Downloads/extracts the kit first if needed (megakit_common.fetch). Outputs
in assets/textures/megakit/ (committed, with their .import files):

  megakit_albedo.jpg    Texture2DArray, 8 slices of 1024^2, sRGB colour.
  megakit_nrm.png       Texture2DArray, same slices: R,G = normal X,Y
                        (OpenGL / Y+, 0.5 = flat), B = roughness, A = AO.
                        Metallic is dropped: the kit's only metal is painted
                        cast iron and grilles, which ART_BIBLE §6 treats as
                        paint (metallic 0).
  megakit_rooms.jpg     Texture2DArray, 3 slices of 512^2: the one-point
                        perspective room photos for the fake interiors
                        (lit office 1, lit office 2, dark room).
  megakit_covers.png    Texture2DArray, 2 slices of 512^2 RGBA: blinds and
                        curtains atlases drawn over the rooms.
  megakit_detail.png    1024^2: R,G = the kit's "fake bevel" corner normal
                        (sampled with UV2), B = drip/streak noise, A = 1.
  megakit_decals.png    1024^2 RGBA: road and sidewalk markings atlas.

Slice order is a contract with scripts/world/downtown/megakit.gd (LAYER_*)
and the shader: 0 brick, 1 trim stone, 2 metal/concrete, 3 ornaments,
4 roof slate, 5 asphalt, 6 concrete, 7 soil.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import megakit_common as mk  # noqa: E402

OUT = os.path.join(mk.ROOT, "assets", "textures", "megakit")
SIZE = 1024

# (albedo, normal, orm) per slice; None = flat / defaults.
LAYERS = [
    ("T_RedBrick_BaseColor", "T_RedBrick_Normal", "T_RedBrick_ORM"),
    ("T_Trim_BaseColor", "T_Trim_Normal", "T_Trim_ORM"),
    ("T_MetalConcrete_BaseColor", "T_MetalConcrete_Normal", "T_MetalConcrete_ORM"),
    ("T_Ornaments_BaseColor", "T_Ornaments_Normal", "T_Ornaments_ORM"),
    ("T_RoofSlate_BaseColor", "T_RoofSlate_Normal", "T_RoofSlate_ORM"),
    ("T_Concrete_Asphalt_BaseColor", "T_Concrete_Normal", "T_Concrete_ORM"),
    ("T_Concrete_BaseColor", "T_Concrete_Normal", "T_Concrete_ORM"),
    ("T_Dirt_BaseColor", "T_Dirt_Normal", "T_Dirt_ORM"),
]


def tex(name):
    return Image.open(os.path.join(mk.TEXTURES, name + ".png"))


def rgb(name, size):
    return np.asarray(tex(name).convert("RGB").resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def normal_xy(name, size):
    """Resized normal map, renormalised, as (x, y) in 0..1."""
    n = np.asarray(tex(name).convert("RGB").resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    v = n * 2.0 - 1.0
    v /= np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-6)
    return v[..., :2] * 0.5 + 0.5


def to8(a):
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def write_import(path, kind, slices=1):
    """Godot keeps an existing .import's importer and params on first import."""
    ipath = path + ".import"
    if kind == "array":
        txt = ("[remap]\n\nimporter=\"2d_array_texture\"\ntype=\"CompressedTexture2DArray\"\n\n[params]\n\n"
               "compress/mode=2\ncompress/high_quality=true\ncompress/lossy_quality=0.7\n"
               "compress/hdr_compression=1\ncompress/channel_pack=0\nmipmaps/generate=true\n"
               "mipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n" % slices)
    else:
        txt = ("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
               "compress/mode=2\ncompress/high_quality=true\ncompress/lossy_quality=0.7\n"
               "compress/hdr_compression=1\ncompress/normal_map=2\ncompress/channel_pack=0\n"
               "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nprocess/fix_alpha_border=true\n"
               "process/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
               "process/size_limit=0\ndetect_3d/compress_to=0\n")
    if not os.path.exists(ipath):
        with open(ipath, "w") as f:
            f.write(txt)


def main():
    mk.fetch()
    os.makedirs(OUT, exist_ok=True)

    albedo = []
    nrm = []
    for a, n, o in LAYERS:
        albedo.append(to8(rgb(a, SIZE)))
        orm = rgb(o, SIZE)
        ao = orm[..., 0]
        if a == "T_Dirt_BaseColor":
            ao = np.ones_like(ao)  # the kit's soil ORM has AO = 0 everywhere
        xy = normal_xy(n, SIZE)
        nrm.append(to8(np.dstack([xy[..., 0], xy[..., 1], orm[..., 1], ao])))
    p = os.path.join(OUT, "megakit_albedo.jpg")
    Image.fromarray(np.vstack(albedo), "RGB").save(p, quality=92, subsampling=0)
    write_import(p, "array", len(LAYERS))
    p = os.path.join(OUT, "megakit_nrm.png")
    Image.fromarray(np.vstack(nrm), "RGBA").save(p, optimize=True)
    write_import(p, "array", len(LAYERS))

    rooms = [to8(rgb(r, 512)) for r in ("T_lit_interior_1", "T_lit_interior_2", "T_dark_interior")]
    p = os.path.join(OUT, "megakit_rooms.jpg")
    Image.fromarray(np.vstack(rooms), "RGB").save(p, quality=92, subsampling=0)
    write_import(p, "array", len(rooms))

    covers = [np.asarray(tex(c).convert("RGBA").resize((512, 512), Image.LANCZOS)) for c in ("T_Blinds", "T_Curtains")]
    p = os.path.join(OUT, "megakit_covers.png")
    Image.fromarray(np.vstack(covers), "RGBA").save(p, optimize=True)
    write_import(p, "array", len(covers))

    bevel = normal_xy("T_CornerDamage_Normal", SIZE)
    drips = np.asarray(tex("T_Noise_Drips").convert("L").resize((SIZE, SIZE), Image.LANCZOS), dtype=np.float32) / 255.0
    p = os.path.join(OUT, "megakit_detail.png")
    Image.fromarray(to8(np.dstack([bevel[..., 0], bevel[..., 1], drips, np.ones_like(drips)])), "RGBA").save(p, optimize=True)
    write_import(p, "texture")

    p = os.path.join(OUT, "megakit_decals.png")
    tex("T_Street_Decals").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS).save(p, optimize=True)
    write_import(p, "texture")

    with open(os.path.join(OUT, "SOURCES.md"), "w") as f:
        f.write("# Sources\n\nAll textures here are processed (resized, repacked into arrays) from the\n"
                "**Downtown City MegaKit** (Standard, free) by **Quaternius**, CC0 1.0:\n"
                "https://quaternius.com/packs/downtowncitymegakit.html\n\n"
                "Made by `tools/megakit/build_megakit_textures.py`. See ASSET_MANIFEST.md.\n")
    for fn in sorted(os.listdir(OUT)):
        print("%-28s %6d KB" % (fn, os.path.getsize(os.path.join(OUT, fn)) // 1024))


if __name__ == "__main__":
    main()
