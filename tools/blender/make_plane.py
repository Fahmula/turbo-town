"""Generates the sport plane (plane_body.glb) and its wheel (plane_wheel.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_plane.py

Design language (ART_BIBLE.md §12): a generic, unbranded two-seat aerobatic
sport plane. A low, slightly tapered wing with dihedral; a side-by-side
cockpit under a big bubble canopy; a cowled flat-four with a two-blade
propeller and spinner; tricycle gear in wheel fairings; a swept fin with a
dorsal strake. Real proportions (8.1 m span, 6.35 m long, 2.25 m tall). The
fuselage is a body_kit loft, so its panels are evenly meshed for dents like
the cars'.

Conventions (Blender Z-up, front = +Y = Godot -Z, right = +X):
  * Origin on the centre line at the centre of gravity (y = 0, about the
    wing's quarter chord), z = 0 at the main wheels' centre height; the
    ground is z = -MAIN_R. scenes/vehicles/plane.tscn puts the wheels at
    (+-MAIN_X, MAIN_Y) and (0, NOSE_Y), radii MAIN_R and NOSE_R.
  * Objects (their node names are a code contract, see aircraft.gd):
      PlaneBody   fuselage, tail, gear, cockpit (deformable)
      WingL/R     the wings (deformable, apart so a dent only touches one)
      Propeller   spinner and blades; origin on the thrust line, spins about
                  its local Y (Godot local Z)
      PropDisc    the blur disc shown when the propeller turns fast
                  (material PropBlur)
      AileronL/R, FlapL/R, Elevator: local X = the hinge line (pointing
                  right), origin on the hinge; + rotation = trailing edge down
      Rudder      local Z (Godot Y) = the hinge line, pointing up;
                  + rotation = trailing edge to the right
      Stripes     the livery (material Stripe): a cheat line down each side,
                  a band on the fin and stripes near the wing tips
  * Materials: the vehicle set (Paint, Glass, Trim, Chrome, Headlight = the
    landing light, Interior), plus NavLight (wing tip, tail and beacon
    lights; UV kind NAV_RED / NAV_GREEN / NAV_STROBE / NAV_BEACON, decoded by
    nav_light.gdshader), PropTip (yellow blade tips) and PropBlur.
"""
import math
import os
import sys

import bmesh
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402
import make_wheels as mw  # noqa: E402

V = mathutils.Vector

# ----------------------------------------------------------------- layout ---
MAIN_R = 0.20                 # main wheel radius
NOSE_R = 0.17                 # nose wheel radius
MAIN_X, MAIN_Y = 1.02, -0.32  # main wheels (x = +-MAIN_X)
NOSE_Y = 1.78
NOSE_Z = -MAIN_R + NOSE_R     # nose wheel centre height (same ground)
THRUST_Z = 0.91               # propeller axis height
PROP_Y = 2.47                 # propeller plane
PROP_R = 0.90                 # propeller radius

# Fuselage: plan and side curves by station y (nose +, tail -).
CANOPY_FRONT, CANOPY_BACK = 1.05, -1.22
WS_BOW = (0.57, 0.51)         # frame between the windscreen and the canopy
COWL_SEAM = (1.567, 1.555)    # cowling shut line
TAIL_Y = -3.55
NOSE_FRONT = 2.44

HW = bk.curve([(2.44, 0.33), (2.30, 0.405), (2.05, 0.475), (1.70, 0.525), (1.20, 0.56), (0.40, 0.572),
               (-0.40, 0.566), (-1.20, 0.525), (-2.00, 0.395), (-2.80, 0.215), (-3.30, 0.10), (-3.55, 0.035)])
ZB = bk.curve([(2.44, 0.635), (2.30, 0.55), (2.05, 0.465), (1.60, 0.415), (0.80, 0.385), (-0.60, 0.39),
               (-1.30, 0.45), (-2.00, 0.60), (-2.80, 0.80), (-3.55, 0.945)])
ZR = bk.curve([(2.44, 1.00), (1.60, 1.09), (1.05, 1.125), (0.0, 1.12), (-1.22, 1.10), (-2.00, 1.065),
               (-2.80, 1.025), (-3.55, 0.99)])
ZT = bk.curve([(2.44, 1.175), (2.20, 1.235), (1.80, 1.265), (1.30, 1.285), (1.05, 1.30), (0.80, 1.425),
               (0.50, 1.525), (0.15, 1.585), (-0.20, 1.592), (-0.55, 1.562), (-0.90, 1.455), (-1.22, 1.30),
               (-1.50, 1.215), (-2.00, 1.16), (-2.80, 1.085), (-3.55, 1.00)])
P_LOW, P_UP = 2.7, 2.45       # superellipse exponents below / above the widest point

# Wing: straight tapered panels from the root (inside the fuselage) to the tip.
WING_ROOT, WING_TIP = 0.45, 3.92
WING_END = 4.06               # the rounded tip fairing ends here
DIHEDRAL = math.radians(4.0)
INCIDENCE = math.radians(1.0)
FLAP = (0.60, 1.95)           # span of the flaps (x)
AILERON = (2.00, 3.84)        # span of the ailerons (x)
HINGE_S = 0.755               # control surfaces start at this chord fraction
SPAR_S = 0.74                 # the fixed wing ends here in front of them

# Tail.
STAB_Z = 1.035
STAB_HINGE_Y = -3.245         # elevator hinge line (straight across)
FIN_ROOT_Z, FIN_TOP_Z = 1.0, 2.04
FIN_HINGE = 0.62              # rudder hinge (fraction of the fin's chord)

SMOOTH = math.radians(48)

# UV kinds for NavLight (decoded by nav_light.gdshader).
NAV_RED, NAV_GREEN, NAV_STROBE, NAV_BEACON = 1, 2, 3, 4


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------- materials ---

def materials():
    m = bk.vehicle_materials((0.93, 0.93, 0.91))
    m["NavLight"] = bk.material("NavLight", (0.9, 0.9, 0.9), rough=0.2, emission=(1, 1, 1), strength=1.0)
    m["PropTip"] = bk.material("PropTip", (0.93, 0.76, 0.12), rough=0.45)
    m["PropBlur"] = bk.material("PropBlur", (0.12, 0.12, 0.13), rough=0.6, alpha=0.3)
    return m


# --------------------------------------------------------------- helpers ---

def ring_loft(part, rings, mat_fn, close=True, cap_start=False, cap_end=False, inside=None):
    """Quads between consecutive rings of 3D points (the same count each).
    `mat_fn(i, j)` -> the material of the face between rings i, i+1 and
    points j, j+1 (None = no face). `close` joins each ring's last point to
    its first; caps close the first / last ring. Faces point away from
    `inside` (or the ring's centre) as checked on a middle face, so the
    winding never depends on the order of the rings or points."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    faces = []
    for i in range(len(rings) - 1):
        for j in range(n if close else n - 1):
            j1 = (j + 1) % n
            mat = mat_fn(i, j)
            if mat is None:
                continue
            quad = [vs[i][j], vs[i][j1], vs[i + 1][j1], vs[i + 1][j]]
            if len({v.co.to_tuple(6) for v in quad}) < 3:
                continue
            try:
                f = bm.faces.new(list(dict.fromkeys(quad)))
            except ValueError:
                continue
            faces.append((f, mat, i))
    caps = []
    if cap_start:
        caps.append(bm.faces.new(list(reversed(vs[0]))))
    if cap_end:
        caps.append(bm.faces.new(vs[-1]))
    bm.normal_update()
    f, _m, i = faces[len(faces) // 2]
    c = V(inside) if inside is not None else sum((V(p) for p in rings[i]), V()) / n
    if f.normal.dot(f.calc_center_median() - c) < 0:
        for ff, _mm, _ii in faces:
            ff.normal_flip()
        for cf in caps:
            cf.normal_flip()
    vmap = {v: part.bm.verts.new(v.co) for v in bm.verts}
    for ff, mm, _ii in faces:
        nf = part.bm.faces.new([vmap[v] for v in ff.verts])
        nf.material_index = part.slot(mm)
    for cf in caps:
        nf = part.bm.faces.new([vmap[v] for v in cf.verts])
        nf.material_index = part.slot(faces[0][1])
    bm.free()


def foil(s, thick, camber=0.0):
    """NACA 4-digit half thickness and camber line at chord fraction s,
    with a slightly blunt trailing edge so lofts never collapse."""
    s = min(max(s, 0.0), 1.0)
    yt = 5.0 * thick * (0.2969 * math.sqrt(s) - 0.1260 * s - 0.3516 * s * s + 0.2843 * s ** 3 - 0.1036 * s ** 4)
    yt += 0.0025 * s
    yc = 0.0
    if camber > 0.0:
        p = 0.4
        yc = camber / p ** 2 * (2 * p * s - s * s) if s < p else camber / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * s - s * s)
    return yt, yc


def foil_ring(s0, s1, n_up, n_low, thick, camber, place):
    """A closed ring over chord fractions [s0, s1]: the upper surface from
    s1 to s0, then the lower one back to s1. `place(s, t)` maps a chord
    fraction and a height (chord units) to a 3D point. From the leading
    edge (s0 = 0) the points bunch up near the nose."""
    pts = []
    for k in range(n_up + 1):
        f = k / n_up
        s = s1 * (1 - math.sin(f * math.pi / 2)) if s0 == 0.0 else lerp(s1, s0, f)
        yt, yc = foil(s, thick, camber)
        pts.append(place(s, yc + yt))
    for k in range(1 if s0 == 0.0 else 0, n_low + 1):
        f = k / n_low
        s = s1 * (1 - math.cos(f * math.pi / 2)) if s0 == 0.0 else lerp(s0, s1, f)
        yt, yc = foil(s, thick, camber)
        pts.append(place(s, yc - yt))
    return pts


def place_object(obj, origin, x_axis=None, z_axis=None):
    """Re-bases `obj` so its origin is `origin` and its local X (or Z) axis
    points along the given direction; the mesh stays where it is."""
    if x_axis is not None:
        x = V(x_axis).normalized()
        y = V((0, 0, 1)).cross(x).normalized()
        z = x.cross(y).normalized()
    else:
        z = V(z_axis).normalized()
        x = V((0, 1, 0)).cross(z).normalized()
        y = z.cross(x).normalized()
    rot = mathutils.Matrix((x, y, z)).transposed().to_4x4()
    mat = mathutils.Matrix.Translation(origin) @ rot
    obj.data.transform(mat.inverted())
    obj.matrix_world = mat


# --------------------------------------------------------------- fuselage ---

def in_canopy(y):
    return CANOPY_BACK < y < CANOPY_FRONT


def fuse_section(y):
    """Right half: bottom centre -> widest point -> canopy rail -> top
    centre, 19 points. Point 6 is the widest, 9 lies on the rail (ZR), 10 is
    a seal band just above it, 18 the top (ZT)."""
    hw, zb, zr, zt = HW(y), ZB(y), ZR(y), ZT(y)
    zm = zb + 0.42 * (zr - zb)
    pts = []
    for k in range(7):
        a = k / 6 * math.pi / 2
        c, s = math.sin(a), math.cos(a)
        pts.append((hw * c ** (2 / P_LOW), zm - (zm - zb) * s ** (2 / P_LOW)))
    # Above the widest point one superellipse runs to the top centre, with a
    # point exactly on the rail so the glass edge is a clean line.
    h = max(zt - zm, 1e-3)
    u_r = math.asin(min(min(max((zr - zm) / h, 0.0), 0.995) ** (P_UP / 2), 0.999))
    us = [u_r * k / 3 for k in (1, 2, 3)]
    us.append(u_r + (math.pi / 2 - u_r) * 0.045)
    us += [us[3] + (math.pi / 2 - us[3]) * k / 8 for k in range(1, 9)]
    for u in us:
        c, s = math.cos(u), math.sin(u)
        pts.append((hw * c ** (2 / P_UP), zm + h * s ** (2 / P_UP)))
    pts[-1] = (0.0, zt)
    return pts


def fuse_side_x(y, z):
    """x of the fuselage's right side at height z (between the widest point
    and the rail), for the livery ribbon."""
    pts = fuse_section(y)[3:10]
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / max(z1 - z0, 1e-6)
            return lerp(x0, x1, t)
    return pts[0][0] if z < pts[0][1] else pts[-1][0]


def fuse_stations():
    keep = [CANOPY_FRONT, CANOPY_BACK, CANOPY_FRONT - 0.03, CANOPY_BACK + 0.03, *WS_BOW, *COWL_SEAM,
            NOSE_FRONT, TAIL_Y, 2.42, 2.38, -3.45, -3.5,
            wing_le(WING_ROOT), wing_le(WING_ROOT) - wing_chord(WING_ROOT)]
    return bk.stations(NOSE_FRONT, TAIL_Y, 0.2, keep=keep, refine=[(2.44, 2.1, 0.08)])


def fuse_material(m, y0, y1, j):
    y = (y0 + y1) * 0.5
    if COWL_SEAM[1] < y < COWL_SEAM[0]:
        return m["Trim"]
    if in_canopy(y):
        if j == 9:
            return m["Trim"]                              # rubber seal on the sill
        if j >= 10:
            if WS_BOW[1] < y < WS_BOW[0]:
                return m["Paint"]                         # windscreen bow
            if y > CANOPY_FRONT - 0.03 or y < CANOPY_BACK + 0.03:
                return m["Trim"]                          # frame seals front and back
            return m["Glass"]
    return m["Paint"]


def build_fuselage(part, m):
    ys = fuse_stations()
    secs = [fuse_section(y) for y in ys]
    bk.loft(part, ys, lambda i, _y: secs[i], lambda _i, j, y0, y1: fuse_material(m, y0, y1, j))
    # Close the tail cone.
    tail = secs[-1]
    bm = bmesh.new()
    vs = [bm.verts.new((x, TAIL_Y, z)) for (x, z) in tail] + [bm.verts.new((-x, TAIL_Y, z)) for (x, z) in reversed(tail[1:-1])]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    bk._append(part, bm, m["Paint"])
    # Cowl intakes: a dark disc behind the spinner; the gap either side of the
    # spinner reads as the two air inlets.
    cz = (ZB(NOSE_FRONT) + ZT(NOSE_FRONT)) * 0.5
    hz = (ZT(NOSE_FRONT) - ZB(NOSE_FRONT)) * 0.5
    bm = bmesh.new()
    rim = [bm.verts.new((HW(NOSE_FRONT) * 0.99 * math.cos(a), NOSE_FRONT - 0.012, cz + hz * 0.99 * math.sin(a)))
           for a in [k * math.pi / 12 for k in range(24)]]
    df = bm.faces.new(rim)
    df.normal_update()
    if df.normal.y < 0:
        df.normal_flip()
    bk._append(part, bm, m["Trim"])
    return ys


def cockpit(part, m, ys):
    """Inner walls, floor, baggage bulkhead, instrument panel, seats, sticks
    and throttle: what you see through the canopy (plain boxes: it's dark
    in there and the glass is tinted)."""
    im = m["Interior"]
    inner = [y for y in ys if CANOPY_FRONT + 0.02 > y > CANOPY_BACK - 0.02][::2]

    def inner_sec(_i, y):
        pts = fuse_section(y)
        out = []
        for j, (x, z) in enumerate(pts):
            a = pts[max(j - 1, 0)]
            b = pts[min(j + 1, len(pts) - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            ln = max(math.hypot(tx, tz), 1e-5)
            out.append((max(x - tz / ln * 0.02, 0.0), z + tx / ln * 0.02))
        return out
    tmp = bk.Part("inner", list(part.mats))
    bk.loft(tmp, inner, inner_sec, lambda _i, j, _y0, _y1: im if 5 <= j <= 9 else None)
    bmesh.ops.reverse_faces(tmp.bm, faces=tmp.bm.faces[:])
    bk.merge(part, tmp)
    bk.box(part, im, (0, -0.10, 0.47), (1.06, 2.25, 0.02))                        # floor
    bk.box(part, im, (0, CANOPY_BACK + 0.04, 0.80), (0.98, 0.03, 0.66))          # baggage bulkhead
    bk.box(part, im, (0, -1.02, 0.62), (0.96, 0.36, 0.02))                        # baggage floor
    bk.box(part, m["Trim"], (0, 0.93, 0.94), (0.96, 0.05, 0.32))                  # panel
    bk.box(part, im, (0, 1.0, 1.125), (0.84, 0.22, 0.03))                         # glare shield
    for k in range(4):
        x = -0.33 + k * 0.22
        bk.tube(part, m["Chrome"], (x, 0.906, 0.97), (x, 0.902, 0.97), 0.045, 8)  # instrument bezels
    for sx in (-1, 1):
        x = sx * 0.265
        bk.box(part, im, (x, -0.30, 0.56), (0.44, 0.50, 0.12))                     # cushion
        bk.box(part, im, (x, -0.62, 0.86), (0.44, 0.10, 0.62), rot=(math.radians(-18), 0, 0))   # back
        bk.box(part, im, (x, -0.74, 1.20), (0.24, 0.08, 0.13), rot=(math.radians(-18), 0, 0))   # headrest
        bk.tube(part, m["Trim"], (x, 0.20, 0.48), (x, 0.12, 0.88), 0.018, 6)       # stick
    bk.box(part, m["Trim"], (0, 0.70, 0.66), (0.14, 0.30, 0.14))                  # throttle quadrant
    bk.tube(part, m["Trim"], (0, 0.70, 0.73), (0, 0.65, 0.84), 0.012, 6)


# ------------------------------------------------------------------ wings ---

def wing_t(x):
    return min(max((abs(x) - WING_ROOT) / (WING_TIP - WING_ROOT), 0.0), 1.0)


def wing_le(x):
    return lerp(0.66, 0.50, wing_t(x))


def wing_chord(x):
    return lerp(1.58, 1.12, wing_t(x))


def wing_z(x):
    return 0.50 + max(abs(x) - WING_ROOT, 0.0) * math.tan(DIHEDRAL)


def wing_thick(x):
    return lerp(0.15, 0.12, wing_t(x))


def wing_point(x, s, t, tip_round=0.0):
    """A point on the wing at span x (signed), chord fraction s and height t
    (chord units). `tip_round` 0..1 draws the leading and trailing edges in
    and thins the section toward the rounded tip fairing."""
    ax = abs(x)
    c = wing_chord(ax) * (1.0 - 0.22 * tip_round ** 2)
    le = wing_le(ax) - 0.10 * tip_round ** 2
    t *= 0.25 + 0.75 * math.sqrt(max(1.0 - tip_round ** 2, 0.0))
    return (x, le - s * c, wing_z(ax) + t * c - s * c * math.tan(INCIDENCE))


def wing_stations():
    xs = {WING_ROOT, FLAP[0], FLAP[1], AILERON[0], AILERON[1], 3.88, WING_TIP, 3.97, 4.01, 4.04, WING_END}
    x = 0.82
    while x < AILERON[1] - 0.1:
        xs.add(round(x, 4))
        x += 0.22
    return sorted(xs)


def wing_spar_s(x):
    """Where the fixed wing ends: in front of the flaps and ailerons, the
    full chord at the tip."""
    ax = abs(x)
    if ax <= AILERON[1] + 0.001:
        return SPAR_S
    return 1.0 if ax >= 3.88 - 0.001 else lerp(SPAR_S, 1.0, (ax - AILERON[1]) / (3.88 - AILERON[1]))


def build_wing(part, m, side):
    rings = []
    for x in wing_stations():
        r = max(x - WING_TIP, 0.0) / (WING_END - WING_TIP)
        rings.append(foil_ring(0.0, wing_spar_s(x), 9, 8, wing_thick(x), 0.02,
                               lambda s, t, xx=x * side, rr=r: wing_point(xx, s, t, rr)))
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)


def build_surface(m, name, x0, x1, side, step=0.23):
    """A flap or aileron: the wing behind the hinge between spans x0 and x1,
    a closed part with its hinge line as the local X axis."""
    part = bk.Part(name, [])
    xs = [x0]
    x = x0 + step
    while x < x1 - 0.06:
        xs.append(x)
        x += step
    xs.append(x1)
    rings = [foil_ring(HINGE_S, 1.0, 4, 4, wing_thick(xx), 0.02, lambda s, t, xs_=xx * side: wing_point(xs_, s, t))
             for xx in xs]
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    a = V(wing_point(x0 * side, HINGE_S, 0.0))
    b = V(wing_point(x1 * side, HINGE_S, 0.0))
    obj = part.to_object(SMOOTH)
    left, right = (a, b) if a.x < b.x else (b, a)
    place_object(obj, (a + b) * 0.5, x_axis=right - left)
    return obj


# ------------------------------------------------------------------- tail ---

def stab_le(x):
    return lerp(-2.80, -2.98, min(abs(x) / 1.5, 1.0))


def stab_te(x):
    return lerp(-3.53, -3.47, min(abs(x) / 1.5, 1.0))


def stab_point(x, s, t):
    le, te = stab_le(x), stab_te(x)
    c = le - te
    tip = min(max(abs(x) - 1.40, 0.0) / 0.12, 1.0)
    t *= 0.15 + 0.85 * math.sqrt(max(1.0 - tip ** 2, 0.0))
    return (x, le - s * c, STAB_Z + t * c)


def build_stab(part, m):
    for side in (-1, 1):
        rings = []
        for x in (0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.40, 1.46, 1.50, 1.52):
            le, te = stab_le(x), stab_te(x)
            s1 = (le - STAB_HINGE_Y) / (le - te)
            rings.append(foil_ring(0.0, s1, 7, 6, 0.10, 0.0, lambda s, t, xx=x * side: stab_point(xx, s, t)))
        ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)


def build_elevator(m):
    part = bk.Part("Elevator", [])
    for side in (-1, 1):
        rings = []
        for x in (0.07, 0.35, 0.65, 0.95, 1.2, 1.40, 1.46):
            le, te = stab_le(x), stab_te(x)
            s0 = (le - (STAB_HINGE_Y - 0.015)) / (le - te)
            rings.append(foil_ring(s0, 1.0, 3, 3, 0.10, 0.0, lambda s, t, xx=x * side: stab_point(xx, s, t)))
        ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    obj = part.to_object(SMOOTH)
    place_object(obj, V((0, STAB_HINGE_Y - 0.015, STAB_Z)), x_axis=(1, 0, 0))
    return obj


def fin_le(z):
    return lerp(-2.60, -3.14, (z - FIN_ROOT_Z) / (FIN_TOP_Z - FIN_ROOT_Z))


def fin_te(z):
    return lerp(-3.60, -3.50, (z - FIN_ROOT_Z) / (FIN_TOP_Z - FIN_ROOT_Z))


def fin_point(z, s, t, top_round=0.0):
    le, te = fin_le(z), fin_te(z)
    c = le - te
    t *= 0.15 + 0.85 * math.sqrt(max(1.0 - top_round ** 2, 0.0))
    return (t * c, le - s * c, z)


FIN_Z = (1.2, 1.4, 1.6, 1.8, 1.95, 2.0, 2.025, FIN_TOP_Z)


def build_fin(part, m):
    rings = []
    for z in (FIN_ROOT_Z - 0.06,) + FIN_Z:
        r = max(z - 1.95, 0.0) / (FIN_TOP_Z - 1.95)
        rings.append(foil_ring(0.0, FIN_HINGE, 7, 6, 0.10, 0.0, lambda s, t, zz=z, rr=r: fin_point(zz, s, t, rr)))
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    # Dorsal strake: a low, thin fillet running forward from the fin's root.
    rings = []
    for k, z in enumerate((1.0, 1.07, 1.14, 1.21, 1.27)):
        f = k / 4
        le = lerp(-2.05, -2.72, f)
        te = -2.98
        c = le - te
        th = 0.045 / c
        rings.append(foil_ring(0.0, 1.0, 5, 4, th, 0.0, lambda s, t, le=le, c=c, z=z: (t * c, le - s * c, z)))
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)


def build_rudder(m):
    part = bk.Part("Rudder", [])
    s0 = FIN_HINGE + 0.015
    rings = []
    for z in (0.97,) + FIN_Z:
        r = max(z - 1.95, 0.0) / (FIN_TOP_Z - 1.95)
        zc = max(z, FIN_ROOT_Z)
        rings.append(foil_ring(s0, 1.0, 3, 3, 0.10, 0.0,
                               lambda s, t, z_=z, zc=zc, rr=r: (fin_point(zc, s, t, rr)[0], fin_point(zc, s, t, rr)[1], z_)))
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    obj = part.to_object(SMOOTH)
    a = V((0.0, fin_le(FIN_ROOT_Z) - s0 * (fin_le(FIN_ROOT_Z) - fin_te(FIN_ROOT_Z)), 0.97))
    b = V((0.0, fin_le(FIN_TOP_Z) - s0 * (fin_le(FIN_TOP_Z) - fin_te(FIN_TOP_Z)), FIN_TOP_Z))
    place_object(obj, (a + b) * 0.5, z_axis=b - a)
    return obj


# ------------------------------------------------------------------- gear ---

def pant(part, mat, center, length, half_w, height, n=10):
    """A teardrop wheel fairing round a wheel at `center`: ellipse rings
    along y, fullest a third of the way back. The tyre pokes out through
    its bottom, which reads as the slot."""
    cx, cy, cz = center
    rings = []
    for f in (0.0, 0.03, 0.09, 0.18, 0.30, 0.45, 0.60, 0.75, 0.88, 0.96, 1.0):
        y = cy + length * (0.36 - f)
        if f < 0.36:
            prof = math.sin(math.pi * 0.5 * f / 0.36) ** 0.7
        else:
            prof = math.cos(math.pi * 0.5 * (f - 0.36) / 0.64) ** 0.8
        hw = max(half_w * prof, 0.004)
        hh = max(height * 0.5 * prof, 0.004)
        zc = cz + 0.11 + 0.03 * f
        rings.append([(cx + hw * math.cos(2 * math.pi * k / n), y, zc + hh * math.sin(2 * math.pi * k / n))
                      for k in range(n)])
    ring_loft(part, rings, lambda i, j: mat, cap_start=True, cap_end=True, inside=(cx, cy, cz + 0.11))


def build_gear(part, m):
    paint = m["Paint"]
    for sx in (-1, 1):
        # Spring-steel leg in a fairing, from the wing root to the axle.
        bk.tube(part, paint, (sx * 0.52, MAIN_Y + 0.05, 0.43), (sx * (MAIN_X - 0.07), MAIN_Y, 0.06), 0.032, 8)
        pant(part, paint, (sx * MAIN_X, MAIN_Y, 0.0), 0.86, 0.125, 0.44)
    # Nose leg: an oleo with a chrome slider, a fork and its own fairing.
    bk.tube(part, m["Trim"], (0, NOSE_Y + 0.03, NOSE_Z + 0.36), (0, NOSE_Y + 0.04, 0.50), 0.042, 10)
    bk.tube(part, m["Chrome"], (0, NOSE_Y + 0.02, NOSE_Z + 0.25), (0, NOSE_Y + 0.03, NOSE_Z + 0.38), 0.028, 10)
    bk.box(part, m["Trim"], (0, NOSE_Y + 0.01, NOSE_Z + 0.25), (0.17, 0.07, 0.03))
    for sx in (-1, 1):
        bk.box(part, m["Trim"], (sx * 0.075, NOSE_Y, NOSE_Z + 0.12), (0.02, 0.06, 0.26))
    pant(part, paint, (0.0, NOSE_Y, NOSE_Z), 0.70, 0.105, 0.38)


def build_wheel():
    """The plane's tyre and hub (plane_wheel.glb), at the shared 0.37 m base
    radius like every wheel (the scene scales it to MAIN_R / NOSE_R)."""
    bk.reset_scene()
    tire = bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9)
    rim = bk.material("Rim", (0.78, 0.79, 0.80), rough=0.35, metal=1.0)
    part = bk.Part("PlaneWheel", [])
    # A fat, round aircraft tyre on a small split hub.
    mw.tyre(part, tire, 0.25, 0.19, tread="grooves", segments=28, bulge=0.012)
    bk.lathe(part, rim, [(-0.13, 0.19), (-0.12, 0.20), (-0.105, 0.17), (-0.10, 0.08), (-0.11, 0.05), (-0.13, 0.0)], 24)
    bk.lathe(part, rim, [(0.13, 0.0), (0.11, 0.05), (0.10, 0.08), (0.105, 0.17), (0.12, 0.20), (0.13, 0.19)], 24)
    for sx in (-1, 1):
        mw.lugs(part, rim, 6, 0.12, sx * 0.105, nut=0.012)
    bk.export([part.to_object(math.radians(40))], "plane_wheel.glb")


# -------------------------------------------------------------- propeller ---

def build_propeller(m):
    part = bk.Part("Propeller", [])
    # Spinner: a lathe round the thrust axis (built round X, turned to Y).
    bm = bmesh.new()
    prof = [(0.0, 0.28), (0.04, 0.28), (0.10, 0.265), (0.17, 0.225), (0.23, 0.165), (0.28, 0.095), (0.31, 0.04),
            (0.322, 0.0)]
    seg = 16
    rings = [[bm.verts.new((x, r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg))) for (x, r) in prof]
             for k in range(seg)]
    for k in range(seg):
        r0, r1 = rings[k], rings[(k + 1) % seg]
        for j in range(len(prof) - 1):
            quad = list(dict.fromkeys([r0[j], r1[j], r1[j + 1], r0[j + 1]]))
            if len({v.co.to_tuple(6) for v in quad}) >= 3:
                bm.faces.new(quad)
    bm.faces.new([r[0] for r in reversed(rings)])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, "Z"))     # X axis -> Y axis
    bk._append(part, bm, m["Paint"])
    # Two twisted blades along +-X with yellow tips.
    for side in (-1, 1):
        rings = []
        tips = []
        for r in (0.16, 0.30, 0.48, 0.64, 0.78, 0.86, PROP_R):
            f = (r - 0.16) / (PROP_R - 0.16)
            chord = lerp(0.15, 0.10, f) * (1.0 - 0.45 * max(f - 0.85, 0.0) / 0.15)
            pitch = math.radians(lerp(46.0, 14.0, f))
            th = lerp(0.18, 0.07, f)

            def blade(s, t, r=r, chord=chord, pitch=pitch):
                u = (s - 0.35) * chord             # along the chord
                v = t * chord                      # thickness
                yy = u * math.sin(pitch) + v * math.cos(pitch)
                zz = -u * math.cos(pitch) + v * math.sin(pitch)
                return (side * r, yy + 0.06, zz * side)
            rings.append(foil_ring(0.0, 1.0, 4, 4, th, 0.0, blade))
            tips.append(f >= 0.87)
        ring_loft(part, rings, lambda i, j, tips=tips: m["PropTip"] if tips[i] else m["Trim"],
                  cap_start=True, cap_end=True)
    obj = part.to_object(math.radians(40))
    obj.data.transform(mathutils.Matrix.Translation((0, PROP_Y, THRUST_Z)))
    place_object(obj, V((0, PROP_Y, THRUST_Z)), z_axis=(0, 0, 1))
    return obj


def build_prop_disc(m):
    """A flat ring in the propeller's plane: aircraft.gd fades it in as the
    propeller speeds up (the blades blur into a disc)."""
    part = bk.Part("PropDisc", [])
    bm = bmesh.new()
    seg = 28
    inner = [bm.verts.new((0.30 * math.cos(2 * math.pi * k / seg), 0.0, 0.30 * math.sin(2 * math.pi * k / seg))) for k in range(seg)]
    outer = [bm.verts.new((PROP_R * math.cos(2 * math.pi * k / seg), 0.0, PROP_R * math.sin(2 * math.pi * k / seg))) for k in range(seg)]
    for k in range(seg):
        k1 = (k + 1) % seg
        bm.faces.new([inner[k], outer[k], outer[k1], inner[k1]])
    bm.normal_update()
    for f in bm.faces:
        if f.normal.y < 0:
            f.normal_flip()
    bk._append(part, bm, m["PropBlur"])
    obj = part.to_object()
    obj.data.transform(mathutils.Matrix.Translation((0, PROP_Y + 0.03, THRUST_Z)))
    place_object(obj, V((0, PROP_Y + 0.03, THRUST_Z)), z_axis=(0, 0, 1))
    return obj


# ---------------------------------------------------------------- details ---

def details(surf, part, wings, m):
    """Small parts on the fuselage (`part`) and the wings (`wings`, keyed by
    side -1 / 1); `surf` is the whole plane for projected patches."""
    up = (0, 0, 1)
    # Exhaust stubs under the cowl and the cooling-air outlet.
    for sx in (-1, 1):
        bk.tube(part, m["Trim"], (sx * 0.17, 1.72, 0.47), (sx * 0.19, 1.58, 0.36), 0.032, 8)
        bk.tube(part, m["Chrome"], (sx * 0.19, 1.585, 0.365), (sx * 0.195, 1.575, 0.355), 0.026, 8)
    bk.patch(surf, part, m["Trim"], bk.rect(0.40, 0.16, 0.4), (0, 1.66, -1.0), (0, 0, 1), (0, 1, 0), lift=0.004, grid=(4, 2))
    # A boarding step behind the right wing.
    bk.tube(part, m["Chrome"], (0.50, -1.16, 0.52), (0.62, -1.16, 0.42), 0.01, 6)
    bk.box(part, m["Trim"], (0.63, -1.16, 0.415), (0.09, 0.07, 0.012))
    # Antenna blade on the turtle deck.
    bm = bmesh.new()
    base = [(-1.98, ZT(-1.98) - 0.01), (-2.10, ZT(-2.10) - 0.01), (-2.09, ZT(-2.09) + 0.17), (-2.04, ZT(-2.04) + 0.17)]
    vs = [bm.verts.new((dx, y, z)) for dx in (-0.005, 0.005) for (y, z) in base]
    for q in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([vs[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Trim"])
    # A white light on the tail and a red beacon on top of the fin.
    bk.box(part, m["NavLight"], (0, TAIL_Y - 0.03, ZB(TAIL_Y) + 0.03), (0.04, 0.05, 0.04), kind=NAV_STROBE)
    bk.box(part, m["NavLight"], (0, fin_le(FIN_TOP_Z) - 0.12, FIN_TOP_Z + 0.02), (0.04, 0.10, 0.04), kind=NAV_BEACON)
    # Wings: fuel caps, the pitot tube and landing light on the left, the
    # navigation lights in the tips with strobes behind them.
    for sx, kind in ((-1, NAV_RED), (1, NAV_GREEN)):
        w = wings[sx]
        bk.patch(surf, w, m["Chrome"], bk.ellipse(0.07, 0.07), (sx * 1.6, wing_le(1.6) - 0.35, 2.0), (0, 0, -1),
                 (0, 1, 0), lift=0.003, grid=3)
        tip = V(wing_point(sx * 4.0, 0.08, 0.0, 0.6))
        bk.box(w, m["NavLight"], (tip.x + sx * 0.012, tip.y - 0.02, tip.z), (0.05, 0.10, 0.05), bevel=0.012, segments=1,
               kind=kind)
        st = V(wing_point(sx * 4.0, 0.80, 0.0, 0.6))
        bk.box(w, m["NavLight"], (st.x + sx * 0.01, st.y, st.z), (0.04, 0.06, 0.03), kind=NAV_STROBE)
    w = wings[-1]
    bk.tube(w, m["Chrome"], (-2.6, wing_le(2.6) - 0.3, wing_z(2.6) - 0.06), (-2.6, wing_le(2.6) + 0.2, wing_z(2.6) - 0.09),
            0.009, 6)
    lx = -1.45
    le = V(wing_point(lx, 0.0, 0.0))
    bk.patch(surf, w, m["Trim"], bk.ellipse(0.24, 0.10), (lx, le.y + 0.5, le.z), (0, -1, 0), up, lift=0.003, grid=4)
    bk.patch(surf, w, m["Headlight"], bk.ellipse(0.20, 0.075), (lx, le.y + 0.5, le.z), (0, -1, 0), up, lift=0.006,
             grid=4, kind=bk.LAMP)


def livery(surf_wings, surf_fin):
    """The Stripes mesh: a double cheat line sweeping down each side of the
    fuselage (a ribbon following the shell), stripes across the wing tips
    and a band on the fin."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.79, 0.17, 0.12), rough=0.3)
    ys = [y for y in bk.stations(2.25, -3.15, 0.17, keep=[2.25, -3.15])]
    for sx in (-1, 1):
        for (f0, f1) in ((0.50, 0.66), (0.36, 0.40)):
            rings = []
            for y in ys:
                zb, zr = ZB(y), ZR(y)
                ring = []
                for f in (f0, f1):
                    z = lerp(zb, zr, f)
                    ring.append((sx * (fuse_side_x(y, z) + 0.005), y, z))
                rings.append(ring)
            ring_loft(part, rings, lambda i, j: mat, close=False, inside=(0.0, 0.0, 0.8))
        bk.patch(surf_wings, part, mat, bk.rect(0.22, 0.80), (sx * 3.55, wing_le(3.55) - 0.43, 3.0), (0, 0, -1), (0, 1, 0),
                 lift=0.005, grid=(1, 5))
        bk.patch(surf_fin, part, mat, bk.rect(0.30, 0.14), (sx * 1.0, -3.12, 1.62), (-sx, 0, 0), (0, 0, 1), lift=0.005,
                 grid=(3, 1))
    return part


# ------------------------------------------------------------------ build ---

def build():
    bk.reset_scene()
    m = materials()
    body = bk.Part("PlaneBody", [])
    ys = build_fuselage(body, m)
    # The wings are meshes of their own, so a dent in one never has to touch
    # the other or the fuselage (VehicleDamage skips far meshes).
    wings = {-1: bk.Part("WingL", list(body.mats)), 1: bk.Part("WingR", list(body.mats))}
    for side, w in wings.items():
        build_wing(w, m, side)
    surf_wings = bk.Surface(list(wings.values()))
    tail = bk.Part("tail", list(body.mats))
    build_stab(tail, m)
    build_fin(tail, m)
    surf_fin = bk.Surface([tail])
    bk.merge(body, tail)
    build_gear(body, m)
    cockpit(body, m, ys)
    surf = bk.Surface([body] + list(wings.values()))
    details(surf, body, wings, m)
    stripes = livery(surf_wings, surf_fin)
    objs = [body.to_object(SMOOTH), wings[-1].to_object(SMOOTH), wings[1].to_object(SMOOTH)]
    for side, sname in ((-1, "L"), (1, "R")):
        objs.append(build_surface(m, "Flap" + sname, FLAP[0], FLAP[1], side))
        objs.append(build_surface(m, "Aileron" + sname, AILERON[0], AILERON[1], side))
    objs.append(build_elevator(m))
    objs.append(build_rudder(m))
    objs.append(build_propeller(m))
    objs.append(build_prop_disc(m))
    objs.append(stripes.to_object(SMOOTH))
    bk.export(objs, "plane_body.glb")


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
    build_wheel()
