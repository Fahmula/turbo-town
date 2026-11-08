"""Generates the garage body parts (assets/models/kits/<vehicle>_kit.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_kits.py
    blender -b -P tools/blender/make_kits.py -- sports_car sedan   (only these)

One kit per drivable vehicle, with one mesh per part named "<slot>_<id>"
(PartsCatalog.BODY_PARTS; BodyKit fits them). Every part is modelled in its
vehicle's own space (front = Blender +Y, origin at wheel-centre height
between the axles), so the game puts it on with an identity transform.

* Spoilers (every vehicle): a lip and a ducktail that follow the deck's (or
  the roof's) rear edge, a GT wing and a Mega Wing on stands. The stands are
  ray-cast onto the committed body model, so they always reach it.
* Bonnets (sports car, sedan, pickup, monster truck): vents, a scoop, a
  supercharger poking out of the bonnet.
* Roofs: a roof scoop, a rack, a light bar (UV kind AUX: lit at night), a
  roof box.
* Body kits (sports car and sedan only, ART_BIBLE.md §12): Sport and Race
  bumpers built from the vehicle's own BodySpec with a deeper lower edge, so
  they meet the stock shell exactly at the bumper split; a race splitter,
  canards and diffuser fins; side skirts between the arches; bolt-on flares
  and wide-body arches round the wheels (the game pushes the wheels out to
  fill them, PartsCatalog `track`).

Material names are the contract (ART_BIBLE.md §13). Bumpers are thickened
like the stock ones: BodyKit renames them FrontBumper / RearBumper /
Spoiler, so they still fall off in crashes.
"""
import math
import os
import sys

import bmesh
import bpy
import mathutils
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402
import make_car  # noqa: E402
import make_sedan  # noqa: E402

V = mathutils.Vector
MODELS = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models"))

# ------------------------------------------------------------ vehicles ---
# Mounts are in Blender metres. spoiler: the deck (or roof) rear edge `edge`
# with lip half span `lip_hs` (None = no lip/ducktail); the wing over `wing_y`
# on stands at +-`stand_x`, `span` wide, `height` above the deck. bonnet:
# centre `y`, scale `s`. roof: centre `y`, length `len`, half width `hw`,
# front edge `front`.
VEHICLES = {
    "sports_car": {
        "glb": "car_body.glb", "spec": make_car.SPEC,
        "spoiler": {"edge": -2.10, "lip_hs": 0.70, "wing_y": -1.98, "stand_x": 0.52, "span": 1.66, "height": 0.27},
        "bonnet": {"y": 1.18, "s": 1.0},
        "roof": {"y": -0.36, "len": 0.5, "hw": 0.55, "front": -0.08},
    },
    "sedan": {
        "glb": "sedan_body.glb", "spec": make_sedan.SPEC,
        "spoiler": {"edge": -2.20, "lip_hs": 0.72, "wing_y": -1.96, "stand_x": 0.55, "span": 1.66, "height": 0.25},
        "bonnet": {"y": 1.30, "s": 1.0},
        "roof": {"y": -0.48, "len": 0.85, "hw": 0.58, "front": -0.04},
    },
    "van": {
        "glb": "van_body.glb",
        "spoiler": {"edge": -2.42, "lip_hs": 0.86, "wing_y": -2.15, "stand_x": 0.62, "span": 1.9, "height": 0.24},
        "roof": {"y": -0.85, "len": 2.6, "hw": 0.84, "front": 0.55},
    },
    "pickup": {
        "glb": "pickup_body.glb",
        "spoiler": {"edge": None, "lip_hs": None, "wing_y": -2.45, "stand_x": 0.98, "span": 2.08, "height": 0.30},
        "bonnet": {"y": 1.62, "s": 1.15},
        "roof": {"y": -0.08, "len": 0.72, "hw": 0.72, "front": 0.30},
    },
    "box_truck": {
        "glb": "truck_body.glb",
        "spoiler": {"edge": -3.78, "lip_hs": 1.12, "wing_y": -3.35, "stand_x": 0.85, "span": 2.3, "height": 0.28},
        "roof": {"y": 1.95, "len": 1.0, "hw": 1.0, "front": 2.62},
    },
    "bus": {
        "glb": "bus_body.glb",
        "spoiler": {"edge": -4.22, "lip_hs": 1.2, "wing_y": -3.85, "stand_x": 0.9, "span": 2.5, "height": 0.28},
    },
    "buggy": {
        "glb": "buggy_body.glb",
        "spoiler": {"edge": None, "lip_hs": None, "wing_y": -1.72, "stand_x": 0.36, "span": 1.5, "height": 0.30,
                    "floor": 0.62},
    },
    "monster_truck": {
        "glb": "monster_body.glb",
        "spoiler": {"edge": None, "lip_hs": None, "wing_y": -1.95, "stand_x": 0.92, "span": 2.0, "height": 0.36},
        "bonnet": {"y": 1.55, "s": 1.15},
        # No roof parts: it has its own light bar.
    },
}


# ------------------------------------------------------------- the body ---

class Body:
    """The committed body model, imported to place parts on (ray casts).
    The imported data is deleted again so its materials never clash with
    the kit's (Blender would name ours "Paint.001")."""

    def __init__(self, glb, skip=("Stripes", "Spoiler")):
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, glb))
        bm = bmesh.new()
        imported = [o for o in bpy.context.scene.objects]
        for o in imported:
            if o.type != "MESH" or o.name.split(".")[0] in skip:
                continue
            tmp = bmesh.new()
            tmp.from_mesh(o.data)
            tmp.transform(o.matrix_world)
            vmap = {v: bm.verts.new(v.co) for v in tmp.verts}
            for f in tmp.faces:
                try:
                    bm.faces.new([vmap[v] for v in f.verts])
                except ValueError:
                    pass
            tmp.free()
        bm.normal_update()
        self.tree = BVHTree.FromBMesh(bm)
        self.bm = bm
        meshes = [o.data for o in imported if o.type == "MESH"]
        mats = {m for me in meshes for m in me.materials if m}
        for o in imported:
            bpy.data.objects.remove(o, do_unlink=True)
        for me in meshes:
            bpy.data.meshes.remove(me)
        for m in mats:
            bpy.data.materials.remove(m)

    def down(self, x, y, top=8.0):
        """Surface height under (x, y) and its normal (None if it misses)."""
        loc, n, _i, _d = self.tree.ray_cast(V((x, y, top)), V((0, 0, -1)))
        return (loc.z, n) if loc is not None else (None, None)

    def side(self, y, z, sx):
        """The body side's x at (y, z) on side sx (+1 right)."""
        loc, _n, _i, _d = self.tree.ray_cast(V((sx * 4.0, y, z)), V((-sx, 0, 0)))
        return abs(loc.x) if loc is not None else None


# ---------------------------------------------------------------- helpers ---

def closed(part, mat, rings, cap=True, uv=None):
    """A tube through `rings` (each a list of points going round a cross
    section), capped at both ends, normals pointing out."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for i in range(len(vr) - 1):
        for j in range(n):
            j1 = (j + 1) % n
            bm.faces.new([vr[i][j], vr[i][j1], vr[i + 1][j1], vr[i + 1][j]])
    if cap:
        bm.faces.new(vr[0])
        bm.faces.new(vr[-1][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, mat, uv)


def sheet(part, mat, grid, outward, uv=None):
    """An open grid of points (rows x cols) as quads, facing `outward`
    (a vector or a function of the face centre)."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in row] for row in grid]
    for a in range(len(vs) - 1):
        for b in range(len(vs[0]) - 1):
            f = bm.faces.new([vs[a][b], vs[a + 1][b], vs[a + 1][b + 1], vs[a][b + 1]])
            f.normal_update()
            want = outward(f.calc_center_median()) if callable(outward) else V(outward)
            if f.normal.dot(want) < 0:
                f.normal_flip()
    bk._append(part, bm, mat, uv)


def airfoil(part, mat, y0, z0, chord, thick, span, aoa=0.14, pts=8):
    """An extruded wing section: leading edge at (y0, z0), trailing edge
    `chord` behind, nose-down by `aoa` (rad, the back kicks up)."""
    prof = []
    for k in range(pts):
        t = k / (pts - 1)
        half = thick * 0.5 * (math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.7 + 0.12)
        prof.append((t, half))
    loop = [(t, h) for (t, h) in prof] + [(t, -h * 0.55) for (t, h) in reversed(prof)]
    ca, sa = math.cos(aoa), math.sin(aoa)
    ring = []
    for (t, h) in loop:
        # Chord runs back and up (e_t = (-cos, sin)); thickness along its
        # normal (e_n = (sin, cos)).
        ring.append((y0 - t * chord * ca + h * sa, z0 + t * chord * sa + h * ca))
    rings = []
    for x in (-span / 2, span / 2):
        rings.append([(x, y, z) for (y, z) in ring])
    closed(part, mat, rings)


def finish(part, smooth=50):
    return part.to_object(math.radians(smooth))


# --------------------------------------------------------------- spoilers ---

def lip(body, m, sp, big):
    """A kicked-up lip along the rear edge: rises toward the back, follows
    the surface across. `big` = ducktail."""
    part = bk.Part("spoiler_ducktail" if big else "spoiler_lip", [])
    depth = 0.28 if big else 0.09
    rise = 0.11 if big else 0.045
    hs = sp["lip_hs"]
    xs = [hs * (2 * i / 20 - 1) for i in range(21)]
    ts = [k / 6 for k in range(7)]
    top, bot = [], []
    for x in xs:
        end = bk.smoothstep(hs, hs * 0.86, abs(x))
        trow, brow = [], []
        for t in ts:
            y = sp["edge"] + depth * (1 - t)
            z, _n = body.down(x, y)
            if z is None:
                z = body.down(0, y)[0]
            r = rise * end * (t ** 1.6)
            brow.append((x, y, z + 0.002))
            trow.append((x, y - 0.01 * t * end, z + 0.004 + r))
        top.append(trow)
        bot.append(brow)
    bm = bmesh.new()
    T = [[bm.verts.new(p) for p in row] for row in top]
    B = [[bm.verts.new(p) for p in row] for row in bot]
    nx, nt = len(xs), len(ts)
    for i in range(nx - 1):
        for k in range(nt - 1):
            bm.faces.new([T[i][k], T[i + 1][k], T[i + 1][k + 1], T[i][k + 1]])
            bm.faces.new([B[i][k + 1], B[i + 1][k + 1], B[i + 1][k], B[i][k]])
        bm.faces.new([T[i][nt - 1], T[i + 1][nt - 1], B[i + 1][nt - 1], B[i][nt - 1]])   # back face
        bm.faces.new([B[i][0], B[i + 1][0], T[i + 1][0], T[i][0]])                     # front edge
    for i in (0, nx - 1):
        for k in range(nt - 1):
            bm.faces.new([T[i][k], T[i][k + 1], B[i][k + 1], B[i][k]])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Paint"])
    return finish(part, 40)


def wing(body, m, sp, mega):
    """A GT wing (or the twin-element Mega Wing) on two stands."""
    part = bk.Part("spoiler_mega" if mega else "spoiler_wing", [])
    span = sp["span"] + (0.16 if mega else 0.0)
    chord = 0.36 if mega else 0.26
    height = sp["height"] * (1.9 if mega else 1.0)
    y0 = sp["wing_y"] + chord * 0.5
    sx = sp["stand_x"]
    feet = []
    for s in (-1, 1):
        z, _n = body.down(s * sx, sp["wing_y"])
        feet.append(z if z is not None else sp.get("floor", 0.4))
    base = max(feet)
    zw = base + height
    airfoil(part, m["Paint"], y0, zw, chord, 0.04 if mega else 0.032, span)
    if mega:
        # A second, smaller element above and behind (a gurney flap look).
        airfoil(part, m["Paint"], y0 - chord * 0.62, zw + 0.075, chord * 0.5, 0.025, span, aoa=0.42)
    # End plates.
    ph = 0.26 if mega else 0.15
    for s in (-1, 1):
        x = s * (span / 2 + 0.006)
        bk.box(part, m["Paint" if mega else "Trim"], (x, y0 - chord * 0.5, zw + ph * 0.25),
               (0.012, chord * 1.25, ph), bevel=0.004, segments=1)
    # Stands: plates from the deck up to the wing, raked back a little.
    for s, foot in zip((-1, 1), feet):
        x = s * sx
        h = zw - foot + 0.01
        bk.box(part, m["Trim"], (x, sp["wing_y"] - 0.02, foot + h / 2), (0.022, 0.12 if mega else 0.09, h),
               rot=(math.radians(-8), 0, 0))
        bk.box(part, m["Trim"], (x, sp["wing_y"], foot + 0.008), (0.06, 0.16, 0.016))       # foot plate
    return finish(part, 40)


# ---------------------------------------------------------------- bonnet ---

def bonnet_vents(body, m, bn):
    part = bk.Part("bonnet_vents", [])
    s = bn["s"]
    surf = Surf(body)
    for sx in (-1, 1):
        c = (sx * 0.30 * s, bn["y"] + 0.22 * s, 3.0)
        bk.patch(surf, part, m["Trim"], bk.rect(0.20 * s, 0.30 * s, 0.25), c, (0, 0, -1), (0, 1, 0), lift=0.004, grid=(4, 6),
                 kind=bk.GRILLE_SLATS)
    return finish(part)


class Surf(bk.Surface):
    """bk.Surface over an imported Body (shares its BVH)."""

    def __init__(self, body):
        self.bm = body.bm
        self.tree = body.tree


def scoop(body, m, name, y_c, length, width, height, mat="Paint"):
    """A bonnet/roof scoop: open at the front, sloping down to the surface
    at the back, following the surface it sits on."""
    part = bk.Part(name, [])
    nx, ny = 10, 8
    rings = []
    for k in range(ny + 1):
        t = k / ny                               # 0 = front (mouth), 1 = back
        y = y_c + length * (0.5 - t)
        h = height * (1 - t) ** 1.3 + 0.004
        ring = []
        for i in range(nx + 1):
            u = i / nx                           # across, -1 .. 1
            x = width * 0.5 * (2 * u - 1) * (1 - 0.2 * t)
            z, _n = body.down(x, y)
            if z is None:
                z = body.down(0, y)[0]
            prof = math.sin(math.pi * u) ** 0.45  # rounded top
            ring.append((x, y, z + 0.002 + h * prof))
        rings.append(ring)
    sheet(part, m[mat], rings, (0, 0, 1))
    # The dark mouth at the front.
    front = rings[0]
    mouth = [[(p[0] * 0.9, p[1] - 0.003, max(p[2] - 0.006, body.down(p[0], p[1])[0] or p[2]))
              for p in front], [(p[0] * 0.9, p[1] - 0.003, (body.down(p[0], p[1])[0] or p[2]) + 0.006) for p in front]]
    sheet(part, m["Trim"], mouth, (0, 1, 0), uv=bk.tag_uv(bk.GRILLE_MESH))
    return finish(part, 35)


def blower(body, m, bn):
    """A supercharger poking up out of the bonnet: a ribbed case, a drive
    belt at the front and a big air scoop with a dark mouth on top."""
    part = bk.Part("bonnet_blower", [])
    s = bn["s"]
    y = bn["y"]
    z0, _n = body.down(0, y)
    w, l = 0.36 * s, 0.50 * s
    # Base plate where it comes through the bonnet.
    bk.box(part, m["Trim"], (0, y, z0 + 0.012), (w + 0.1, l + 0.08, 0.03), bevel=0.01, segments=1)
    # The case (chrome) with ribs.
    bk.box(part, m["Chrome"], (0, y, z0 + 0.1 * s), (w, l, 0.16 * s), bevel=0.025, segments=2)
    for k in range(5):
        bk.box(part, m["Chrome"], (0, y - l * 0.4 + k * l * 0.2, z0 + 0.1 * s), (w + 0.02, 0.018, 0.13 * s))
    # Drive belt and pulley at the front.
    bk.box(part, m["Trim"], (0, y + l * 0.5 + 0.02, z0 + 0.07 * s), (0.12 * s, 0.03, 0.2 * s), bevel=0.02, segments=1)
    # Air scoop on top (body colour) with a dark mouth.
    top = z0 + 0.18 * s
    bk.box(part, m["Paint"], (0, y + 0.02, top + 0.07 * s), (w * 0.9, l * 0.7, 0.14 * s), bevel=0.03, segments=2)
    bk.box(part, m["Trim"], (0, y + 0.02 + l * 0.35, top + 0.075 * s), (w * 0.75, 0.01, 0.1 * s), kind=bk.GRILLE_MESH)
    # Two butterfly intakes behind the scoop.
    for sx in (-1, 1):
        bk.tube(part, m["Chrome"], (sx * 0.09 * s, y - l * 0.25, top), (sx * 0.09 * s, y - l * 0.25, top + 0.06 * s), 0.05 * s, 12)
        bk.tube(part, m["Trim"], (sx * 0.09 * s, y - l * 0.25, top + 0.06 * s), (sx * 0.09 * s, y - l * 0.25, top + 0.062 * s),
                0.04 * s, 12)
    return finish(part, 35)


# ------------------------------------------------------------------ roof ---

def roof_rack(body, m, rf):
    part = bk.Part("roof_rack", [])
    hw, length, y = rf["hw"], rf["len"], rf["y"]
    x = hw - 0.07
    zs = []
    for sx in (-1, 1):
        for yy in (y + length * 0.42, y - length * 0.42):
            z, _n = body.down(sx * x, yy)
            zs.append(z)
    top = max(z for z in zs if z is not None) + 0.07
    for sx in (-1, 1):
        bk.tube(part, m["Trim"], (sx * x, y + length * 0.5, top), (sx * x, y - length * 0.5, top), 0.016, 8)
        for yy in (y + length * 0.42, y - length * 0.42):
            z = body.down(sx * x, yy)[0]
            bk.box(part, m["Trim"], (sx * x, yy, (z + top) / 2), (0.04, 0.07, top - z + 0.01))
    n = 2 if length < 1.2 else 3
    for k in range(n):
        yy = y + length * 0.4 * (1 - 2 * k / (n - 1))
        bk.box(part, m["Trim"], (0, yy, top + 0.018), (2 * x + 0.06, 0.04, 0.022), bevel=0.006, segments=1)
    return finish(part)


def light_bar(body, m, rf):
    part = bk.Part("roof_lights", [])
    hw, yf = rf["hw"], rf["front"]
    y = yf - 0.1
    w = hw * 1.7
    zl, _n = body.down(-w * 0.4, y)
    zr, _n = body.down(w * 0.4, y)
    zc, _n = body.down(0, y)
    base = max(z for z in (zl, zr, zc) if z is not None)
    top = base + 0.08
    bk.box(part, m["Trim"], (0, y, top), (w, 0.10, 0.09), bevel=0.012, segments=2)
    for sx in (-1, 1):
        for yy in (y,):
            z = body.down(sx * w * 0.38, yy)[0] or base
            bk.box(part, m["Trim"], (sx * w * 0.38, yy, (z + top) / 2), (0.04, 0.06, top - z))
    lamps = 4
    for k in range(lamps):
        x = w * 0.5 * ((2 * k + 1) / lamps - 1) * 0.94
        bk.tube(part, m["Chrome"], (x, y + 0.045, top), (x, y + 0.056, top), 0.038, 14)
        bk.tube(part, m["Headlight"], (x, y + 0.056, top), (x, y + 0.058, top), 0.032, 14, kind=bk.AUX)
    return finish(part)


def roof_box(body, m, rf):
    part = bk.Part("roof_box", [])
    hw, length, y = rf["hw"], rf["len"], rf["y"]
    bl = min(length * 0.85, 1.7)
    bw = min(hw * 1.25, 1.0)
    z, _n = body.down(0, y)
    zs = [body.down(sx * bw * 0.45, yy)[0] for sx in (-1, 1) for yy in (y + bl * 0.4, y - bl * 0.4)]
    base = max([z] + [q for q in zs if q is not None]) + 0.05
    # Rounded pod: a lofted box narrowing to the front.
    rings = []
    for k in range(9):
        t = k / 8
        yy = y + bl * (0.5 - t)
        nose = bk.smoothstep(0.0, 0.25, t) * bk.smoothstep(1.0, 0.85, t)
        hh = 0.27 * (0.45 + 0.55 * nose)
        ww = bw * 0.5 * (0.8 + 0.2 * nose)
        ring = []
        for i in range(16):
            a = 2 * math.pi * i / 16
            ca, sa = math.cos(a), math.sin(a)
            # Superellipse cross-section, flat-ish bottom.
            ex = math.copysign(abs(ca) ** 0.4, ca) * ww
            ez = math.copysign(abs(sa) ** 0.5, sa) * hh * 0.5
            ring.append((ex, yy, base + hh * 0.5 + ez))
        rings.append(ring)
    closed(part, m["Trim"], rings)
    for sx in (-1, 1):
        for yy in (y + bl * 0.3, y - bl * 0.3):
            zz = body.down(sx * bw * 0.35, yy)[0] or base - 0.05
            bk.box(part, m["Trim"], (sx * bw * 0.35, yy, (zz + base) / 2), (0.04, 0.06, base - zz + 0.01))
    return finish(part, 40)


def roof_scoop(body, m, rf):
    return scoop(body, m, "roof_scoop", rf["front"] - 0.2, 0.32, 0.36, 0.06)


# ------------------------------------------------------------ body kits ---

def _kit_spec(spec, front_drop, rear_drop):
    """A copy of `spec` whose bumpers reach `front_drop` / `rear_drop` m
    lower. Rows above the bumper's top edge are untouched, and the drop
    fades in from the bumper split, so the new bumpers meet the stock shell
    exactly."""
    base = bk.LoftBody(spec)
    fy, ry = spec.bumper_split
    row = spec.bumper_row

    def sec(body, y):
        pts = list(bk.LoftBody.section(base, 0, y))
        if y > fy:
            k = bk.smoothstep(fy, fy + 0.2, y) * front_drop
        elif y < ry:
            k = bk.smoothstep(ry, ry - 0.2, y) * rear_drop
        else:
            return pts
        for j in range(row):
            w = 1.0 if j <= 2 else 0.45
            pts[j] = (pts[j][0] * (1.0 + 0.012 * k / max(front_drop, rear_drop, 1e-3) * (j >= 2)), pts[j][1] - k * w)
        return pts

    s2 = bk.BodySpec()
    s2.__dict__.update(spec.__dict__)
    s2.section_override = sec
    return s2


def bumpers(m, spec, variant, sizes):
    """The front and rear bumpers of one kit variant ("sport" or "race")."""
    fd, rd = sizes[variant]
    body = bk.LoftBody(_kit_spec(spec, fd, rd))
    shell, front, rear, _ys = body.build(m, "tmp")
    shell.bm.free()
    front.name = "front_%s" % variant
    rear.name = "rear_%s" % variant
    surf = bk.Surface([front, rear])
    yn, yt = spec.y_nose, spec.y_tail
    zf = spec.floor - fd
    zr = spec.floor - rd
    w_nose = spec.width(spec.nose0)
    # Intakes: a wide lower grille and two corner vents (race: bigger).
    big = variant == "race"
    bk.patch(surf, front, m["Trim"], bk.rect(1.0 if big else 0.9, 0.10 if big else 0.08, 0.5), (0, yn + 0.2, zf + 0.12), (0, -1, 0),
             (0, 0, 1), lift=0.003, kind=bk.GRILLE_MESH)
    for sx in (-1, 1):
        bk.patch(surf, front, m["Trim"], bk.rect(0.20 if big else 0.16, 0.08, 0.4), (sx * (w_nose - 0.22), yn + 0.2, zf + 0.11),
                 (-sx * 0.35, -1, 0), (0, 0, 1), lift=0.003, kind=bk.GRILLE_MESH)
    bk.patch(surf, rear, m["Trim"], bk.rect(1.2 if big else 1.05, 0.11, 0.3), (0, yt - 0.2, zr + 0.09), (0, 1, 0), (0, 0, 1), lift=0.003)
    objs = []
    if big:
        # Splitter: a flat plate under the nose, a little proud of it.
        _splitter(front, m, spec, zf - 0.006)
        for sx in (-1, 1):
            # Canards on the front corners.
            bk.box(front, m["Trim"], (sx * (w_nose - 0.05), yn - 0.17, zf + 0.17), (0.16, 0.12, 0.008),
                   rot=(math.radians(-12), 0, math.radians(sx * 22)))
        # Diffuser fins.
        for k in range(5):
            x = 0.5 * (k / 4 * 2 - 1)
            bk.box(rear, m["Trim"], (x, yt + 0.15, zr + 0.06), (0.014, 0.3, 0.12))
    objs.append(front.to_object(math.radians(60)))
    objs.append(rear.to_object(math.radians(60)))
    return objs


def _splitter(part, m, spec, z):
    body = bk.LoftBody(spec)
    fy = spec.bumper_split[0]
    ys = [fy + (spec.y_nose - fy) * k / 10 for k in range(11)]
    out = []
    for y in ys:
        w = spec.width(min(y, spec.nose0)) * body.wrap(y) + 0.025
        out.append((w, y + 0.03 * (y - fy) / (spec.y_nose - fy)))
    rim = [(x, y) for (x, y) in out] + [(0.0, spec.y_nose + 0.06)]
    pts = [(x, y) for (x, y) in rim] + [(-x, y) for (x, y) in reversed(rim[:-1])]
    bm = bmesh.new()
    top = [bm.verts.new((x, y, z)) for (x, y) in pts]
    bot = [bm.verts.new((x, y, z - 0.012)) for (x, y) in pts]
    n = len(pts)
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    for i in range(n):
        i1 = (i + 1) % n
        bm.faces.new([top[i], bot[i], bot[i1], top[i1]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Trim"])


def skirts(m, spec, variant):
    """Side skirts between the arches, hung under the sills."""
    part = bk.Part("skirts_%s" % variant, [])
    body = bk.LoftBody(spec)
    (fa, fr), (ra, rr) = spec.axles[0], spec.axles[1]
    y0, y1 = fa - fr - 0.02, ra + rr + 0.02
    out, drop = (0.016, 0.022) if variant == "sport" else (0.03, 0.045)
    n = 24
    for sx in (-1, 1):
        rings = []
        for k in range(n + 1):
            y = y0 + (y1 - y0) * k / n
            e = bk.smoothstep(0.0, 0.14, min(y0 - y, y - y1))   # taper at both ends
            pts = body.section(0, y)
            x1, zb = pts[1]
            x3, z3 = pts[3]
            o, d = out * e + 0.002, drop * e + 0.002
            prof = [(x3 - 0.004, z3 - 0.01), (x3 + o, z3 - 0.02), (x3 + o * 0.85, zb - d), (x1 - 0.04, zb - d * 0.6),
                    (x1 - 0.06, zb + 0.004)]
            rings.append([(sx * x, y, z) for (x, z) in prof])
        closed(part, m["Paint"], rings)
        if variant == "race":
            # A black lip along the bottom edge.
            lip_rings = []
            for k in range(n + 1):
                y = y0 + (y1 - y0) * k / n
                e = bk.smoothstep(0.0, 0.14, min(y0 - y, y - y1))
                pts = body.section(0, y)
                x3, z3 = pts[3]
                zb = pts[1][1]
                o, d = out * e + 0.002, drop * e + 0.002
                prof = [(x3 + o * 0.85, zb - d + 0.01), (x3 + o * 0.85 + 0.012, zb - d - 0.004), (x3 - 0.02, zb - d - 0.01),
                        (x3 - 0.03, zb - d + 0.004)]
                lip_rings.append([(sx * x, y, z) for (x, z) in prof])
            closed(part, m["Trim"], lip_rings)
    return finish(part, 40)


def flares(body3d, m, spec, variant):
    """Arches round each wheel, standing out from the body side: bolt-on
    black flares with bolts, or smooth body-colour wide-body arches."""
    part = bk.Part("flares_%s" % variant, [])
    wide = variant == "widebody"
    out = 0.062 if wide else 0.055
    width = 0.15 if wide else 0.085
    mat = m["Paint"] if wide else m["Trim"]
    na = 26
    for (ay, r) in spec.axles:
        for sx in (-1, 1):
            grid = []
            for k in range(na + 1):
                a = -0.18 + (math.pi + 0.36) * k / na    # from the front, over the top, to the back
                e = bk.smoothstep(0.0, 0.22, min(a + 0.18, math.pi + 0.18 - a))
                ca, sa = math.cos(a), math.sin(a)
                row = []
                prof = [(0.0, 0.004), (0.006, out * 0.95), (0.03, out), (width * 0.55, out * 0.75), (width, 0.002)]
                for (dr, dx) in prof:
                    rr_ = r + dr
                    y = ay + rr_ * ca
                    z = rr_ * sa
                    # Sample the side just outside the arch lip (a ray at
                    # the lip itself can slip into the wheel well).
                    q = r + max(dr, 0.012)
                    xb = body3d.side(ay + q * ca, max(q * sa, spec.floor + 0.02), sx) or (spec.width(y) + 0.01)
                    row.append((sx * (xb + dx * e + 0.002), y, z))
                grid.append(row)
            sheet(part, mat, grid, lambda c, sx=sx: V((sx, 0, 0)) + (V((0, c.y - ay, c.z)).normalized() * 0.3))
            if not wide:
                for k in range(2, na - 1, 4):
                    a = -0.18 + (math.pi + 0.36) * k / na
                    rr_ = r + 0.03
                    y, z = ay + rr_ * math.cos(a), rr_ * math.sin(a)
                    xb = body3d.side(y, max(z, spec.floor + 0.02), sx) or spec.width(y)
                    bk.box(part, m["Chrome"], (sx * (xb + out + 0.004), y, z), (0.008, 0.016, 0.016))
    return finish(part, 50)


# ------------------------------------------------------------------- main ---

BUMPER_DROP = {"sports_car": {"sport": (0.035, 0.03), "race": (0.05, 0.055)},
               "sedan": {"sport": (0.03, 0.025), "race": (0.045, 0.045)}}


def build(vid):
    v = VEHICLES[vid]
    bk.reset_scene()
    body = Body(v["glb"])
    m = bk.vehicle_materials()
    objs = []
    sp = v["spoiler"]
    if sp["lip_hs"]:
        objs.append(lip(body, m, sp, False))
        objs.append(lip(body, m, sp, True))
    objs.append(wing(body, m, sp, False))
    objs.append(wing(body, m, sp, True))
    if "bonnet" in v:
        bn = v["bonnet"]
        objs.append(bonnet_vents(body, m, bn))
        objs.append(scoop(body, m, "bonnet_scoop", bn["y"], 0.55 * bn["s"], 0.5 * bn["s"], 0.085 * bn["s"]))
        objs.append(blower(body, m, bn))
    if "roof" in v:
        rf = v["roof"]
        objs.append(light_bar(body, m, rf))
        if vid in ("sports_car", "sedan"):
            objs.append(roof_scoop(body, m, rf))
        if vid in ("sports_car", "sedan", "van", "pickup"):
            objs.append(roof_rack(body, m, rf))
        if vid in ("sedan", "van", "pickup"):
            objs.append(roof_box(body, m, rf))
    if "spec" in v:
        spec = v["spec"]
        for variant in ("sport", "race"):
            objs += bumpers(m, spec, variant, BUMPER_DROP[vid])
            objs.append(skirts(m, spec, variant))
        for variant in ("overfenders", "widebody"):
            objs.append(flares(body, m, spec, variant))
    os.makedirs(os.path.join(bk.OUT_DIR, "kits"), exist_ok=True)
    bk.export(objs, os.path.join("kits", "%s_kit.glb" % vid))
    body.bm.free()


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for vid in (args or list(VEHICLES)):
        build(vid)
