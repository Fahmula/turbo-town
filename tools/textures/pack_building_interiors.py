#!/usr/bin/env python3
"""Packs the room faces rendered by tools/blender/make_building_interiors.py
(build/interiors/<room>_<face>.png) into two atlases:

    assets/textures/building/facade_interiors_rooms.jpg   (homes and offices)
    assets/textures/building/facade_interiors_shops.jpg   (ground-floor shops)

Each atlas is 2048 x 2048: 8 x 8 cells of 256 px. Room r, face f (0 back,
1 left, 2 right, 3 floor, 4 ceiling) sits in cell r * 5 + f, row-major.
The face image (248 px) is inset by a 4 px replicated border so bilinear
filtering and the first mip levels don't bleed into the neighbouring cell.
The shader (facade_common.gdshaderinc: room_sample) undoes the inset.
Rooms are listed in build/interiors/rooms.json (written by the renderer).
Run from the project root; the Blender script calls it when it finishes.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "build", "interiors")
DST = os.path.join(ROOT, "assets", "textures", "building")
FACES = ["back", "left", "right", "floor", "ceiling"]
CELL = 256
PAD = 4


def pack(names, filename):
    atlas = np.zeros((2048, 2048, 3), np.uint8)
    for r, name in enumerate(names):
        for f, face in enumerate(FACES):
            im = Image.open(os.path.join(SRC, "%s_%s.png" % (name, face))).convert("RGB")
            im = im.resize((CELL - 2 * PAD, CELL - 2 * PAD), Image.LANCZOS)
            a = np.pad(np.asarray(im), ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
            idx = r * 5 + f
            cx, cy = (idx % 8) * CELL, (idx // 8) * CELL
            atlas[cy:cy + CELL, cx:cx + CELL] = a
    Image.fromarray(atlas).save(os.path.join(DST, filename), quality=92, optimize=True)
    print("packed", len(names), "rooms ->", filename)


def main():
    os.makedirs(DST, exist_ok=True)
    rooms = json.load(open(os.path.join(SRC, "rooms.json")))
    pack(rooms["rooms"], "facade_interiors_rooms.jpg")
    pack(rooms["shops"], "facade_interiors_shops.jpg")


if __name__ == "__main__":
    main()
