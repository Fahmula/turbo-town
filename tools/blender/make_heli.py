"""Generates the helicopter (heli_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_heli.py

Design language (ART_BIBLE.md §12): a generic, unbranded light utility
helicopter. A rounded teardrop cabin with a big wrap-round windscreen that
sweeps up into the roof, chin windows by the pilots' feet, two doors a side;
a turbine cowling on the roof behind a short mast and a two-blade teetering
main rotor (10.1 m across); a slim tail boom with a horizontal stabiliser and
endplates, a swept fin with the tail rotor on its left; tubular skids on two
arched cross tubes. Real proportions (about 9.6 m long without the rotor,
3.0 m to the top of the hub). The fuselage is a loft like the cars', so its
panels are evenly meshed for dents.

Conventions (Blender Z-up, front = +Y = Godot -Z, right = +X):
  * Origin on the centre line under the rotor mast (y = 0, about the centre
    of gravity), z = 0 at the skid tubes' centre height; the ground is
    z = -SKID_R. scenes/vehicles/helicopter.tscn puts the four skid contact
    "wheels" at (+-SKID_X, CONTACT_Y) with radius SKID_R.
  * Objects (their node names are a code contract, see helicopter.gd):
      CabinFront  the cabin ahead of the B-pillar: nose, windscreen, front
                  doors, the pilots' seats and panel (deformable)
      HeliBody    the rear cabin, cowling, mast, rear bench (deformable)
      TailBoom    the boom, fin, stabiliser (deformable, apart so a dent at
                  the nose never has to touch it)
      Skids       skids and cross tubes
      MainRotor   hub and blades; origin on the mast at the hub, spins about
                  its local Z (Godot local Y)
      RotorDisc   the main rotor's blur disc (material RotorBlur), at the hub
      TailRotor   hub and blades; origin at its hub, spins about its local X
      TailDisc    the tail rotor's blur disc (material TailBlur)
      Stripes     the livery (material Stripe): a cheat line along the cabin,
                  a band down the boom and one on the fin
  * Materials: the vehicle set (Paint, Glass, Trim, Chrome, Headlight = the
    search / landing light, Interior), plus NavLight (UV kind NAV_RED /
    NAV_GREEN / NAV_STROBE / NAV_BEACON, decoded by nav_light.gdshader),
    PropTip (blade tip bands), RotorBlur and TailBlur (prop_blur.gdshader
    discs), Frame (the skids' painted tubes).
  * The pilot sits on the left (like every vehicle in the game), the
    passenger on the right, two more on the rear bench.
"""
import math
import os
import sys

import bmesh
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402
from make_plane import foil_ring, place_object, ring_loft  # noqa: E402

V = mathutils.Vector

# ----------------------------------------------------------------- layout ---
SKID_R = 0.045                # contact radius (the tube is 0.04)
SKID_X = 1.12                 # skid centre lines (x = +-SKID_X)
SKID_BACK, SKID_TOE = -1.40, 1.30   # straight run, then the upturned toe
CROSS_Y = (0.92, -0.86)       # the two cross tubes
CONTACT_Y = (1.05, -1.05)     # the scene's contact points along each skid
MAST_Y = 0.0
HUB_Z = 2.95                  # main rotor hub
ROTOR_R = 5.05
ROOT_R = 0.50                 # blades start here
TR = (-0.30, -6.16, 1.98)     # tail rotor hub (left of the fin)
TR_R = 0.78

NOSE_Y, TAIL_Y = 2.10, -6.45
WIN_LOW, WIN_TOP = 1.14, 1.93     # side window band (z)
WS_BACK = 1.10                # the windscreen ends at the A-pillar here
A_PILLAR = (1.02, 1.10)
B_PILLAR = (-0.10, 0.10)
FRONT_WIN = (0.10, 1.02)
REAR_WIN = (-0.98, -0.10)
EYEBROW = 0.86                # the roof is glass ahead of this
CHIN = (1.32, 1.98)           # chin windows (y)
SEAMS = [(1.012, 1.02), (-0.004, 0.004), (-1.058, -1.05)]   # door shut lines
CABIN_BACK = -1.12

HW = bk.curve([(2.10, 0.05), (2.06, 0.20), (1.98, 0.36), (1.80, 0.52), (1.50, 0.64), (1.05, 0.70), (0.0, 0.71),
               (-0.90, 0.70), (-1.30, 0.66), (-1.70, 0.52), (-2.10, 0.36), (-2.50, 0.27), (-3.50, 0.22),
               (-5.00, 0.17), (-6.00, 0.14), (-6.45, 0.12)])
ZB = bk.curve([(2.10, 1.03), (2.06, 0.94), (1.98, 0.85), (1.80, 0.72), (1.50, 0.63), (1.10, 0.585), (-0.90, 0.585),
               (-1.30, 0.64), (-1.70, 0.86), (-2.10, 1.08), (-2.50, 1.20), (-3.50, 1.29), (-5.00, 1.38), (-6.45, 1.44)])
ZT = bk.curve([(2.10, 1.10), (2.06, 1.22), (1.98, 1.34), (1.80, 1.56), (1.50, 1.79), (1.10, 1.97), (0.70, 2.06),
               (0.0, 2.10), (-0.90, 2.08), (-1.30, 2.03), (-1.70, 1.92), (-2.10, 1.75), (-2.50, 1.63), (-3.50, 1.56),
               (-5.00, 1.55), (-6.45, 1.57)])

# Engine cowling on the roof: half width and top by station.
COWL_FRONT, COWL_BACK = 0.62, -2.75
WC = bk.curve([(0.62, 0.20), (0.40, 0.38), (0.10, 0.44), (-1.30, 0.45), (-1.90, 0.38), (-2.25, 0.27), (-2.50, 0.19),
               (-2.75, 0.12)])
ZC = bk.curve([(0.62, 2.06), (0.42, 2.30), (0.15, 2.43), (-1.20, 2.46), (-1.80, 2.38), (-2.20, 2.10), (-2.50, 1.80),
               (-2.75, 1.58)])

SMOOTH = math.radians(48)

# UV kinds for NavLight (decoded by nav_light.gdshader).
NAV_RED, NAV_GREEN, NAV_STROBE, NAV_BEACON = 1, 2, 3, 4


def lerp(a, b, t):
    return a + (b - a) * t


def within(y, rng):
    return rng[0] < y < rng[1]


# ------------------------------------------------------------- materials ---

def materials():
    m = bk.vehicle_materials((0.72, 0.13, 0.10))
    m["NavLight"] = bk.material("NavLight", (0.9, 0.9, 0.9), rough=0.2, emission=(1, 1, 1), strength=1.0)
    m["PropTip"] = bk.material("PropTip", (0.93, 0.76, 0.12), rough=0.45)
    m["RotorBlur"] = bk.material("RotorBlur", (0.12, 0.12, 0.13), rough=0.6, alpha=0.3)
    m["TailBlur"] = bk.material("TailBlur", (0.12, 0.12, 0.13), rough=0.6, alpha=0.3)
    m["Frame"] = bk.material("Frame", (0.58, 0.59, 0.60), rough=0.42, metal=0.7)
    return m


# --------------------------------------------------------------- helpers ---

def sweep(part, mat, pts, radius, seg=10, cap_start=True, cap_end=True):
    """A round tube along the polyline `pts` (rings turned with the path, so
    bends don't pinch)."""
    pts = [V(p) for p in pts]
    n = len(pts)
    tangents = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    ref = V((0, 0, 1)) if abs(tangents[0].z) < 0.9 else V((1, 0, 0))
    normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    rings = []
    for i in range(n):
        t = tangents[i]
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        rings.append([tuple(pts[i] + (normal * math.cos(2 * math.pi * k / seg) + binormal * math.sin(2 * math.pi * k / seg)) * radius)
                      for k in range(seg)])
    centre = sum(pts, V()) / n
    ring_loft(part, rings, lambda i, j: mat, cap_start=cap_start, cap_end=cap_end, inside=None if n > 2 else centre)


def annulus(part, mat, r0, r1, seg, place):
    """A flat ring between radii r0 and r1; `place(r, a)` maps a radius and
    an angle to a point."""
    bm = bmesh.new()
    inner = [bm.verts.new(place(r0, 2 * math.pi * k / seg)) for k in range(seg)]
    outer = [bm.verts.new(place(r1, 2 * math.pi * k / seg)) for k in range(seg)]
    for k in range(seg):
        k1 = (k + 1) % seg
        bm.faces.new([inner[k], outer[k], outer[k1], inner[k1]])
    bk._append(part, bm, mat)


# --------------------------------------------------------------- fuselage ---

def boom_t(y):
    return bk.smoothstep(-1.6, -2.6, y)


def fuse_section(y):
    """Right half, bottom centre -> widest point -> window band -> top
    centre, 23 points. 9 is the side windows' bottom edge (WIN_LOW), 14 their
    top (WIN_TOP); 8 and 15 are seal bands just outside them. Where the
    section is too short for the band (the nose, the boom) the band is
    squeezed in proportion, so the rows stay in order and the windscreen's
    lower edge dips smoothly toward the nose. The boom's sections are round
    and keep the same point count."""
    hw, zb, zt = HW(y), ZB(y), ZT(y)
    bt = boom_t(y)
    zm = zb + lerp(0.34, 0.5, bt) * (zt - zb)
    pl = lerp(2.7, 2.0, bt)
    pu = lerp(2.8, 2.0, bt)
    pts = []
    for k in range(7):
        a = k / 6 * math.pi / 2
        pts.append((hw * math.sin(a) ** (2 / pl), zm - (zm - zb) * math.cos(a) ** (2 / pl)))
    h = max(zt - zm, 1e-3)

    def at_z(z):
        s = min(max((z - zm) / h, 0.0), 0.9999)
        u = math.asin(s ** (pu / 2))
        return u, (hw * math.cos(u) ** (2 / pu), zm + h * math.sin(u) ** (2 / pu))

    levels = [WIN_LOW - 0.03, WIN_LOW] + [lerp(WIN_LOW, WIN_TOP, k / 5) for k in range(1, 6)] + [WIN_TOP + 0.03]
    lo, hi = zm + 0.01 * h, zm + 0.9 * h
    a, b = levels[0], levels[-1]
    if a < lo or b > hi:
        na, nb = max(a, lo), min(b, hi)
        if nb - na < 0.3 * (hi - lo):
            na, nb = lo, hi
        levels = [na + (z - a) / (b - a) * (nb - na) for z in levels]
    levels = [zm + (levels[0] - zm) * 0.5] + levels
    for z in levels[:-1]:
        pts.append(at_z(z)[1])
    u15, p15 = at_z(levels[-1])
    pts.append(p15)
    for k in range(1, 8):
        u = lerp(u15, math.pi / 2, k / 7)
        pts.append((hw * max(math.cos(u), 0.0) ** (2 / pu), zm + h * math.sin(u) ** (2 / pu)))
    pts[-1] = (0.0, zt)
    return pts


def side_x(y, z):
    """x of the fuselage's right side at height z."""
    pts = fuse_section(y)
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        if z0 <= z <= z1:
            return lerp(x0, x1, (z - z0) / max(z1 - z0, 1e-6))
    return 0.0


def fuse_stations():
    keep = [NOSE_Y, 2.06, 1.98, CHIN[0], CHIN[1], WS_BACK, *A_PILLAR, EYEBROW, *FRONT_WIN, *B_PILLAR, *REAR_WIN,
            CABIN_BACK, -1.3, -1.7, -2.1, -2.5, TAIL_Y]
    for a, b in SEAMS:
        keep += [a, b]
    cabin = bk.stations(NOSE_Y, -2.5, 0.16, keep=keep, refine=[(NOSE_Y, 1.86, 0.06)])
    boom = [y for y in bk.stations(-2.5, TAIL_Y, 0.42, keep=[-2.5, -4.45, -4.87, TAIL_Y]) if y < -2.5]
    return sorted(set(cabin + boom), reverse=True)


def fuse_material(m, y0, y1, j):
    y = (y0 + y1) * 0.5
    for a, b in SEAMS:
        if a <= y <= b and 1 <= j <= 14:
            return m["Trim"]
    if within(y, (WS_BACK, 2.06)):
        # The windscreen: down to the seal row, up over the nose to a centre post.
        if 9 <= j <= 20:
            return m["Glass"]
        if j == 8:
            return m["Trim"]
    if within(y, CHIN) and 1 <= j <= 4:
        return m["Glass"]                                   # chin windows
    if within(y, (EYEBROW, WS_BACK)) and 15 <= j <= 20:
        return m["Glass"]                                   # roof windows over the pilots
    for rng in (FRONT_WIN, REAR_WIN):
        if within(y, rng):
            if 9 <= j <= 13:
                return m["Glass"]
            if j in (8, 14):
                return m["Trim"]                            # rubber seals
    return m["Paint"]


def build_fuselage(part, m):
    ys = fuse_stations()
    secs = [fuse_section(y) for y in ys]
    bk.loft(part, ys, lambda i, _y: secs[i], lambda _i, j, y0, y1: fuse_material(m, y0, y1, j))
    # Close the nose tip and the end of the boom.
    for y, sec, sign in ((ys[0], secs[0], 1), (ys[-1], secs[-1], -1)):
        bm = bmesh.new()
        vs = [bm.verts.new((x, y, z)) for (x, z) in sec] + [bm.verts.new((-x, y, z)) for (x, z) in reversed(sec[1:-1])]
        f = bm.faces.new(vs)
        f.normal_update()
        if f.normal.y * sign < 0:
            f.normal_flip()
        bk._append(part, bm, m["Paint"])
    return ys


def cowl_section(y):
    """The cowling's right half from its foot on the roof to the top centre."""
    wc, zc = WC(y), ZC(y)
    base = ZT(y) - 0.06
    h = max(zc - base, 0.02)
    pts = []
    for k in range(10):
        a = k / 9 * math.pi / 2
        pts.append((wc * math.cos(a) ** (2 / 3.2), base + h * math.sin(a) ** (2 / 3.2)))
    pts[-1] = (0.0, zc)
    return pts


def build_cowl(part, m):
    ys = bk.stations(COWL_FRONT, COWL_BACK, 0.2, keep=[0.42, -0.10, -0.60, -1.9, -2.5])
    secs = [cowl_section(y) for y in ys]
    # (loft wants a bottom centre point: start each section on the centre line.)
    full = [[(0.0, s[0][1])] + s for s in secs]
    bk.loft(part, ys, lambda i, _y: full[i], lambda _i, j, _y0, _y1: None if j == 0 else m["Paint"])
    for y, sec, sign in ((ys[0], secs[0], 1), (ys[-1], secs[-1], -1)):
        bm = bmesh.new()
        vs = [bm.verts.new((x, y, z)) for (x, z) in sec] + [bm.verts.new((-x, y, z)) for (x, z) in reversed(sec[:-1])]
        f = bm.faces.new(vs)
        f.normal_update()
        if f.normal.y * sign < 0:
            f.normal_flip()
        bk._append(part, bm, m["Paint"])


def cabin_interior(part, m, ys):
    """Inner walls, floor, bulkhead, seats, sticks, collectives, pedals and
    the instrument panel: what you see through the glass (plain shapes: the
    glass is tinted)."""
    im = m["Interior"]
    inner = [y for y in ys if CABIN_BACK - 0.02 < y < 1.96][::3]

    def inner_sec(_i, y):
        pts = fuse_section(y)
        out = []
        for j, (x, z) in enumerate(pts):
            a = pts[max(j - 1, 0)]
            b = pts[min(j + 1, len(pts) - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            ln = max(math.hypot(tx, tz), 1e-5)
            out.append((max(x - tz / ln * 0.025, 0.0), z + tx / ln * 0.025))
        return out

    def inner_mat(_i, j, y0, y1):
        if within((y0 + y1) * 0.5, CHIN) and 1 <= j <= 4:
            return None                                 # (see out through the chin windows)
        if j <= 8:
            return im                                   # door cards, footwell sides
        if j >= 15 and y0 < EYEBROW:
            return im                                   # headliner
        return None
    tmp = bk.Part("inner", list(part.mats))
    bk.loft(tmp, inner, inner_sec, inner_mat)
    bmesh.ops.reverse_faces(tmp.bm, faces=tmp.bm.faces[:])
    bk.merge(part, tmp)
    bk.box(part, im, (0, 0.15, 0.70), (1.0, 2.46, 0.03))                           # floor
    # Rear bulkhead: the cabin's own cross-section, a little inside the skin.
    yb = CABIN_BACK + 0.02
    sec = inner_sec(0, yb)
    sec = [(x * 0.97, z) for (x, z) in sec]
    bm = bmesh.new()
    vs = [bm.verts.new((x, yb, max(z, 0.69))) for (x, z) in sec] + [bm.verts.new((-x, yb, max(z, 0.69))) for (x, z) in reversed(sec[1:-1])]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y < 0:
        f.normal_flip()
    bk._append(part, bm, im)
    for sx in (-1, 1):
        x = sx * 0.33
        bk.box(part, m["Trim"], (x, 0.36, 0.81), (0.40, 0.40, 0.22))              # seat box
        bk.box(part, im, (x, 0.36, 0.95), (0.46, 0.46, 0.10))                     # cushion
        bk.box(part, im, (x, 0.10, 1.30), (0.46, 0.09, 0.62), rot=(math.radians(-6), 0, 0))      # back
        bk.box(part, im, (x, 0.07, 1.69), (0.26, 0.08, 0.15), rot=(math.radians(-6), 0, 0))         # headrest
        bk.tube(part, m["Trim"], (x, 0.52, 0.71), (x, 0.57, 1.16), 0.016, 6)       # cyclic stick
        bk.box(part, m["Trim"], (x, 0.57, 1.20), (0.035, 0.05, 0.09))             # its grip
        bk.tube(part, m["Trim"], (x - 0.29, 0.28, 0.80), (x - 0.27, 0.62, 0.90), 0.018, 6)   # collective
        for px in (-0.09, 0.09):
            bk.box(part, m["Trim"], (x + px, 1.16, 0.74), (0.07, 0.03, 0.12), rot=(math.radians(-30), 0, 0))  # pedals
    # Rear bench.
    bk.box(part, m["Trim"], (0, -0.78, 0.80), (1.06, 0.42, 0.22))
    bk.box(part, im, (0, -0.76, 0.94), (1.22, 0.46, 0.10))
    bk.box(part, im, (0, -1.02, 1.30), (1.22, 0.09, 0.60), rot=(math.radians(-10), 0, 0))
    # Instrument panel with a glare shield, a centre pedestal down to the floor.
    bk.box(part, m["Trim"], (0, 1.30, 1.17), (1.00, 0.06, 0.26), rot=(math.radians(18), 0, 0))
    bk.box(part, im, (0, 1.34, 1.315), (0.92, 0.24, 0.03))
    bk.box(part, im, (0, 1.12, 0.92), (0.24, 0.40, 0.48))
    for sx in (-1, 1):
        for k in range(3):
            x = sx * (0.20 + k * 0.13)
            bk.tube(part, m["Chrome"], (x, 1.262, 1.20), (x, 1.258, 1.19), 0.042, 8)      # instrument bezels


# ------------------------------------------------------------------ cowl ---

def cowl_details(surf, part, m):
    for sx in (-1, 1):
        # Engine air intakes on the cowling's flanks, louvred exhaust grilles behind.
        bk.patch(surf, part, m["Trim"], bk.rect(0.42, 0.14, 0.4), (sx * 0.2, -0.30, 2.30), (-sx, 0, 0), (0, 0, 1),
                 lift=0.004, grid=(4, 2), kind=bk.GRILLE_SLATS)
        bk.patch(surf, part, m["Trim"], bk.rect(0.30, 0.10), (sx * 0.2, -1.55, 2.25), (-sx, 0, 0), (0, 0, 1),
                 lift=0.004, grid=(3, 2), kind=bk.GRILLE_SLATS)
    # The exhaust: a short stack out of the back of the cowling, angled up.
    bk.tube(part, m["Trim"], (0, -1.95, 2.30), (0, -2.30, 2.46), 0.11, 12)
    bk.tube(part, m["Interior"], (0, -2.30, 2.46), (0, -2.31, 2.465), 0.085, 12)
    # Mast, its fairing and the swashplate.
    bk.tube(part, m["Trim"], (0, MAST_Y, 2.40), (0, MAST_Y, HUB_Z - 0.05), 0.075, 12)
    rings = [[(r * math.cos(2 * math.pi * k / 16), MAST_Y + r * math.sin(2 * math.pi * k / 16), z) for k in range(16)]
             for (z, r) in ((2.38, 0.27), (2.44, 0.23), (2.50, 0.16), (2.54, 0.10))]
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_end=True, inside=(0, MAST_Y, 2.2))
    bk.tube(part, m["Chrome"], (0, MAST_Y, 2.60), (0, MAST_Y, 2.66), 0.17, 16)


# ------------------------------------------------------------------- tail ---

def stab_point(x, s, t):
    c = 0.42 - 0.06 * min(abs(x) / 1.0, 1.0)
    le = -4.45 - 0.04 * min(abs(x) / 1.0, 1.0)
    return (x, le - s * c, 1.46 + t * c)


def build_stab(part, m):
    for side in (-1, 1):
        rings = [foil_ring(0.0, 1.0, 6, 5, 0.11, 0.0, lambda s, t, xx=x * side: stab_point(xx, s, t))
                 for x in (0.0, 0.3, 0.6, 0.85, 1.0)]
        ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
        # Endplate: a small swept vertical fin at the tip.
        rings = []
        for z in (1.28, 1.46, 1.64, 1.72):
            f = (z - 1.28) / 0.44
            le = lerp(-4.42, -4.58, f)
            c = lerp(0.40, 0.26, f)
            rings.append(foil_ring(0.0, 1.0, 5, 4, 0.10, 0.0,
                                   lambda s, t, le=le, c=c, z=z: (side * 1.02 + t * c, le - s * c, z)))
        ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)


def fin_point(z, s, t):
    f = (z - 1.30) / (2.62 - 1.30)
    le = lerp(-5.62, -6.18, f)
    te = lerp(-6.48, -6.62, f)
    c = le - te
    return (t * c, le - s * c, z)


def build_fin(part, m):
    rings = [foil_ring(0.0, 1.0, 7, 6, 0.12, 0.0, lambda s, t, zz=z: fin_point(zz, s, t))
             for z in (1.30, 1.55, 1.85, 2.15, 2.40, 2.56, 2.62)]
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    # Ventral fin under the boom with a tail skid.
    rings = []
    for z in (1.40, 1.20, 1.02, 0.96):
        f = (1.40 - z) / 0.44
        le = lerp(-5.95, -6.18, f)
        c = lerp(0.52, 0.30, f)
        rings.append(foil_ring(0.0, 1.0, 5, 4, 0.10, 0.0, lambda s, t, le=le, c=c, z=z: (t * c, le - s * c, z)))
    ring_loft(part, rings, lambda i, j: m["Paint"], cap_start=True, cap_end=True)
    sweep(part, m["Frame"], [(0, -6.05, 0.99), (0, -6.30, 0.90), (0, -6.52, 0.93)], 0.022, 6)
    # Tail rotor gearbox and shaft on the fin's left side.
    bk.box(part, m["Paint"], (-0.10, TR[1], TR[2]), (0.16, 0.32, 0.24), bevel=0.05)
    bk.tube(part, m["Trim"], (-0.16, TR[1], TR[2]), (TR[0] + 0.04, TR[1], TR[2]), 0.04, 10)


# ------------------------------------------------------------------ skids ---

def build_skids(part, m):
    fr = m["Frame"]
    for sx in (-1, 1):
        x = sx * SKID_X
        pts = [(x, SKID_BACK, 0.0), (x, -0.6, 0.0), (x, 0.2, 0.0), (x, 0.9, 0.0), (x, SKID_TOE, 0.0),
               (x, 1.46, 0.025), (x, 1.58, 0.085), (x, 1.67, 0.17), (x, 1.72, 0.27), (x, 1.735, 0.32)]
        sweep(part, fr, pts, 0.04, 10)
        # Wear shoes under the skids.
        for y in (-0.9, 0.9):
            bk.box(part, m["Trim"], (x, y, -0.036), (0.05, 0.42, 0.016))
    for y in CROSS_Y:
        pts = [(-SKID_X, y, 0.0)]
        for k in range(1, 7):
            a = k / 6 * math.pi / 2
            pts.append((-(SKID_X - 0.48 * (1 - math.cos(a))), y, 0.60 * math.sin(a) + 0.03 * (k / 6)))
        pts += [(-0.25, y, 0.635), (0.25, y, 0.635)]
        for k in range(6, 0, -1):
            a = k / 6 * math.pi / 2
            pts.append(((SKID_X - 0.48 * (1 - math.cos(a))), y, 0.60 * math.sin(a) + 0.03 * (k / 6)))
        pts.append((SKID_X, y, 0.0))
        sweep(part, fr, pts, 0.045, 10)
    # Boarding steps on the front cross tube, by the doors.
    for sx in (-1, 1):
        bk.box(part, m["Trim"], (sx * 0.86, CROSS_Y[0] - 0.02, 0.48), (0.26, 0.14, 0.02))


# ------------------------------------------------------------------ rotors ---

def build_main_rotor(m):
    part = bk.Part("MainRotor", [])
    z = HUB_Z
    bk.box(part, m["Trim"], (0, 0, z), (0.70, 0.20, 0.13), bevel=0.03)                  # teetering yoke
    bk.tube(part, m["Chrome"], (0, 0, z + 0.06), (0, 0, z + 0.14), 0.08, 12)           # mast nut
    for sx in (-1, 1):
        bk.box(part, m["Chrome"], (sx * 0.43, 0, z), (0.24, 0.13, 0.09), bevel=0.02)  # blade grips
        bk.tube(part, m["Chrome"], (sx * 0.14, 0.11, 2.64), (sx * 0.20, 0.11, z - 0.04), 0.012, 6)  # pitch links
    for side in (-1, 1):
        rs = (ROOT_R, 0.9, 1.6, 2.4, 3.2, 4.0, 4.55, 4.70, 4.80, 4.90, 4.98, ROTOR_R)
        rings = []
        tips = []
        for r in rs:
            f = (r - ROOT_R) / (ROTOR_R - ROOT_R)
            c = 0.31 if r < 4.80 else lerp(0.31, 0.17, (r - 4.80) / (ROTOR_R - 4.80))
            pitch = math.radians(lerp(9.0, 3.0, f))

            def blade(s, t, r=r, c=c, pitch=pitch):
                u = (0.25 - s) * c                 # + = toward the leading edge
                v = t * c
                a = V((0, side * math.cos(pitch), math.sin(pitch)))
                n = V((0, -side * math.sin(pitch), math.cos(pitch)))
                p = V((side * r, 0, z)) + a * u + n * v
                return tuple(p)
            rings.append(foil_ring(0.0, 1.0, 5, 5, 0.11, 0.0, blade))
            tips.append(r > 4.62)
        ring_loft(part, rings, lambda i, j, tips=tips: m["PropTip"] if tips[i] else m["Trim"],
                  cap_start=True, cap_end=True)
    obj = part.to_object(math.radians(40))
    place_object(obj, V((0, MAST_Y, HUB_Z)), z_axis=(0, 0, 1))
    return obj


def build_rotor_disc(m):
    """The flat ring the blades blur into (helicopter.gd fades it in with rpm)."""
    part = bk.Part("RotorDisc", [])
    annulus(part, m["RotorBlur"], ROOT_R, ROTOR_R, 48,
            lambda r, a: (r * math.cos(a), MAST_Y + r * math.sin(a), HUB_Z + 0.02))
    obj = part.to_object()
    place_object(obj, V((0, MAST_Y, HUB_Z + 0.02)), z_axis=(0, 0, 1))
    return obj


def build_tail_rotor(m):
    part = bk.Part("TailRotor", [])
    x0, y0, z0 = TR
    bk.tube(part, m["Trim"], (x0 + 0.03, y0, z0), (x0 - 0.06, y0, z0), 0.06, 10)           # hub
    for side in (-1, 1):
        rings = []
        tips = []
        for r in (0.10, 0.30, 0.50, 0.64, 0.70, TR_R):
            f = (r - 0.10) / (TR_R - 0.10)
            c = 0.13 if r < 0.70 else 0.10
            pitch = math.radians(lerp(14.0, 8.0, f))

            def blade(s, t, r=r, c=c, pitch=pitch):
                u = (0.25 - s) * c
                v = t * c
                a = V((math.sin(pitch), -side * math.cos(pitch), 0.0))
                n = V((math.cos(pitch), side * math.sin(pitch), 0.0))
                p = V((x0 - 0.02, y0, z0 + side * r)) + a * u + n * v
                return tuple(p)
            rings.append(foil_ring(0.0, 1.0, 4, 4, 0.12, 0.0, blade))
            tips.append(r > 0.62)
        ring_loft(part, rings, lambda i, j, tips=tips: m["PropTip"] if tips[i] else m["Trim"],
                  cap_start=True, cap_end=True)
    obj = part.to_object(math.radians(40))
    place_object(obj, V(TR), x_axis=(1, 0, 0))
    return obj


def build_tail_disc(m):
    part = bk.Part("TailDisc", [])
    x0, y0, z0 = TR
    annulus(part, m["TailBlur"], 0.10, TR_R, 24, lambda r, a: (x0 - 0.04, y0 + r * math.cos(a), z0 + r * math.sin(a)))
    obj = part.to_object()
    place_object(obj, V((x0 - 0.04, y0, z0)), x_axis=(1, 0, 0))
    return obj


# ---------------------------------------------------------------- details ---

def details(surf, front, body, tail, m):
    # Search / landing light under the nose: a housing and the lamp.
    bk.patch(surf, front, m["Trim"], bk.ellipse(0.24, 0.24), (0.0, 1.70, 0.0), (0, 0, 1), (0, 1, 0), lift=0.004, grid=4)
    bk.patch(surf, front, m["Headlight"], bk.ellipse(0.18, 0.18), (0.0, 1.70, 0.0), (0, 0, 1), (0, 1, 0), lift=0.008,
             grid=4, kind=bk.LAMP)
    # Door handles.
    for sx in (-1, 1):
        for y, part in ((0.20, front), (-0.22, body)):
            x = side_x(y, 1.02)
            bk.box(part, m["Chrome"], (sx * (x + 0.006), y, 1.02), (0.02, 0.14, 0.03), bevel=0.008, segments=1)
    # Pitot tube on the nose, a whip antenna under the boom, a blade antenna on top.
    bk.tube(front, m["Chrome"], (0.10, 1.95, 1.04), (0.12, 2.20, 1.04), 0.010, 6)
    bk.tube(tail, m["Trim"], (0, -3.2, ZB(-3.2) + 0.02), (0, -3.6, ZB(-3.6) - 0.35), 0.008, 5)
    bm = bmesh.new()
    base = [(-2.70, ZT(-2.70) - 0.01), (-2.88, ZT(-2.88) - 0.01), (-2.86, ZT(-2.86) + 0.16), (-2.80, ZT(-2.80) + 0.16)]
    vs = [bm.verts.new((dx, y, z)) for dx in (-0.005, 0.005) for (y, z) in base]
    for q in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([vs[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(tail, bm, m["Trim"])
    # Lights: red / green on the stabiliser endplates, white strobes on the
    # fin and the tail, a red beacon on top of the cowling and one underneath.
    for sx, kind in ((-1, NAV_RED), (1, NAV_GREEN)):
        bk.box(tail, m["NavLight"], (sx * 1.075, -4.43, 1.46), (0.05, 0.10, 0.06), bevel=0.012, segments=1, kind=kind)
    bk.box(tail, m["NavLight"], (0, -6.66, 2.30), (0.05, 0.08, 0.06), kind=NAV_STROBE)
    bk.box(tail, m["NavLight"], (0, -6.20, 2.645), (0.06, 0.12, 0.05), kind=NAV_STROBE)
    bk.box(body, m["NavLight"], (0, -1.30, ZC(-1.30) + 0.02), (0.08, 0.14, 0.06), bevel=0.015, segments=1, kind=NAV_BEACON)
    bk.box(front, m["NavLight"], (0, 0.30, ZB(0.30) - 0.02), (0.08, 0.14, 0.05), bevel=0.015, segments=1, kind=NAV_BEACON)


def livery():
    """The Stripes mesh: a cheat line along the cabin, a band down the boom
    and one across the fin."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    bands = [(bk.stations(1.28, -1.62, 0.1, keep=[1.28, -1.62]), (0.17, 0.25)),
             (bk.stations(-2.55, -5.80, 0.2, keep=[-2.55, -5.80]), (0.40, 0.66))]
    for ys, (f0, f1) in bands:
        for sx in (-1, 1):
            rings = []
            for y in ys:
                zb, zt = ZB(y), ZT(y)
                ring = []
                for k in range(4):
                    z = lerp(zb, zt, lerp(f0, f1, k / 3))
                    # Out along the surface's normal in the section (the boom is round).
                    dz = 0.004
                    nx, nz = -(side_x(y, z + dz) - side_x(y, z - dz)), 2 * dz
                    ln = math.hypot(nx, nz)
                    nx, nz = (nz / ln, nx / ln) if ln > 0 else (1.0, 0.0)
                    ring.append((sx * (side_x(y, z) + 0.006 * nx), y, z + 0.006 * nz))
                rings.append(ring)
            ring_loft(part, rings, lambda i, j: mat, close=False, inside=(0.0, -2.0, 1.4))
    for sx in (-1, 1):
        rings = []
        for z in (2.02, 2.10, 2.18):
            ring = []
            for s in (0.0, 0.3, 0.6, 0.9):
                x, y, zz = fin_point(z, s, 0.0)
                # (the fin's surface at this chord station, plus a hair)
                yt = 5.0 * 0.12 * (0.2969 * math.sqrt(max(s, 0.0)) - 0.1260 * s - 0.3516 * s * s + 0.2843 * s ** 3 - 0.1036 * s ** 4)
                c = fin_point(z, 0.0, 0.0)[1] - fin_point(z, 1.0, 0.0)[1]
                ring.append((sx * (yt * c + 0.004), y, zz))
            rings.append(ring)
        ring_loft(part, rings, lambda i, j: mat, close=False, inside=(0.0, -6.2, 2.1))
    return part


# ------------------------------------------------------------------ build ---

def build():
    bk.reset_scene()
    m = materials()
    body = bk.Part("HeliBody", [])
    ys = build_fuselage(body, m)
    build_cowl(body, m)
    surf = bk.Surface([body])
    cowl_details(surf, body, m)
    cabin_interior(body, m, ys)
    tail = bk.split_part(body, "TailBoom", lambda c: c.y < -2.45 and c.z > 0.9)
    # The cabin in two meshes, split along the door seam at the B-pillar (a
    # dark shut line hides the crease), so a dent pass only processes the
    # half it reaches (ART_BIBLE.md §14).
    front = bk.split_part(body, "CabinFront", lambda c: c.y > 0.0 and c.z < 2.15)
    build_stab(tail, m)
    build_fin(tail, m)
    skids = bk.Part("Skids", list(body.mats))
    build_skids(skids, m)
    surf = bk.Surface([body, front, tail])
    details(surf, front, body, tail, m)
    objs = [front.to_object(SMOOTH), body.to_object(SMOOTH), tail.to_object(SMOOTH), skids.to_object(SMOOTH)]
    objs.append(build_main_rotor(m))
    objs.append(build_rotor_disc(m))
    objs.append(build_tail_rotor(m))
    objs.append(build_tail_disc(m))
    objs.append(livery().to_object(SMOOTH))
    bk.export(objs, "heli_body.glb")


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
