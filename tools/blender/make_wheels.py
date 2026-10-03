"""Generates every vehicle wheel as .glb files in assets/models/.

Run headless from the project root:
    blender -b -P tools/blender/make_wheels.py

All wheels share one base size (outer radius 0.37 m); the vehicle scenes
scale them uniformly to their own radius. Axis is X, +X is the outer face.
Materials: Tire, Rim, Hub (fixed looks, ART_BIBLE.md §13).

Combined wheels (traffic and the stock wheel choice use these as they are):

  wheel.glb          sports car: 19" split five-spoke alloy, low-profile tyre
  wheel_sedan.glb    sedan: 16" six-spoke alloy, taller sidewall
  wheel_steel.glb    van / delivery truck / bus: painted steel, deep dish
  wheel_offroad.glb  pickup / buggy / monster truck: beadlock rim, knobbly tyre
  brake_caliper.glb  a brake caliper for the wheels with discs (sports, sedan);
                     VehicleWheel mounts it on the hub so it steers and follows
                     the suspension but doesn't spin (material Caliper, coloured
                     per vehicle)

Wheel parts (wheel customisation): the same wheels split into a rim and a tyre
that the game combines at runtime. Both live in assets/models/wheels/ and the
combined wheels above are built from exactly these builders, so a stock rim on
its own tyre reproduces the combined wheel.

  Common contract: metres, axis X, +X = outer face, wheel centre at the origin,
  tyre outer radius R = 0.37. One mesh (node "Tyre" / "Rim") with an identity
  node transform (scale is baked into the vertices).

  tyre_<id>.glb   single material Tire, at native size (outer radius 0.37):
                  id      bead radius  width
                  sport   0.243        0.254
                  road    0.222        0.235   (the sedan tyre)
                  heavy   0.205        0.26    (the steel wheel's commercial tyre)
                  offroad 0.21         0.30    (knobs included)
                  allterrain 0.222     0.27    (road sidewall, three staggered
                                               rows of low chevron blocks 18 mm
                                               tall, small shoulder blocks)
                  The tread is at R = 0.37 (knobs may stand a little proud);
                  vehicle_tyre.gdshader tells tread from sidewall by object
                  space radius (tread above ~0.345).

  rim_<id>.glb    everything but the tyre. Two main materials: Rim (what the
                  player recolours: barrel, lip, face, spokes) and Hub (fixed
                  look: brake disc, centre cap, lug nuts, vent-hole darks).
                  A rim may also use Tire as an optional third material for
                  dark see-through fakes (holes, gaps between blades): the game
                  draws any Tire surface with the tyre shader, i.e. dark rubber.
                  Every rim is NORMALISED to the sports rim's fit, bead radius
                  0.243 and width 0.254: the mesh is scaled by (0.254 / native
                  width) along X and (0.243 / native bead) along Y and Z. The
                  game scales it back to the fitted tyre: X by tyre_width /
                  0.254, Y and Z by tyre_bead / 0.243. The barrel sits just
                  inside the tyre bead (the tyre covers the join). Open rims
                  carry the brake disc (x -0.035..-0.012, radius 0.07..0.175)
                  and keep spokes and face clear of the caliper's box (x -0.058
                  ..+0.016, radius 0.118..0.196); closed rims have no disc.
                  Stock rims (same geometry as the combined wheels, built at
                  the matching stock tyre's width and bead radius, then scaled
                  to the standard fit): sport5 (open), six (open), steel
                  (closed), beadlock (closed; its six cut-outs are Tire).
                  New rims (built at the standard fit, no scaling):
                    star5    deep-dish five-spoke star, stepped lip, big cap (open)
                    mesh     ten pairs of crossing thin spokes, lattice (open)
                    turbine  14 curved louvred blades with real gaps (open)
                    ten      thin concave ten-spoke (open)
                    twist    seven spiral spokes (open)
                    dish     flat "pepper pot" disc, six holes in Tire (closed)
                  Open rims show the brake disc; the game mounts the caliper.

Metallic is binary (ART_BIBLE.md §6): discs, hubs and alloy rims are bare
metal (1.0); painted steel and beadlock rims are paint (0.0).
"""
import math
import os
import sys

import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

R = 0.37


def tyre(part, mat, width, rim_r, tread="grooves", segments=32, bulge=0.004):
    """Lathed tyre: bead -> sidewall -> rounded shoulder -> tread -> back."""
    hw = width / 2
    side = R - rim_r
    half = [(-hw + 0.012, rim_r), (-hw - bulge * 0.5, rim_r + side * 0.3), (-hw - bulge, rim_r + side * 0.6),
            (-hw + 0.004, R - 0.016), (-hw + 0.022, R - 0.004), (-hw + 0.045, R)]
    if tread == "grooves":
        mid = [(-0.05, R), (-0.042, R - 0.006), (-0.034, R), (-0.006, R), (0.0, R - 0.006), (0.006, R),
               (0.034, R), (0.042, R - 0.006), (0.05, R)]
    elif tread == "commercial":
        mid = [(-0.04, R), (-0.034, R - 0.007), (-0.028, R), (0.028, R), (0.034, R - 0.007), (0.04, R)]
    else:
        mid = []
    prof = half + mid + [(-x, r) for (x, r) in reversed(half)]
    bk.lathe(part, mat, prof, segments)


def knobs(part, mat, width, count=20):
    """Two staggered rows of tread blocks plus shoulder lugs."""
    for k in range(count):
        a = 2 * math.pi * k / count
        for row, (x, wx) in enumerate(((-width * 0.22, width * 0.34), (width * 0.22, width * 0.34))):
            aa = a + (math.pi / count if row else 0.0)
            c = mathutils.Vector((x, math.cos(aa) * (R + 0.012), math.sin(aa) * (R + 0.012)))
            bk.box(part, mat, c, (wx, 0.07, 0.03), rot=(aa - math.pi / 2, 0, 0))
        # Shoulder lug wrapping onto the sidewall, alternating sides.
        sx = 1 if k % 2 else -1
        c = mathutils.Vector((sx * width * 0.5, math.cos(a) * (R - 0.012), math.sin(a) * (R - 0.012)))
        bk.box(part, mat, c, (0.03, 0.055, 0.045), rot=(a - math.pi / 2, 0, 0))


def lugs(part, mat, n, r, x, nut=0.009):
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        c = (x, math.cos(a) * r, math.sin(a) * r)
        bk.tube(part, mat, (c[0] - 0.012, c[1], c[2]), (c[0] + 0.005, c[1], c[2]), nut, 6)


def brake_disc(part, mat, r_out):
    bk.lathe(part, mat, [(-0.035, 0.07), (-0.035, r_out), (-0.012, r_out), (-0.012, 0.07)], 28, loop=True)


def _outward(bm, centre):
    """Flips every face of `bm` that points toward `centre` (for convex-ish
    pieces such as one tread block)."""
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - centre) < 0:
            f.normal_flip()


def tread_block(part, mat, a, x, r0, r1, width, length, taper=0.004, skew=0.0):
    """One tapered tread block at angle `a` and axial position `x`: an open
    frustum (no bottom face, it is buried in the tyre) from radius r0 up to r1.
    `skew` turns it about the radial axis (chevron tread)."""
    import bmesh
    ex = mathutils.Vector((1, 0, 0))
    er = mathutils.Vector((0, math.cos(a), math.sin(a)))
    et = mathutils.Vector((0, -math.sin(a), math.cos(a)))
    ca, sa = math.cos(skew), math.sin(skew)
    ax, tg = ex * ca + et * sa, et * ca - ex * sa
    bm = bmesh.new()
    rings = []
    for r, w, l in ((r0, width, length), (r1, width - 2 * taper, length - 2 * taper)):
        c = ex * x + er * r
        rings.append([bm.verts.new(c + ax * (sx * w / 2) + tg * (st * l / 2))
                      for (sx, st) in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    lo, hi = rings
    bm.faces.new(hi)
    for j in range(4):
        j1 = (j + 1) % 4
        bm.faces.new([lo[j], lo[j1], hi[j1], hi[j]])
    _outward(bm, ex * x + er * (r0 - 0.01))
    bk._append(part, bm, mat)


def beam(part, mat, stations, chamfer=0.0):
    """A swept bar (spokes, blades): a rounded-off rectangular section carried
    along a path in the wheel's face. Each station is (x, r, angle, half_width,
    depth[, tilt]): x is the FRONT face, the bar is `depth` thick behind it and
    its width runs across the path in the face plane. `tilt` turns the section
    about the path (louvred blades). `chamfer` bevels the two front edges."""
    import bmesh
    n = len(stations)
    pts = [mathutils.Vector((st[0], st[1] * math.cos(st[2]), st[1] * math.sin(st[2]))) for st in stations]
    ex = mathutils.Vector((1, 0, 0))
    bm = bmesh.new()
    rings = []
    for i, st in enumerate(stations):
        hw, d = st[3], st[4]
        tilt = st[5] if len(st) > 5 else 0.0
        path_dir = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        w = ex.cross(path_dir).normalized()          # across the bar, in the face plane
        nrm = path_dir.cross(w)                      # toward +X (the visible side)
        c = chamfer
        if c > 0:
            sec = [(hw - c, 0.0), (hw, -c), (hw, -d), (-hw, -d), (-hw, -c), (-hw + c, 0.0)]
        else:
            sec = [(hw, 0.0), (hw, -d), (-hw, -d), (-hw, 0.0)]
        ct, stt = math.cos(tilt), math.sin(tilt)
        ring = []
        for (u, v) in sec:
            vc = v + d / 2                            # turn about the section's middle
            u2, v2 = u * ct - vc * stt, u * stt + vc * ct - d / 2
            ring.append(bm.verts.new(pts[i] + w * u2 + nrm * v2))
        rings.append(ring)
    m = len(rings[0])
    for i in range(n - 1):
        for j in range(m):
            j1 = (j + 1) % m
            bm.faces.new([rings[i][j], rings[i][j1], rings[i + 1][j1], rings[i + 1][j]])
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, mat)


def plug(part, mat, x0, x1, y, z, radius, segments=12):
    """A short round pad on the wheel face (vent / lightening hole): a cylinder
    along X from x0 to x1 at (y, z), without the buried bottom face."""
    import bmesh
    bm = bmesh.new()
    lo, hi = [], []
    for k in range(segments):
        t = 2 * math.pi * k / segments
        yy, zz = y + radius * math.cos(t), z + radius * math.sin(t)
        lo.append(bm.verts.new((x0, yy, zz)))
        hi.append(bm.verts.new((x1, yy, zz)))
    for k in range(segments):
        k1 = (k + 1) % segments
        bm.faces.new([lo[k], lo[k1], hi[k1], hi[k]])
    bm.faces.new(hi)
    bm.faces.new(lo)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.remove(next(f for f in bm.faces if f.normal.x < -0.9))
    bk._append(part, bm, mat)


# Back half shared by the new rims' barrels: runs inside the tyre bead at the
# back. The barrel's inner surface is at radius 0.2185 (the caliper needs 0.21).
BARREL_BACK = [(-0.07, 0.2185), (-0.112, 0.243)]


def barrel(part, mat, front, segments=28):
    """Rim barrel as one lathe: `front` runs from the bead under the tyre,
    over the lip and in to the barrel's inner surface; the shared back half
    follows."""
    bk.lathe(part, mat, front + BARREL_BACK, segments)


# ------------------------------------------------------ materials and parts ---

SMOOTH = math.radians(42)           # smooth-by-angle for every wheel part
STD_W, STD_BEAD = 0.254, 0.243      # the normalised rim fit (the sports rim's size)
PARTS_DIR = "wheels"                # under assets/models/


def mats_sport():
    """(Tire, Rim, Hub) of the sports wheel: bright alloy, #5A5C5E disc."""
    return (bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9),
            bk.material("Rim", (0.72, 0.73, 0.75), rough=0.32, metal=1.0),
            bk.material("Hub", (0.353, 0.361, 0.369), rough=0.45, metal=1.0))


def mats_sedan():
    return (bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9),
            bk.material("Rim", (0.70, 0.71, 0.73), rough=0.38, metal=1.0),
            bk.material("Hub", (0.353, 0.361, 0.369), rough=0.45, metal=1.0))


def mats_steel():
    return (bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9),
            bk.material("Rim", (0.78, 0.78, 0.76), rough=0.5, metal=0.0),
            bk.material("Hub", (0.12, 0.12, 0.13), rough=0.6, metal=0.0))      # black paint, dark vent holes


def mats_offroad():
    return (bk.material("Tire", (0.095, 0.095, 0.1), rough=0.95),
            bk.material("Rim", (0.2, 0.21, 0.22), rough=0.4, metal=1.0),       # gunmetal
            bk.material("Hub", (0.72, 0.73, 0.75), rough=0.3, metal=1.0))


def mats_allterrain():
    return (bk.material("Tire", (0.10, 0.10, 0.105), rough=0.93),
            bk.material("Rim", (0.7, 0.7, 0.7), rough=0.4, metal=1.0),
            bk.material("Hub", (0.353, 0.361, 0.369), rough=0.45, metal=1.0))


def _alloy(color, rough, metal=1.0):
    """Materials of a new rim: the Tire slot is only for dark fakes and the
    Hub is the standard #5A5C5E bare metal."""
    def mats():
        return (bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9),
                bk.material("Rim", color, rough=rough, metal=metal),
                bk.material("Hub", (0.353, 0.361, 0.369), rough=0.45, metal=1.0))
    return mats


mats_star5 = _alloy((0.72, 0.73, 0.75), 0.34)
mats_mesh = _alloy((0.70, 0.71, 0.73), 0.36)
mats_turbine = _alloy((0.82, 0.83, 0.85), 0.30)           # light silver
mats_ten = _alloy((0.74, 0.745, 0.76), 0.32)
mats_twist = _alloy((0.71, 0.72, 0.74), 0.35)
mats_dish = _alloy((0.90, 0.91, 0.92), 0.38)              # white-ish silver


# Tyres: tyre_<id>(part, tire_m) adds the tyre at its native size.

def tyre_sport(part, tire_m):
    tyre(part, tire_m, 0.254, 0.243, "grooves")


def tyre_road(part, tire_m):
    tyre(part, tire_m, 0.235, 0.222, "grooves", bulge=0.008)


def tyre_heavy(part, tire_m):
    tyre(part, tire_m, 0.26, 0.205, "commercial", bulge=0.01)


def tyre_offroad(part, tire_m):
    tyre(part, tire_m, 0.30, 0.21, "plain", segments=28, bulge=0.012)
    knobs(part, tire_m, 0.30, 18)


def tyre_allterrain(part, tire_m):
    """Between road and off-road: the road tyre's sidewall, a tread of three
    staggered rows of low chevron blocks (18 mm tall, 13 mm proud of the
    tread surface) and small shoulder blocks."""
    width, rim_r, count = 0.27, 0.222, 24
    hw, side = width / 2, R - rim_r
    half = [(-hw + 0.012, rim_r), (-hw - 0.004, rim_r + side * 0.3), (-hw - 0.008, rim_r + side * 0.6),
            (-hw + 0.006, R - 0.014), (-hw + 0.04, R)]
    bk.lathe(part, tire_m, half + [(-x, r) for (x, r) in reversed(half)], count)
    pitch = 2 * math.pi / count
    r0, r1 = R - 0.005, R + 0.013
    for k in range(count):
        a = pitch * k
        tread_block(part, tire_m, a, -0.056, r0, r1, 0.040, 0.058, skew=0.28)
        tread_block(part, tire_m, a + pitch / 3, 0.0, r0, r1, 0.048, 0.058)
        tread_block(part, tire_m, a + 2 * pitch / 3, 0.056, r0, r1, 0.040, 0.058, skew=-0.28)
    for k in range(12):
        sx = 1 if k % 2 else -1
        tread_block(part, tire_m, 2 * math.pi * (k + 0.5) / 12, sx * 0.107, R - 0.03, R + 0.004, 0.03, 0.04, taper=0.003)


# Rims: rim_<id>(part, rim_m, hub_m, dark_m) adds the rim at its native size (the
# stock rims' native size is their tyre's width and bead radius). `dark_m` is
# the Tire material, for dark see-through fakes (holes, gaps): the game draws
# any Tire surface with the tyre shader, which is dark rubber.

def rim_sport5(part, rim_m, hub_m, dark_m=None):
    """19-inch five split-spoke alloy (the approved sports car wheel). Open."""
    bk.lathe(part, rim_m, [(0.112, 0.243), (0.122, 0.248), (0.126, 0.24), (0.118, 0.232), (0.102, 0.226),
                           (0.04, 0.222), (-0.06, 0.222), (-0.104, 0.232), (-0.112, 0.243)], 32)
    brake_disc(part, hub_m, 0.175)
    bk.lathe(part, rim_m, [(0.06, 0.0), (0.06, 0.07), (0.088, 0.078), (0.098, 0.06), (0.104, 0.03), (0.105, 0.0)], 20)
    for k in range(5):
        base = 2 * math.pi * k / 5
        for side in (-1, 1):
            bk.spoke(part, rim_m, (0.097, 0.068, base + side * 0.09, 0.016),
                     (0.116, 0.225, base + side * 0.2, 0.013), 0.024)
    lugs(part, hub_m, 5, 0.042, 0.104)


def rim_six(part, rim_m, hub_m, dark_m=None):
    """16-inch six-spoke alloy with rounded spokes: a sensible family-car
    wheel. Open."""
    rim_r = 0.222
    bk.lathe(part, rim_m, [(0.102, rim_r), (0.11, rim_r + 0.005), (0.114, rim_r - 0.004), (0.104, rim_r - 0.014),
                           (0.085, rim_r - 0.02), (-0.06, rim_r - 0.022), (-0.1, rim_r - 0.012), (-0.104, rim_r)], 28)
    brake_disc(part, hub_m, 0.155)
    bk.lathe(part, rim_m, [(0.05, 0.0), (0.05, 0.065), (0.08, 0.072), (0.09, 0.05), (0.096, 0.0)], 18)
    for k in range(6):
        a = 2 * math.pi * k / 6
        bk.spoke(part, rim_m, (0.088, 0.06, a, 0.026), (0.104, rim_r - 0.012, a, 0.02), 0.022)
    lugs(part, hub_m, 5, 0.038, 0.094)


def rim_steel(part, rim_m, hub_m, dark_m=None):
    """Painted steel wheel with a deep dish, round vent holes and a hub dome.
    Closed (no disc)."""
    rim_r = 0.205
    # Rim barrel and the dished face plate in one profile.
    bk.lathe(part, rim_m, [(0.115, rim_r), (0.124, rim_r + 0.004), (0.126, rim_r - 0.006), (0.112, rim_r - 0.014),
                           (0.07, rim_r - 0.03), (0.06, 0.15), (0.062, 0.1), (0.075, 0.075), (0.078, 0.0)], 24)
    bk.lathe(part, rim_m, [(0.07, rim_r - 0.03), (-0.1, rim_r - 0.03), (-0.115, rim_r)], 24)
    # Vent holes: dark discs set into the face.
    for k in range(8):
        a = 2 * math.pi * k / 8
        c = (0.0635, math.cos(a) * 0.128, math.sin(a) * 0.128)
        bk.tube(part, hub_m, (c[0] - 0.002, c[1], c[2]), (c[0] + 0.0015, c[1], c[2]), 0.024, 8)
    bk.lathe(part, hub_m, [(0.078, 0.0), (0.078, 0.045), (0.096, 0.04), (0.104, 0.02), (0.106, 0.0)], 14)
    lugs(part, rim_m, 8, 0.06, 0.084, nut=0.008)


def rim_beadlock(part, rim_m, hub_m, dark_m):
    """Beadlock off-road wheel: dark rim, bolted ring, six cut-outs drawn in
    the Tire material (dark rubber, so they read as holes). Closed."""
    rim_r = 0.21
    bk.lathe(part, rim_m, [(0.128, rim_r), (0.12, rim_r - 0.01), (0.08, rim_r - 0.016), (0.07, 0.14),
                           (0.07, 0.09), (0.085, 0.06), (0.09, 0.0)], 24)
    bk.lathe(part, rim_m, [(0.08, rim_r - 0.016), (-0.12, rim_r - 0.016), (-0.13, rim_r)], 24)
    # Beadlock ring with its bolts.
    bk.lathe(part, hub_m, [(0.13, rim_r - 0.022), (0.142, rim_r - 0.018), (0.142, rim_r + 0.012), (0.13, rim_r + 0.016)], 28, loop=True)
    lugs(part, rim_m, 12, rim_r - 0.003, 0.146, nut=0.007)
    # Six round cut-outs in the face.
    for k in range(6):
        a = 2 * math.pi * k / 6
        c = (0.0705, math.cos(a) * 0.115, math.sin(a) * 0.115)
        bk.tube(part, dark_m, (c[0] - 0.002, c[1], c[2]), (c[0] + 0.0015, c[1], c[2]), 0.03, 8)
    lugs(part, hub_m, 6, 0.045, 0.094, nut=0.01)


def rim_star5(part, rim_m, hub_m, dark_m=None):
    """Classic deep-dish five-spoke star: wide flat stepped lip, five fat
    tapered spokes set back 3.7 cm from the lip, a big centre cap. Open."""
    barrel(part, rim_m, [(0.110, 0.243), (0.119, 0.2478), (0.1265, 0.2478), (0.1265, 0.2315),
                         (0.1195, 0.2315), (0.1195, 0.2185)])
    brake_disc(part, hub_m, 0.175)
    for k in range(5):
        a = math.pi / 2 + 2 * math.pi * k / 5
        beam(part, rim_m, [(0.094, 0.05, a, 0.040, 0.038), (0.093, 0.10, a, 0.036, 0.038),
                           (0.091, 0.16, a, 0.030, 0.036), (0.089, 0.224, a, 0.025, 0.034)], chamfer=0.009)
    bk.lathe(part, hub_m, [(0.058, 0.0), (0.058, 0.082), (0.098, 0.088), (0.112, 0.074), (0.1175, 0.045), (0.119, 0.0)], 24)


def rim_mesh(part, rim_m, hub_m, dark_m=None):
    """Cross-spoke mesh (90s motorsport): ten pairs of thin spokes crossing
    into a lattice, a rolled rim edge and a raised centre. Open."""
    barrel(part, rim_m, [(0.110, 0.243), (0.121, 0.2490), (0.1265, 0.2455), (0.1235, 0.2315),
                         (0.1155, 0.2235), (0.098, 0.2185)])
    brake_disc(part, hub_m, 0.175)
    n, half_sweep = 10, math.pi / 10 * 0.95
    for k in range(n):
        a = math.pi / 2 + 2 * math.pi * k / n
        for side, dx in ((1, 0.0), (-1, -0.005)):
            beam(part, rim_m, [(0.101 + dx, 0.09, a - side * half_sweep, 0.0095, 0.018),
                               (0.096 + dx, 0.225, a + side * half_sweep, 0.011, 0.018)])
    bk.lathe(part, rim_m, [(0.066, 0.0), (0.066, 0.094), (0.098, 0.098), (0.113, 0.086), (0.118, 0.05), (0.119, 0.0)], 24)
    lugs(part, hub_m, 5, 0.052, 0.116)


def rim_turbine(part, rim_m, hub_m, dark_m=None):
    """Aero turbine: a near-flat disc of 14 curved, louvred blades between a
    centre hub and the lip, with real gaps between them (the brake disc shows
    through). Open."""
    barrel(part, rim_m, [(0.110, 0.243), (0.119, 0.2475), (0.1245, 0.2425), (0.1185, 0.2300), (0.1060, 0.2185)])
    brake_disc(part, hub_m, 0.175)
    n, tilt, thick = 14, 0.7, 0.010
    for k in range(n):
        a0 = 2 * math.pi * k / n
        st = []
        for s in (0.0, 1 / 3, 2 / 3, 1.0):
            r = 0.085 + 0.14 * s
            pitch = 2 * math.pi * r / n
            hw = (0.62 * pitch - thick * math.sin(tilt)) / (2 * math.cos(tilt))
            st.append((0.100 - 0.004 * s, r, a0 + 0.62 * s ** 1.15, hw, thick, tilt))
        beam(part, rim_m, st)
    bk.lathe(part, rim_m, [(0.078, 0.0), (0.078, 0.092), (0.094, 0.096), (0.104, 0.082), (0.1055, 0.0)], 24)
    bk.lathe(part, hub_m, [(0.098, 0.0), (0.098, 0.046), (0.112, 0.038), (0.1165, 0.0)], 16)


def rim_ten(part, rim_m, hub_m, dark_m=None):
    """Modern thin ten-spoke: straight spokes that dip toward the centre
    (a shallow concave face), small centre cap. Open."""
    barrel(part, rim_m, [(0.110, 0.243), (0.1195, 0.2478), (0.1255, 0.2430), (0.1215, 0.2300),
                         (0.1100, 0.2210), (0.098, 0.2185)])
    brake_disc(part, hub_m, 0.175)
    for k in range(10):
        a = math.pi / 2 + 2 * math.pi * k / 10
        st = []
        for s, hw in ((0.0, 0.0145), (0.5, 0.0115), (1.0, 0.0185)):
            st.append((0.080 + 0.028 * s ** 1.6, 0.06 + 0.164 * s, a, hw, 0.022))
        beam(part, rim_m, st, chamfer=0.003)
    bk.lathe(part, rim_m, [(0.062, 0.0), (0.062, 0.072), (0.082, 0.078), (0.092, 0.062), (0.0955, 0.0)], 24)
    bk.lathe(part, hub_m, [(0.088, 0.0), (0.088, 0.038), (0.099, 0.031), (0.1025, 0.0)], 16)


def rim_twist(part, rim_m, hub_m, dark_m=None):
    """Directional "twister": seven spokes curving in a spiral from hub to
    lip. Open."""
    barrel(part, rim_m, [(0.110, 0.243), (0.1195, 0.2478), (0.1260, 0.2430), (0.1190, 0.2310),
                         (0.1050, 0.2230), (0.098, 0.2185)])
    brake_disc(part, hub_m, 0.175)
    n = 7
    for k in range(n):
        a0 = math.pi / 2 + 2 * math.pi * k / n
        st = []
        for s in (0.0, 0.25, 0.5, 0.75, 1.0):
            st.append((0.098 + 0.010 * s, 0.06 + 0.164 * s, a0 + 0.8 * s ** 1.3, 0.018 + 0.010 * s, 0.024))
        beam(part, rim_m, st, chamfer=0.004)
    bk.lathe(part, rim_m, [(0.062, 0.0), (0.062, 0.075), (0.086, 0.080), (0.098, 0.064), (0.103, 0.032), (0.104, 0.0)], 24)
    lugs(part, hub_m, 5, 0.040, 0.103)


def rim_dish(part, rim_m, hub_m, dark_m):
    """Retro flat disc ("pepper pot"): a flat face with six big flanged round
    holes (dark Tire-material discs) and a domed centre. Closed."""
    barrel(part, rim_m, [(0.110, 0.243), (0.119, 0.2478), (0.1260, 0.2455), (0.1235, 0.2300), (0.1100, 0.2215)])
    bk.lathe(part, rim_m, [(0.088, 0.222), (0.088, 0.105), (0.100, 0.092), (0.112, 0.070), (0.1175, 0.04), (0.119, 0.0)], 28)
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        y, z = math.cos(a) * 0.15, math.sin(a) * 0.15
        plug(part, rim_m, 0.086, 0.0935, y, z, 0.050, 12)
        plug(part, dark_m, 0.092, 0.095, y, z, 0.039, 16)
    lugs(part, hub_m, 5, 0.045, 0.1165)


# id -> (builder, native width, native bead radius, materials[, uses Tire])
TYRES = {
    "sport": (tyre_sport, 0.254, 0.243, mats_sport),
    "road": (tyre_road, 0.235, 0.222, mats_sedan),
    "heavy": (tyre_heavy, 0.26, 0.205, mats_steel),
    "offroad": (tyre_offroad, 0.30, 0.21, mats_offroad),
    "allterrain": (tyre_allterrain, 0.27, 0.222, mats_allterrain),
}
RIMS = {
    "sport5": (rim_sport5, 0.254, 0.243, mats_sport),
    "six": (rim_six, 0.235, 0.222, mats_sedan),
    "steel": (rim_steel, 0.26, 0.205, mats_steel),
    "beadlock": (rim_beadlock, 0.30, 0.21, mats_offroad, True),
    # New designs are built at the normalised fit, so they need no scaling.
    "star5": (rim_star5, STD_W, STD_BEAD, mats_star5),
    "mesh": (rim_mesh, STD_W, STD_BEAD, mats_mesh),
    "turbine": (rim_turbine, STD_W, STD_BEAD, mats_turbine),
    "ten": (rim_ten, STD_W, STD_BEAD, mats_ten),
    "twist": (rim_twist, STD_W, STD_BEAD, mats_twist),
    "dish": (rim_dish, STD_W, STD_BEAD, mats_dish, True),
}


def new_part(name, *mats):
    """A Part with its material slots in a fixed order."""
    part = bk.Part(name, [])
    for m in mats:
        part.slot(m)
    return part


def build_combined(filename, tyre_fn, rim_fn, mats):
    """A whole wheel (tyre + rim) as one mesh, for traffic and stock wheels."""
    bk.reset_scene()
    tire_m, rim_m, hub_m = mats()
    part = new_part("Wheel", tire_m, rim_m, hub_m)
    tyre_fn(part, tire_m)
    rim_fn(part, rim_m, hub_m, tire_m)
    bk.export([part.to_object(SMOOTH)], filename)


def export_tyre(tyre_id):
    fn, _w, _bead, mats = TYRES[tyre_id][:4]
    bk.reset_scene()
    tire_m = mats()[0]
    part = new_part("Tyre", tire_m)
    fn(part, tire_m)
    bk.export([part.to_object(SMOOTH)], "%s/tyre_%s.glb" % (PARTS_DIR, tyre_id))


def export_rim(rim_id):
    """Builds the rim at its native size, then bakes the scale to the standard
    fit (bead 0.243, width 0.254) into the vertices. Slots: Rim, Hub and, for
    rims with dark see-through fakes, Tire."""
    entry = RIMS[rim_id]
    fn, width, bead, mats = entry[:4]
    bk.reset_scene()
    tire_m, rim_m, hub_m = mats()
    part = new_part("Rim", rim_m, hub_m, *([tire_m] if len(entry) > 4 else []))
    fn(part, rim_m, hub_m, tire_m)
    obj = part.to_object(SMOOTH)
    sx, sr = STD_W / width, STD_BEAD / bead
    obj.data.transform(mathutils.Matrix.Diagonal((sx, sr, sr, 1.0)))
    obj.data.update()
    bk.export([obj], "%s/rim_%s.glb" % (PARTS_DIR, rim_id))


def build_sports():
    """Sports car: split five-spoke alloy, low-profile tyre."""
    build_combined("wheel.glb", tyre_sport, rim_sport5, mats_sport)


def build_sedan():
    """Sedan: six-spoke alloy, taller sidewall."""
    build_combined("wheel_sedan.glb", tyre_road, rim_six, mats_sedan)


def build_steel():
    """Van, trucks and bus: painted steel, deep dish."""
    build_combined("wheel_steel.glb", tyre_heavy, rim_steel, mats_steel)


def build_offroad():
    """Pickup, buggy, monster truck: beadlock rim, chunky knobbly tyre."""
    build_combined("wheel_offroad.glb", tyre_offroad, rim_beadlock, mats_offroad)


def build_caliper():
    """A two-piston caliper at the top of the disc (+Z, Blender), straddling
    its outer edge, biased toward the outer face so it shows between the
    spokes. Sized for the sports wheel's 0.175 m disc; the scene scales it
    with the wheel."""
    bk.reset_scene()
    mat = bk.material("Caliper", (0.75, 0.1, 0.07), rough=0.35)
    part = bk.Part("Caliper", [])
    import bmesh
    bm = bmesh.new()
    x0, x1 = -0.058, 0.016          # disc runs x -0.035..-0.012
    r0, r1 = 0.118, 0.196
    half = math.radians(27)
    n = 8
    rings = []
    for k in range(n + 1):
        a = math.pi / 2 - half + 2 * half * k / n
        ca, sa = math.cos(a), math.sin(a)
        # Rounded ends: the block tapers a little toward both ends.
        taper = 1.0 - 0.18 * abs(2 * k / n - 1) ** 3
        ra, rb = r0 + (1 - taper) * 0.03, r1 - (1 - taper) * 0.01
        rings.append([bm.verts.new((x, r * ca, r * sa)) for (x, r) in ((x0, ra), (x1, ra), (x1, rb), (x0, rb))])
    for k in range(n):
        a, b = rings[k], rings[k + 1]
        for j in range(4):
            j1 = (j + 1) % 4
            bm.faces.new([a[j], b[j], b[j1], a[j1]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.006, segments=1, affect="EDGES", profile=0.5)
    bk._append(part, bm, mat)
    bk.export([part.to_object(math.radians(40))], "brake_caliper.glb")


if __name__ == "__main__":
    os.makedirs(os.path.abspath(os.path.join(bk.OUT_DIR, PARTS_DIR)), exist_ok=True)
    build_caliper()
    build_sports()
    build_sedan()
    build_steel()
    build_offroad()
    for tyre_id in TYRES:
        export_tyre(tyre_id)
    for rim_id in RIMS:
        export_rim(rim_id)
