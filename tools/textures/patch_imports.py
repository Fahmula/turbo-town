#!/usr/bin/env python3
"""Sets the Godot import options of freshly fetched textures (ART_BIBLE.md §8):
VRAM compressed, mipmaps, and normal-map compression for *_normal.png.

Godot writes a default .import next to each new image the first time it
imports the project, so the order is:

    godot --headless --path . --import
    python3 tools/textures/patch_imports.py assets/textures/terrain
    godot --headless --path . --import

(`--` separate directories may be passed.) Files named *_normal.png or
*normal*.png get compress/normal_map=1; everything else keeps the detect-off
default. Colour textures are sRGB by default in Godot's shaders (source_color).
"""
import os
import re
import sys


def patch(path):
    name = os.path.basename(path)[:-len(".import")]
    is_normal = "normal" in name.lower() and name.lower().endswith(".png")
    with open(path) as f:
        txt = f.read()
    wanted = {"compress/mode": "2", "compress/high_quality": "false", "mipmaps/generate": "true",
              "compress/normal_map": "1" if is_normal else "0"}
    for k, v in wanted.items():
        txt, n = re.subn(r"^%s=.*$" % re.escape(k), "%s=%s" % (k, v), txt, flags=re.M)
        if n == 0:
            print("warning: %s has no %s" % (path, k))
    with open(path, "w") as f:
        f.write(txt)


def main():
    for d in sys.argv[1:]:
        for root, _, files in os.walk(d):
            for fn in sorted(files):
                if fn.endswith((".png.import", ".jpg.import")):
                    patch(os.path.join(root, fn))
                    print("patched", os.path.join(root, fn))


if __name__ == "__main__":
    main()
