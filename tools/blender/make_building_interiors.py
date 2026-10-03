"""Renders the rooms behind building windows (interior mapping) for
assets/shaders/facade.gdshader (realism branch).

Run headless from the project root:
    blender -b -P tools/blender/make_building_interiors.py
    blender -b -P tools/blender/make_building_interiors.py -- --only living_0,cafe_0 --samples 24

Each room is a 3 x 3 x 3 m cube lit from the inside (lights ON; the shader
dims it by day and brightens it at night). The camera sits at the centre
and renders the five faces a viewer outside can see (back, left, right,
floor, ceiling) at 90 degrees; the shader intersects the view ray with a
box of the real room size, so a face texel is the colour at that point of
the wall: parallax-correct furniture on a flat box.

Room frame (as in the shader): x to the right seen from outside, y up,
z into the building. Blender: X = x, Y = z, Z = y. Face images:
    back    u = x,  v = y        left   u = +z, v = y      right  u = -z, v = y
    floor   u = x,  v = z        ceiling u = x, v = -z   (v up in the image)

Faces go to build/interiors/<room>_<face>.png; tools/textures/
pack_building_interiors.py then packs them into
assets/textures/building/facade_interiors_*.jpg (called at the end).
Everything is seeded: re-running reproduces the atlases.
"""
import math
import os
import random
import subprocess
import sys

import bpy

ROOT = os.getcwd()
OUT = os.path.join(ROOT, "build", "interiors")
FACE = 256
LIGHT_SCALE = 0.3  # overall room brightness (the shader multiplies it anyway)
H = 1.5  # half size of the cube (3 m)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
SAMPLES = 64
for i, a in enumerate(argv):
    if a == "--only":
        ONLY = set(argv[i + 1].split(","))
    if a == "--samples":
        SAMPLES = int(argv[i + 1])

# ------------------------------------------------------------------ helpers

_mats = {}


def mat(color, rough=0.6, emit=0.0, metal=0.0, name=None):
    key = (tuple(round(c, 3) for c in color[:3]), round(rough, 2), round(emit, 2), metal)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name or "m%d" % len(_mats))
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (color[0], color[1], color[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def srgb(h):
    """'#RRGGBB' -> linear rgb tuple."""
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def box(center, size, m, rot=0.0):
    """Axis-aligned (rotated about Z by `rot`) box; coordinates in room
    metres, X right, Y into the room, Z up; centre of the room is the origin."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.scale = size
    o.rotation_euler[2] = rot
    o.data.materials.append(m)
    return o


def cyl(center, radius, height, m, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=center)
    o = bpy.context.active_object
    o.data.materials.append(m)
    return o


def sphere(center, radius, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=radius, location=center)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(m)
    return o


def on_floor(x, y, w, d, h, m, rot=0.0):
    return box((x, y, -H + h * 0.5), (w, d, h), m, rot)


def panel_light(x, y, w, d, color, strength, z=H - 0.02):
    """Emissive ceiling panel plus a soft area light below it."""
    box((x, y, z + 0.01), (w, d, 0.03), mat(color, 0.4, emit=strength * 0.6))
    bpy.ops.object.light_add(type="AREA", location=(x, y, z - 0.05))
    L = bpy.context.active_object
    L.data.shape = "RECTANGLE"
    L.data.size = w
    L.data.size_y = d
    L.data.color = color
    L.data.energy = strength * 90.0 * w * d * LIGHT_SCALE
    return L


def point_light(x, y, z, color, power):
    bpy.ops.object.light_add(type="POINT", location=(x, y, z))
    L = bpy.context.active_object
    L.data.color = color
    L.data.energy = power * LIGHT_SCALE
    L.data.shadow_soft_size = 0.15
    return L


def picture(x, z, w, h, wall, rng, side="back"):
    """A framed picture with a few abstract colour blocks."""
    frame = mat(srgb(rng.choice(["#2b2622", "#d8d2c4", "#6b4a2f", "#1d1d1f"])), 0.5)
    inner = mat(srgb(rng.choice(["#e9e4d8", "#cfd8d4", "#e6d6b8"])), 0.8)
    if side == "back":
        y = H - 0.03
        box((x, y, z), (w, 0.04, h), frame)
        box((x, y - 0.02, z), (w - 0.08, 0.02, h - 0.08), inner)
        for _ in range(rng.randint(2, 4)):
            bw = rng.uniform(0.1, w * 0.45)
            bh = rng.uniform(0.1, h * 0.45)
            c = srgb(rng.choice(["#b5523a", "#3e6f8e", "#d6a53a", "#4c7a5a", "#2b2f3a", "#c9c3b4"]))
            box((x + rng.uniform(-w * 0.28, w * 0.28), y - 0.035, z + rng.uniform(-h * 0.28, h * 0.28)), (bw, 0.01, bh), mat(c, 0.7))
    else:
        sgn = -1 if side == "left" else 1
        xx = sgn * (H - 0.03)
        box((xx, x, z), (0.04, w, h), frame)
        box((xx - sgn * 0.02, x, z), (0.02, w - 0.08, h - 0.08), inner)
        for _ in range(rng.randint(2, 3)):
            c = srgb(rng.choice(["#b5523a", "#3e6f8e", "#d6a53a", "#4c7a5a", "#2b2f3a"]))
            box((xx - sgn * 0.035, x + rng.uniform(-w * 0.25, w * 0.25), z + rng.uniform(-h * 0.25, h * 0.25)),
                (0.01, rng.uniform(0.1, w * 0.4), rng.uniform(0.1, h * 0.4)), mat(c, 0.7))


def books(cx, cy, cz, w, h, depth, rng, axis="x"):
    """A row of books on a shelf starting at (cx, cy, cz) (shelf top)."""
    x = -w * 0.5
    while x < w * 0.5 - 0.04:
        bw = rng.uniform(0.025, 0.06)
        bh = rng.uniform(h * 0.6, h)
        c = srgb(rng.choice(["#7a2e2a", "#2f4a6b", "#d8cfae", "#3b5b3f", "#c08a3a", "#222222", "#8a8a84", "#6b3b5b", "#b55a3a"]))
        if axis == "x":
            box((cx + x + bw * 0.5, cy, cz + bh * 0.5), (bw, depth, bh), mat(c, 0.7))
        else:
            box((cx, cy + x + bw * 0.5, cz + bh * 0.5), (depth, bw, bh), mat(c, 0.7))
        x += bw + rng.uniform(0.0, 0.01)


def bookcase(cx, cy, w, h, rng, side="back"):
    """Open wooden bookcase against a wall: back panel, end panels, boards, rows of books."""
    wood = mat(srgb(rng.choice(["#5b3d28", "#8a6a44", "#c9b48a", "#2e2a26"])), 0.55)
    dark = mat(srgb("#2a2420"), 0.8)
    shelves = 5
    gap = (h - 0.06) / shelves
    if side == "back":
        box((cx, H - 0.015, -H + h * 0.5), (w, 0.03, h), dark)
        for e in (-1, 1):
            box((cx + e * (w * 0.5 - 0.015), H - 0.19, -H + h * 0.5), (0.03, 0.34, h), wood)
        for s in range(shelves + 1):
            box((cx, H - 0.19, -H + 0.015 + s * gap), (w, 0.34, 0.03), wood)
        for s in range(shelves):
            books(cx, H - 0.15, -H + 0.03 + s * gap + 0.015, w - 0.1, gap - 0.06, 0.22, rng, "x")
    else:
        sgn = -1 if side == "left" else 1
        xw = sgn * (H - 0.015)
        xs = sgn * (H - 0.19)
        box((xw, cy, -H + h * 0.5), (0.03, w, h), dark)
        for e in (-1, 1):
            box((xs, cy + e * (w * 0.5 - 0.015), -H + h * 0.5), (0.34, 0.03, h), wood)
        for s in range(shelves + 1):
            box((xs, cy, -H + 0.015 + s * gap), (0.34, w, 0.03), wood)
        for s in range(shelves):
            books(sgn * (H - 0.15), cy, -H + 0.03 + s * gap + 0.015, w - 0.1, gap - 0.06, 0.22, rng, "y")


def plant(x, y, rng, h=0.9):
    pot = mat(srgb(rng.choice(["#8c5a3c", "#d8d2c4", "#33373a"])), 0.6)
    leaf = mat(srgb(rng.choice(["#3f6b34", "#4f7a3a", "#2f5a30"])), 0.5)
    cyl((x, y, -H + 0.15), 0.16, 0.3, pot)
    for k in range(5):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.0, 0.14)
        sphere((x + math.cos(a) * r, y + math.sin(a) * r, -H + 0.45 + rng.uniform(0, h - 0.4)), rng.uniform(0.14, 0.22), leaf)


def chair(x, y, rot, m, seat=0.45):
    on_floor(x, y, 0.42, 0.42, seat, m, rot)
    box((x - math.sin(rot) * 0.0, y, -H + seat + 0.22), (0.42, 0.06, 0.44), m, rot)  # back (rough)


def lamp_floor(x, y, rng, warm=(1.0, 0.72, 0.42)):
    cyl((x, y, -H + 0.7), 0.025, 1.4, mat(srgb("#222222"), 0.4, metal=0.8))
    cyl((x, y, -H + 1.5), 0.17, 0.3, mat(warm, 0.9, emit=3.0))
    point_light(x, y, -H + 1.45, warm, 40)


# -------------------------------------------------------------- room shell

WALLS = ["#e8e2d4", "#d9cfba", "#cfd6d0", "#d9dbe0", "#e2d3c4", "#c9d4c2", "#d8c9c9", "#bfc9d6", "#e5dec8", "#b9a894"]
FLOORS = ["#a8794d", "#c49a68", "#6e4a30", "#8b6a45", "#4a3829", "#bfa57e"]
CARPETS = ["#6b7280", "#5d6b78", "#8a8478", "#4a525c", "#7a6f66", "#3c4a5a"]


def shell(rng, wall_hex=None, floor=("wood", None), ceiling_hex="#f2efe8", wall_colors=None):
    """Floor, ceiling, left/right/back walls and a hidden front wall (for bounce)."""
    wall_hex = wall_hex or rng.choice(WALLS)
    wcol = srgb(wall_hex)
    wm = mat(wcol, 0.85)
    side_m = mat(srgb(rng.choice(WALLS)) if rng.random() < 0.3 else wcol, 0.85)
    ceil_m = mat(srgb(ceiling_hex), 0.9)
    # floor
    kind, hexv = floor
    if kind == "wood":
        fm = bpy.data.materials.new("wood")
        fm.use_nodes = True
        nt = fm.node_tree
        b = nt.nodes["Principled BSDF"]
        base = srgb(hexv or rng.choice(FLOORS))
        brick = nt.nodes.new("ShaderNodeTexBrick")
        brick.inputs["Color1"].default_value = (base[0] * 1.15, base[1] * 1.15, base[2] * 1.15, 1)
        brick.inputs["Color2"].default_value = (base[0] * 0.8, base[1] * 0.8, base[2] * 0.8, 1)
        brick.inputs["Mortar"].default_value = (base[0] * 0.4, base[1] * 0.4, base[2] * 0.4, 1)
        brick.inputs["Scale"].default_value = 6.0
        brick.inputs["Mortar Size"].default_value = 0.006
        brick.inputs["Brick Width"].default_value = 1.6
        brick.inputs["Row Height"].default_value = 0.08
        brick.offset = 0.5
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, math.radians(90))
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], brick.inputs["Vector"])
        nt.links.new(brick.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = 0.35
        floor_m = fm
    elif kind == "carpet":
        floor_m = mat(srgb(hexv or rng.choice(CARPETS)), 0.95)
    else:  # tile / polished concrete
        floor_m = mat(srgb(hexv or "#9a978f"), 0.3)
    box((0, 0, -H - 0.05), (3.2, 3.2, 0.1), floor_m)
    # a thin top layer so the floor texture is on the visible face
    box((0, 0, -H + 0.005), (3.0, 3.0, 0.01), floor_m)
    box((0, 0, H + 0.05), (3.2, 3.2, 0.1), ceil_m)
    box((0, H + 0.05, 0), (3.2, 0.1, 3.2), wm)  # back
    box((-H - 0.05, 0, 0), (0.1, 3.2, 3.2), side_m)  # left
    box((H + 0.05, 0, 0), (0.1, 3.2, 3.2), side_m)  # right
    fw = box((0, -H - 0.05, 0), (3.2, 0.1, 3.2), wm)  # front (invisible to the camera, bounces light)
    fw.visible_camera = False
    # skirting boards
    sk = mat(srgb("#f0ece2"), 0.6)
    box((0, H - 0.01, -H + 0.06), (3.0, 0.02, 0.12), sk)
    box((-H + 0.01, 0, -H + 0.06), (0.02, 3.0, 0.12), sk)
    box((H - 0.01, 0, -H + 0.06), (0.02, 3.0, 0.12), sk)
    return wm


# ----------------------------------------------------------- room designs

WARM = (1.0, 0.72, 0.45)
WARM2 = (1.0, 0.8, 0.58)
COOL = (0.86, 0.93, 1.0)
FABRICS = ["#6d4c41", "#46605f", "#8a3f35", "#4e5b7a", "#8f8777", "#2f2f33", "#a4793f", "#5b6e55"]


def room_living(rng):
    shell(rng)
    fab = mat(srgb(rng.choice(FABRICS)), 0.9)
    # rug
    box((0, 0.2, -H + 0.012), (2.0, 1.6, 0.02), mat(srgb(rng.choice(["#8a8478", "#9c6b4a", "#4a525c", "#b9a98a"])), 0.95))
    # sofa on the back wall (or left wall)
    if rng.random() < 0.65:
        sx = rng.uniform(-0.3, 0.3)
        on_floor(sx, H - 0.45, 1.9, 0.8, 0.42, fab)
        on_floor(sx, H - 0.75, 1.9, 0.2, 0.85, fab)
        for s in (-1, 1):
            on_floor(sx + s * 0.95, H - 0.45, 0.16, 0.8, 0.62, fab)
        picture(sx, 0.35, rng.uniform(0.8, 1.3), rng.uniform(0.5, 0.8), None, rng)
    else:
        on_floor(-H + 0.45, 0.2, 0.8, 1.9, 0.42, fab)
        on_floor(-H + 0.15, 0.2, 0.2, 1.9, 0.85, fab)
        picture(0.2, 0.3, 0.9, 0.7, None, rng, side="left")
        picture(-0.6, 0.35, 1.0, 0.7, None, rng)
    # coffee table
    on_floor(0, 0.25, 0.9, 0.5, 0.36, mat(srgb("#7a5a3c"), 0.45))
    # TV unit on the right wall
    on_floor(H - 0.22, 0.1, 0.4, 1.4, 0.45, mat(srgb("#3b2f28"), 0.5))
    box((H - 0.08, 0.1, -0.1), (0.05, 1.1, 0.65), mat((0.01, 0.01, 0.012), 0.2))
    lamp_floor(rng.choice([-1.2, 1.2]), H - 0.3, rng)
    plant(rng.choice([-1.2, 1.15]), rng.uniform(0.6, 1.1), rng)
    panel_light(0, 0.1, 0.4, 0.4, WARM, 4.0)
    point_light(0, 0.3, 0.9, WARM, 120)


def room_bedroom(rng):
    shell(rng, floor=("carpet", None) if rng.random() < 0.4 else ("wood", None))
    bed = mat(srgb(rng.choice(["#e8e4da", "#cfd6d8", "#b9b0a2", "#d6c9c0"])), 0.9)
    duvet = mat(srgb(rng.choice(FABRICS)), 0.9)
    wood = mat(srgb(rng.choice(["#5b3d28", "#8a6a44", "#2e2a26", "#c9b48a"])), 0.5)
    x = rng.uniform(-0.2, 0.2)
    on_floor(x, H - 1.0, 1.6, 2.0, 0.3, wood)  # frame
    on_floor(x, H - 1.0, 1.5, 1.9, 0.5, bed)  # mattress
    on_floor(x, H - 0.75, 1.52, 1.4, 0.56, duvet)
    on_floor(x, H - 0.1, 1.7, 0.12, 1.2, wood)  # headboard
    for s in (-0.5, 0.5):
        on_floor(x + s, H - 0.35, 0.5, 0.3, 0.64, bed)  # pillows
    for s in (-1, 1):
        on_floor(x + s * 1.1, H - 0.3, 0.42, 0.42, 0.5, wood)
        cyl((x + s * 1.1, H - 0.3, -H + 0.62), 0.1, 0.25, mat(WARM2, 0.9, emit=2.0))
        point_light(x + s * 1.1, H - 0.4, -H + 0.7, WARM, 15)
    # wardrobe on a side wall
    side = rng.choice([-1, 1])
    on_floor(side * (H - 0.3), 0.5, 0.6, 1.6, 2.2, wood)
    box((side * (H - 0.62), 0.5, -H + 1.1), (0.02, 0.02, 1.9), mat(srgb("#aaa"), 0.3, metal=1.0))
    picture(x, 0.55, 0.9, 0.6, None, rng)
    on_floor(0, -0.1, 1.6, 1.2, 0.015, mat(srgb(rng.choice(["#8a8478", "#9c6b4a", "#4a525c"])), 0.95))
    panel_light(0, 0.0, 0.35, 0.35, WARM, 3.2)
    point_light(0, 0.2, 0.9, WARM, 70)


def room_kitchen(rng):
    shell(rng, wall_hex=rng.choice(["#e8e2d4", "#d9dbe0", "#cfd6d0", "#e6dcb8"]), floor=("tile", rng.choice(["#9a978f", "#b9b3a6", "#6e6a64"])))
    cab = mat(srgb(rng.choice(["#e8e4da", "#4e5b7a", "#46605f", "#8a6a44", "#d9d4c6"])), 0.5)
    top = mat(srgb(rng.choice(["#2b2b2d", "#c9c4b8", "#7d7a73"])), 0.3)
    on_floor(0, H - 0.3, 3.0, 0.6, 0.9, cab)
    box((0, H - 0.3, -H + 0.92), (3.0, 0.62, 0.04), top)
    for s in range(6):
        box((-1.25 + s * 0.5, H - 0.6, -H + 0.45), (0.46, 0.02, 0.8), cab)
    # upper cabinets
    box((-0.7, H - 0.2, 0.55), (1.6, 0.36, 0.8), cab)
    box((1.1, H - 0.2, 0.55), (0.8, 0.36, 0.8), cab)
    # hood / window-less splash back
    box((0.6, H - 0.02, -0.02), (1.2, 0.02, 0.5), mat(srgb("#d9d4c6"), 0.3))
    # steel appliance
    on_floor(1.15, H - 0.33, 0.7, 0.62, 1.8, mat(srgb("#b9bcbf"), 0.3, metal=1.0))
    # table & chairs
    tab = mat(srgb(rng.choice(["#8a6a44", "#d9d4c6", "#2e2a26"])), 0.5)
    on_floor(0, 0.1, 1.3, 0.85, 0.75, tab)
    cm = mat(srgb(rng.choice(FABRICS)), 0.8)
    for cx in (-0.35, 0.35):
        for cy, rot in ((-0.55, 0), (0.75, 0)):
            chair(cx, cy + 0.0, rot, cm)
    for s in (-0.5, 0.5):
        cyl((s, 0.1, 0.9), 0.17, 0.3, mat(WARM2, 0.9, emit=3.0))
        box((s, 0.1, H - 0.3), (0.02, 0.02, 1.2), mat(srgb("#222"), 0.4))
    panel_light(0, 0.2, 0.5, 0.5, COOL if rng.random() < 0.5 else WARM, 3.8)
    point_light(0, 0.4, 0.8, WARM2, 90)


def room_study(rng):
    shell(rng, wall_hex=rng.choice(["#cfd6d0", "#c9d4c2", "#bfc9d6", "#d9cfba"]))
    bookcase(-0.65, 0, 1.3, 2.3, rng, side="back")
    bookcase(0.75, 0, 1.2, 2.3, rng, side="back")
    bookcase(0.0, -0.1, 1.9, 2.0, rng, side="right") if rng.random() < 0.6 else None
    desk = mat(srgb(rng.choice(["#5b3d28", "#8a6a44", "#2e2a26"])), 0.45)
    on_floor(-0.2, 0.4, 1.3, 0.65, 0.76, desk)
    box((-0.2, 0.5, -H + 1.0), (0.5, 0.03, 0.32), mat((0.01, 0.01, 0.012), 0.2))
    box((-0.2, 0.52, -H + 0.8), (0.06, 0.03, 0.2), mat(srgb("#222"), 0.4))
    cyl((-0.65, 0.3, -H + 1.0), 0.07, 0.3, mat(WARM2, 0.9, emit=4.0))
    point_light(-0.65, 0.3, -H + 1.1, WARM, 25)
    chair(-0.2, -0.15, 0, mat(srgb(rng.choice(FABRICS)), 0.8))
    plant(1.2, 0.9, rng)
    panel_light(0, 0.1, 0.4, 0.4, WARM, 3.0)
    point_light(0, 0.3, 1.0, WARM, 90)


def room_bare(rng):
    shell(rng, wall_hex=rng.choice(["#e8e2d4", "#e2d3c4", "#dcdcd8"]), floor=("wood", None) if rng.random() < 0.5 else ("tile", "#8a867e"))
    # a few moving boxes / a ladder
    cb = mat(srgb("#b58a58"), 0.8)
    for _ in range(rng.randint(2, 4)):
        on_floor(rng.uniform(-1.1, 1.1), rng.uniform(0.2, 1.1), rng.uniform(0.4, 0.6), rng.uniform(0.4, 0.5), rng.uniform(0.3, 0.5), cb, rng.uniform(0, 1))
    box((-1.2, 0.8, 0.0), (0.3, 0.04, 2.7), mat(srgb("#c9c4b8"), 0.4))
    point_light(0, 0.3, 1.2, rng.choice([WARM, COOL]), 140)
    cyl((0, 0.3, H - 0.1), 0.06, 0.06, mat((1, 0.9, 0.75), 0.4, emit=20.0))


def office_ceiling(rng, color=COOL, n=3):
    for ix in range(2):
        for iy in range(n):
            panel_light(-0.75 + ix * 1.5, -0.8 + iy * 0.95 + 0.3, 0.75, 0.5, color, 0.8)


def desk_row(x, y0, n, m_desk, m_chair, rng, rot=0.0):
    for i in range(n):
        y = y0 + i * 0.85
        on_floor(x, y, 1.2, 0.6, 0.74, m_desk)
        box((x, y + 0.15, -H + 1.0), (0.46, 0.03, 0.3), mat((0.01, 0.01, 0.012), 0.2))
        on_floor(x, y - 0.55, 0.45, 0.45, 0.46, m_chair)
        box((x, y - 0.8, -H + 0.75), (0.45, 0.05, 0.5), m_chair)


def room_office(rng):
    shell(rng, wall_hex=rng.choice(["#e6e4de", "#d9dbe0", "#e2e0d6"]), floor=("carpet", None), ceiling_hex="#eeeeec")
    desk = mat(srgb(rng.choice(["#d9d4c6", "#c9b48a", "#e8e4da"])), 0.5)
    ch = mat(srgb(rng.choice(["#2f2f33", "#3b4452", "#4a4a4e"])), 0.8)
    for x in (-0.8, 0.8):
        desk_row(x, -0.4, 3, desk, ch, rng)
    # low partitions
    for x in (-0.0,):
        on_floor(x, 0.4, 0.05, 2.0, 1.2, mat(srgb(rng.choice(["#8a8f95", "#6b7a8a"])), 0.9))
    # back wall: whiteboard / glass office wall / door
    if rng.random() < 0.5:
        box((0, H - 0.03, 0.1), (1.8, 0.02, 1.0), mat(srgb("#f4f4f2"), 0.2))
    else:
        for i in range(4):
            box((-1.2 + i * 0.8, H - 0.05, 0.2), (0.74, 0.04, 2.2), mat(srgb("#5d7f94"), 0.15))
    plant(1.3, 1.2, rng)
    office_ceiling(rng)
    point_light(0, 0.2, 1.0, COOL, 40)


def room_meeting(rng):
    shell(rng, wall_hex=rng.choice(["#e6e4de", "#d9dbe0", "#bfc9d6"]), floor=("carpet", None), ceiling_hex="#eeeeec")
    tab = mat(srgb(rng.choice(["#5b3d28", "#2e2a26", "#d9d4c6"])), 0.35)
    on_floor(0, 0.2, 1.1, 2.2, 0.74, tab)
    ch = mat(srgb(rng.choice(["#2f2f33", "#46605f", "#8a3f35"])), 0.8)
    for i in range(4):
        on_floor(-0.85, -0.5 + i * 0.6, 0.45, 0.45, 0.46, ch)
        on_floor(0.85, -0.5 + i * 0.6, 0.45, 0.45, 0.46, ch)
    box((0, H - 0.04, 0.2), (1.9, 0.05, 1.1), mat((0.015, 0.015, 0.02), 0.15))  # display
    box((0, H - 0.07, 0.2), (1.7, 0.02, 0.95), mat(srgb("#3b5f8f"), 0.2, emit=0.8))
    office_ceiling(rng, COOL, 2)
    point_light(0, 0.2, 1.0, COOL, 40)


def room_reception(rng):
    shell(rng, wall_hex=rng.choice(["#e6e4de", "#cfd6d0"]), floor=("tile", "#b9b3a6"))
    on_floor(0.3, 0.7, 2.0, 0.6, 1.05, mat(srgb(rng.choice(["#5b3d28", "#2e2a26", "#d9d4c6"])), 0.4))
    box((0.3, 0.7, -H + 1.07), (2.1, 0.7, 0.04), mat(srgb("#c9c4b8"), 0.25))
    # a feature wall with a big logo-less panel
    box((0.0, H - 0.03, 0.2), (2.2, 0.03, 1.5), mat(srgb(rng.choice(["#46605f", "#4e5b7a", "#8a3f35"])), 0.6))
    on_floor(-1.15, -0.4, 0.9, 0.5, 0.45, mat(srgb(rng.choice(FABRICS)), 0.85))
    plant(-1.2, 1.1, rng, h=1.2)
    plant(1.25, -0.2, rng, h=1.2)
    for s in (-0.8, 0.0, 0.8):
        cyl((s, 0.3, H - 0.15), 0.12, 0.2, mat(WARM2, 0.9, emit=5.0))
    panel_light(0, 0.2, 0.5, 0.5, WARM2, 3.2)
    point_light(0, 0.3, 1.0, WARM2, 100)


def room_cubicles(rng):
    shell(rng, floor=("carpet", None), ceiling_hex="#eeeeec", wall_hex="#e2e0d6")
    part = mat(srgb(rng.choice(["#8a8f95", "#6b7a8a", "#7a8a7a"])), 0.9)
    desk = mat(srgb("#d9d4c6"), 0.5)
    ch = mat(srgb("#2f2f33"), 0.8)
    for x in (-1.0, 0.0, 1.0):
        for y in (0.0, 1.1):
            on_floor(x - 0.5, y + 0.1, 0.04, 1.0, 1.35, part)
            on_floor(x, y + 0.6, 1.0, 0.04, 1.35, part)
            on_floor(x, y + 0.2, 0.9, 0.5, 0.74, desk)
            box((x, y + 0.3, -H + 1.0), (0.4, 0.03, 0.28), mat((0.01, 0.01, 0.012), 0.2))
            if rng.random() < 0.7:
                on_floor(x, y - 0.2, 0.42, 0.42, 0.46, ch)
    office_ceiling(rng)
    point_light(0, 0.2, 1.0, COOL, 40)


# ---------------------------------------------------------------- shops

def shop_light_strip(color, y=0.0, n=3, strength=4.0):
    for i in range(n):
        panel_light(0, -0.9 + i * 0.9, 1.6, 0.2, color, strength)


def room_cafe(rng):
    shell(rng, wall_hex=rng.choice(["#8a6a44", "#d9cfba", "#46605f", "#c9b48a"]), floor=("wood", None) if rng.random() < 0.6 else ("tile", "#7d7a73"))
    wood = mat(srgb(rng.choice(["#5b3d28", "#8a6a44", "#2e2a26"])), 0.5)
    # counter on the right, back shelves
    on_floor(0.9, 0.4, 0.7, 2.2, 1.05, wood)
    box((0.9, 0.4, -H + 1.07), (0.78, 2.3, 0.04), mat(srgb("#d9d4c6"), 0.25))
    box((0.9, 0.6, -H + 1.3), (0.4, 0.5, 0.45), mat(srgb("#b9bcbf"), 0.25, metal=1.0))  # machine
    for i in range(3):
        box((-0.6 + i * 0.7, H - 0.15, 0.2), (0.6, 0.3, 0.04), wood)
        for j in range(4):
            cyl((-0.85 + i * 0.7 + j * 0.15, H - 0.15, 0.27), 0.04, 0.1, mat(srgb(rng.choice(["#e8e4da", "#b55a3a", "#d6a53a"])), 0.5))
    # chalkboard menu
    box((-0.8, H - 0.03, 0.55), (1.0, 0.02, 0.8), mat(srgb("#25292b"), 0.7))
    for k in range(6):
        box((-1.0 + rng.uniform(0, 0.4), H - 0.045, 0.3 + k * 0.1), (rng.uniform(0.2, 0.5), 0.005, 0.015), mat(srgb("#e8e4da"), 0.8, emit=0.3))
    # tables and stools near the window side
    tm = mat(srgb(rng.choice(["#2e2a26", "#8a6a44", "#d9d4c6"])), 0.4)
    for p in ((-0.8, -0.3), (-0.5, 0.7)):
        cyl((p[0], p[1], -H + 0.72), 0.32, 0.04, tm)
        cyl((p[0], p[1], -H + 0.36), 0.04, 0.72, mat(srgb("#222"), 0.4, metal=1.0))
        for a in (0.0, 2.1, 4.2):
            cyl((p[0] + 0.5 * math.cos(a), p[1] + 0.5 * math.sin(a), -H + 0.22), 0.18, 0.44, mat(srgb(rng.choice(FABRICS)), 0.8))
    for s in (-0.9, -0.2, 0.5):
        cyl((s, 0.1, 0.6), 0.14, 0.26, mat(WARM2, 0.9, emit=6.0))
        box((s, 0.1, H - 0.4), (0.015, 0.015, 0.8), mat(srgb("#222"), 0.4))
        point_light(s, 0.1, 0.55, WARM, 28)
    panel_light(0, 0.5, 0.4, 0.4, WARM, 2.2)
    point_light(0, 0.3, 1.0, WARM, 80)


def room_boutique(rng):
    shell(rng, wall_hex=rng.choice(["#e8e4da", "#d9dbe0", "#e2d3c4", "#2f2f33"]), floor=("wood", rng.choice(["#c49a68", "#bfa57e"])) if rng.random() < 0.6 else ("tile", "#b9b3a6"))
    rail = mat(srgb("#c9c9c9"), 0.25, metal=1.0)
    cols = ["#7a2e2a", "#2f4a6b", "#d8cfae", "#3b5b3f", "#c08a3a", "#222222", "#8a8a84", "#6b3b5b", "#b55a3a", "#e8e4da"]
    for rx in (-0.8, 0.5):
        cyl((rx, 0.5, -H + 1.4), 0.015, 0.0, rail) if False else None
        box((rx, 0.5, -H + 1.4), (0.9, 0.025, 0.025), rail)
        for k in range(12):
            box((rx - 0.4 + k * 0.073, 0.5, -H + 1.1), (0.04, 0.2, 0.55), mat(srgb(rng.choice(cols)), 0.85))
    # shelves with folded stacks on the back wall and right wall
    shelf = mat(srgb("#d9d4c6"), 0.5)
    for z in (-0.55, 0.15, 0.85):
        box((0, H - 0.18, z), (2.8, 0.36, 0.03), shelf)
        x = -1.3
        while x < 1.3:
            h = rng.uniform(0.12, 0.3)
            box((x + 0.15, H - 0.18, z + 0.015 + h * 0.5), (0.3, 0.3, h), mat(srgb(rng.choice(cols)), 0.9))
            x += 0.34
    # mannequin
    mx = rng.choice([-1.1, 1.15])
    cyl((mx, 0.9, -H + 0.9), 0.17, 1.2, mat(srgb(rng.choice(["#c9c4b8", "#2f2f33", "#8a3f35"])), 0.8))
    sphere((mx, 0.9, -H + 1.62), 0.1, mat(srgb("#e8e4da"), 0.5))
    cyl((mx, 0.9, -H + 0.15), 0.2, 0.03, mat(srgb("#222"), 0.4))
    # table
    on_floor(0.1, -0.4, 0.9, 0.7, 0.8, mat(srgb("#e8e4da"), 0.5))
    for s in (-0.9, 0.0, 0.9):
        box((s, 0.2, H - 0.12), (0.15, 0.2, 0.1), mat((1, 0.95, 0.85), 0.4, emit=9.0))
        point_light(s, 0.2, H - 0.3, (1, 0.9, 0.75), 55)
    panel_light(0, 0.5, 0.6, 0.6, (1.0, 0.92, 0.82), 3.0)
    point_light(0, 0.3, 1.0, (1.0, 0.9, 0.78), 90)


def shelf_unit(cx, cy, w, d, h, rng, axis="x", rows=5, goods=True):
    """A shop gondola: uprights and rows of colourful packages."""
    frame = mat(srgb("#d4d4d0"), 0.4)
    cols = ["#b5523a", "#3e6f8e", "#d6a53a", "#4c7a5a", "#e8e4da", "#8a3f6b", "#e0d060", "#d86a3a", "#6aa0c0", "#2b2f3a"]
    sx, sy = (w, d) if axis == "x" else (d, w)
    box((cx, cy, -H + h * 0.5), (sx, sy, h), frame)
    for r in range(rows):
        z = -H + 0.15 + r * (h - 0.2) / rows
        x = -w * 0.5 + 0.04
        while x < w * 0.5 - 0.05:
            bw = rng.uniform(0.07, 0.16)
            bh = rng.uniform(0.12, (h - 0.2) / rows - 0.04)
            c = srgb(rng.choice(cols))
            if axis == "x":
                box((cx + x + bw * 0.5, cy - d * 0.5 - 0.0, z + bh * 0.5 + 0.02), (bw, d * 0.7, bh), mat(c, 0.6))
            else:
                box((cx - d * 0.5 + d * 0.5, cy + x + bw * 0.5, z + bh * 0.5 + 0.02), (d * 0.7, bw, bh), mat(c, 0.6))
            x += bw + 0.01


def room_grocery(rng):
    shell(rng, wall_hex="#e8e4da", floor=("tile", rng.choice(["#b9b3a6", "#cfcac0"])), ceiling_hex="#eeeeec")
    # fridge wall at the back
    for i in range(4):
        box((-1.1 + i * 0.75, H - 0.2, -0.1), (0.7, 0.4, 2.4), mat(srgb("#dfe6ea"), 0.3))
        for r in range(4):
            for j in range(4):
                box((-1.3 + i * 0.75 + j * 0.15, H - 0.38, -0.95 + r * 0.55), (0.1, 0.1, 0.32), mat(srgb(rng.choice(["#b5523a", "#3e6f8e", "#d6a53a", "#4c7a5a", "#e8e4da", "#ffffff"])), 0.5))
    # aisles
    for x in (-0.7, 0.7):
        shelf_unit(x, 0.2, 0.5, 1.8, 1.5, rng, axis="y", rows=4)
    # checkout
    on_floor(-1.0, -0.9, 0.9, 0.5, 0.9, mat(srgb("#2e2a26"), 0.5))
    shop_light_strip((0.95, 0.98, 1.0), n=3, strength=1.6)
    point_light(0, 0.2, 1.0, (0.95, 0.98, 1.0), 50)


def room_restaurant(rng):
    shell(rng, wall_hex=rng.choice(["#8a3f35", "#d9cfba", "#46605f", "#4e5b7a"]), floor=("wood", "#6e4a30"))
    cloth = mat(srgb("#f0ece2"), 0.9)
    ch = mat(srgb(rng.choice(["#2e2a26", "#5b3d28", "#8a3f35"])), 0.6)
    for p in ((-0.8, -0.4), (0.8, -0.3), (-0.7, 0.9), (0.8, 0.9)):
        cyl((p[0], p[1], -H + 0.75), 0.4, 0.05, cloth)
        cyl((p[0], p[1], -H + 0.37), 0.06, 0.75, cloth)
        for a in (0.3, 1.9, 3.5, 5.1):
            on_floor(p[0] + 0.62 * math.cos(a), p[1] + 0.62 * math.sin(a), 0.4, 0.4, 0.46, ch)
        cyl((p[0], p[1], -H + 0.82), 0.04, 0.12, mat(WARM2, 0.9, emit=8.0))
        point_light(p[0], p[1], -H + 0.9, WARM, 9)
    # bar at the back
    on_floor(0, H - 0.3, 2.4, 0.6, 1.1, mat(srgb("#3b2f28"), 0.4))
    for i in range(6):
        cyl((-1.0 + i * 0.4, H - 0.15, 0.4), 0.05, 0.3, mat(srgb(rng.choice(["#3b5b3f", "#7a2e2a", "#c08a3a", "#e8e4da"])), 0.2))
    box((0, H - 0.1, 0.1), (2.2, 0.04, 0.03), mat(srgb("#5b3d28"), 0.5))
    for s in (-0.9, 0.0, 0.9):
        cyl((s, 0.2, H - 0.5), 0.15, 0.3, mat(WARM2, 0.9, emit=7.0))
        point_light(s, 0.2, H - 0.7, WARM, 40)
    point_light(0, 0.3, 0.8, WARM, 60)


def room_bookshop(rng):
    shell(rng, wall_hex=rng.choice(["#d9cfba", "#c9d4c2", "#e2d3c4"]), floor=("wood", None))
    bookcase(-0.7, 0, 1.3, 2.4, rng, side="back")
    bookcase(0.7, 0, 1.3, 2.4, rng, side="back")
    bookcase(0.0, 0.1, 1.9, 2.2, rng, side="left")
    bookcase(0.0, 0.1, 1.9, 2.2, rng, side="right")
    tb = mat(srgb("#8a6a44"), 0.5)
    on_floor(0.0, 0.3, 0.9, 0.7, 0.8, tb)
    for i in range(6):
        box((-0.3 + (i % 3) * 0.3, 0.3 + (i // 3 - 0.5) * 0.3, -H + 0.85), (0.22, 0.28, 0.06), mat(srgb(rng.choice(["#7a2e2a", "#2f4a6b", "#d8cfae", "#3b5b3f"])), 0.7))
    for s in (-0.8, 0.0, 0.8):
        cyl((s, 0.0, H - 0.2), 0.12, 0.2, mat(WARM2, 0.9, emit=6.0))
        point_light(s, 0.0, H - 0.4, WARM, 40)
    point_light(0, 0.3, 1.0, WARM, 70)


def room_florist(rng):
    shell(rng, wall_hex=rng.choice(["#e8e4da", "#cfd6d0", "#e2d3c4"]), floor=("tile", "#8a867e"))
    # buckets with flowers on the floor and a counter
    cols = ["#b8322a", "#e8c24a", "#d86aa0", "#f0ece2", "#8a3f6b", "#e0883a", "#6aa0c0"]
    for x in (-1.0, -0.4, 0.2, 0.8):
        for y in (0.3, 1.1):
            cyl((x, y, -H + 0.2), 0.16, 0.4, mat(srgb("#b9bcbf"), 0.4, metal=1.0))
            c = mat(srgb(rng.choice(cols)), 0.7)
            for k in range(6):
                a = rng.uniform(0, 6.28)
                r = rng.uniform(0, 0.12)
                sphere((x + math.cos(a) * r, y + math.sin(a) * r, -H + 0.5 + rng.uniform(0, 0.3)), rng.uniform(0.07, 0.11), c)
    on_floor(-0.4, -0.6, 1.2, 0.6, 0.9, mat(srgb("#8a6a44"), 0.5))
    box((0, H - 0.2, 0.3), (2.6, 0.4, 0.04), mat(srgb("#e8e4da"), 0.5))
    plant(1.2, 0.0, rng, h=1.2)
    panel_light(0, 0.3, 0.5, 0.5, (1.0, 0.95, 0.88), 3.5)
    point_light(0, 0.2, 1.0, (1.0, 0.92, 0.82), 100)


def room_hardware(rng):
    shell(rng, wall_hex="#d9dbe0", floor=("tile", "#7d7a73"), ceiling_hex="#eeeeec")
    for x in (-0.9, 0.0, 0.9):
        shelf_unit(x, 0.5, 0.7, 0.4, 2.0, rng, axis="x", rows=5)
    shelf_unit(0.0, H - 0.2, 2.8, 0.4, 2.2, rng, axis="x", rows=5)
    on_floor(1.0, -0.9, 0.8, 0.5, 0.9, mat(srgb("#b5523a"), 0.5))
    shop_light_strip((0.95, 0.98, 1.0), n=3, strength=1.6)
    point_light(0, 0.2, 1.0, (0.95, 0.98, 1.0), 50)


def room_electronics(rng):
    shell(rng, wall_hex="#e8e4da", floor=("tile", "#4a4a4e"), ceiling_hex="#eeeeec")
    # wall of TVs
    for i in range(4):
        box((-1.05 + i * 0.7, H - 0.04, 0.35), (0.62, 0.04, 0.42), mat((0.01, 0.01, 0.014), 0.15))
        box((-1.05 + i * 0.7, H - 0.07, 0.35), (0.58, 0.02, 0.37), mat(srgb(rng.choice(["#3b5f8f", "#8f4a3b", "#4a8f6b", "#8f7a3b"])), 0.2, emit=1.4))
    # display tables
    for x in (-0.7, 0.7):
        on_floor(x, 0.5, 0.9, 0.7, 0.9, mat(srgb("#e8e4da"), 0.4))
        for k in range(3):
            box((x - 0.25 + k * 0.25, 0.5, -H + 0.97), (0.2, 0.14, 0.14), mat(srgb("#222"), 0.4))
    shop_light_strip((0.95, 0.98, 1.0), n=3, strength=1.6)
    point_light(0, 0.2, 1.0, (0.9, 0.95, 1.0), 50)


# Residential + office atlas. Names must stay in this order (the shader indexes rooms).
LIVING = [
    ("living_0", room_living, 11), ("living_1", room_living, 12), ("bedroom_0", room_bedroom, 21),
    ("bedroom_1", room_bedroom, 22), ("kitchen_0", room_kitchen, 31), ("study_0", room_study, 41),
    ("bare_0", room_bare, 51), ("office_0", room_office, 61), ("office_1", room_office, 62),
    ("meeting_0", room_meeting, 71), ("cubicles_0", room_cubicles, 81), ("reception_0", room_reception, 91),
]
SHOPS = [
    ("cafe_0", room_cafe, 101), ("cafe_1", room_cafe, 102), ("boutique_0", room_boutique, 111),
    ("boutique_1", room_boutique, 112), ("grocery_0", room_grocery, 121), ("restaurant_0", room_restaurant, 131),
    ("restaurant_1", room_restaurant, 132), ("bookshop_0", room_bookshop, 141), ("florist_0", room_florist, 151),
    ("hardware_0", room_hardware, 161), ("electronics_0", room_electronics, 171), ("grocery_1", room_grocery, 122),
]

# ------------------------------------------------------------------ render


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.resolution_x = FACE
    sc.render.resolution_y = FACE
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.0
    # Dim ambient so the hidden front wall isn't the only bounce.
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.02, 0.025, 1)
    sc.world = w
    cam = bpy.data.cameras.new("cam")
    cam.angle = math.radians(90)
    cam.clip_start = 0.01
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return sc, co


FACES = {
    "back": (90, 0, 0),
    "left": (90, 0, 90),
    "right": (90, 0, -90),
    "floor": (0, 0, 0),
    "ceiling": (180, 0, 0),
}


def clear_room():
    for o in list(bpy.data.objects):
        if o.type != "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for l in list(bpy.data.lights):
        bpy.data.lights.remove(l)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    _mats.clear()


def render_room(name, fn, seed, sc, cam):
    clear_room()
    rng = random.Random(seed)
    fn(rng)
    cam.location = (0, 0, 0)
    os.makedirs(OUT, exist_ok=True)
    for face, rot in FACES.items():
        cam.rotation_euler = tuple(math.radians(r) for r in rot)
        sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (name, face))
        bpy.ops.render.render(write_still=True)
    print("rendered", name)


def main():
    os.makedirs(OUT, exist_ok=True)
    import json
    with open(os.path.join(OUT, "rooms.json"), "w") as f:
        json.dump({"rooms": [r[0] for r in LIVING], "shops": [r[0] for r in SHOPS]}, f)
    sc, cam = setup_scene()
    for table in (LIVING, SHOPS):
        for name, fn, seed in table:
            if ONLY and name not in ONLY:
                continue
            render_room(name, fn, seed, sc, cam)
    pack = os.path.join(ROOT, "tools", "textures", "pack_building_interiors.py")
    if not ONLY and os.path.exists(pack):
        subprocess.run(["python3", pack], check=False)


main()
