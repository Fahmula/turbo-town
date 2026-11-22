"""Generates the speedboat (boat_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_boat.py

Design language (ART_BIBLE.md §12): a generic, unbranded sport runabout
about 6 m long and 2.4 m across, the kind you see pulling water-skiers. A
deep-V planing hull with a sharp chine and a raked stem; a white bottom, a
dark boot stripe along the chine, painted topsides (the garage colour) under
a black rub rail and a white gunwale cap; a closed non-skid foredeck with a
chrome bow rail; a wrap-round windscreen with a chrome top rail; an open
cockpit with a helm console (on the left, like every vehicle in the game),
a passenger console, two bucket seats and a rear bench in cream vinyl; swim
platforms either side of a big black outboard motor that turns as you steer.
Real proportions: the sole sits 0.24 m above the waterline, the gunwale
0.8-1.15 m, the windscreen top about 1.2 m.

Conventions (Blender Z-up, front = +Y = Godot -Z, right = +X):
  * Origin on the centre line at the static waterline (z = 0), at y = 0
    (about the centre of buoyancy). The game floats the boat with its origin
    on the sea (Boat, scenes/vehicles/boat.tscn).
  * Objects (their node names are a code contract, see boat.gd):
      Hull        the outer shell, gunwale and foredeck (deformable)
      Cockpit     liner, sole, bulkheads, consoles, seats, bench, wheel
      Windscreen  the glass (material Glass) and its frame
      FittingsBow     bow rail, bow cleat and light
      FittingsStern   midship and stern cleats, stern light pole, swim
                  platforms, ladder, grab handles
      Outboard    the motor; origin on its steering axis (turns about its
                  local Z = Godot local Y)
      Propeller   child of Outboard; origin on the shaft, spins about its
                  local Y (Godot local Z, the fore-aft axis)
      Stripes     the hull graphic (material Stripe), hidden unless picked
  * Materials: the vehicle set (Paint, Glass, Trim, Chrome, Interior) plus
    Gelcoat (white glossy hull and deck mouldings), Deck (non-skid walking
    surfaces), Vinyl (cream upholstery), Cowl (the motor's glossy black) and
    NavLight (UV kind 1 red, port; 2 green, starboard; 5 steady white, the
    stern light; decoded by nav_light.gdshader).

Prints the numbers boat.tscn needs (Godot space: x, z, -y): the hull's
convex collision points and the buoyancy sample points with their areas.
"""
import math
import os
import sys

import bmesh
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402
from make_plane import place_object, ring_loft  # noqa: E402
from make_heli import sweep  # noqa: E402

V = mathutils.Vector

# ----------------------------------------------------------------- layout ---
STERN, BOW = -2.90, 3.12
SOLE = 0.24                    # cockpit floor (z)
CP_BACK, CP_FRONT = -2.40, 0.50
CAP = 0.24                     # gunwale cap width round the cockpit
CROWN = 0.05                   # foredeck camber
PIVOT = (0.0, -3.00, 0.40)     # outboard steering axis
PROP = (0.0, -3.47, -0.50)     # propeller hub

# Hull lines by station y: sheer half width and height, chine half width and
# height, keel height.
SW = bk.curve([(-2.90, 1.10), (-2.20, 1.16), (-1.20, 1.20), (-0.20, 1.20), (0.80, 1.16), (1.60, 1.05),
               (2.20, 0.86), (2.65, 0.60), (2.95, 0.30), (3.12, 0.0)])
ZS = bk.curve([(-2.90, 0.78), (-1.60, 0.80), (-0.20, 0.84), (0.90, 0.90), (1.90, 0.99), (2.60, 1.08), (3.12, 1.15)])
CW = bk.curve([(-2.90, 0.97), (-1.60, 1.01), (-0.20, 1.01), (0.80, 0.95), (1.60, 0.80), (2.20, 0.58), (2.65, 0.34),
               (2.95, 0.12), (3.12, 0.0)])
ZC = bk.curve([(-2.90, -0.12), (-1.00, -0.11), (0.40, -0.07), (1.30, 0.02), (2.00, 0.17), (2.60, 0.36), (3.12, 0.62)])
ZK = bk.curve([(-2.90, -0.40), (-1.60, -0.45), (-0.20, -0.46), (0.80, -0.42), (1.60, -0.30), (2.20, -0.10),
               (2.65, 0.14), (2.95, 0.40), (3.12, 0.62)])

SMOOTH = math.radians(40)
NAV_RED, NAV_GREEN, NAV_WHITE = 1, 2, 5


def lerp(a, b, t):
    return a + (b - a) * t


def gx(y):
    """The gunwale cap's inner edge (half width)."""
    return max(SW(y) - CAP, 0.0)


def deck_z(y, x=0.0):
    """The top of the deck or gunwale cap at (x, y)."""
    g = gx(y)
    base = ZS(y) + 0.045
    if g <= 0.01 or abs(x) >= g:
        return base
    return base + CROWN * (1.0 - (abs(x) / g) ** 2)


# ------------------------------------------------------------- materials ---

def materials():
    m = bk.vehicle_materials((0.12, 0.30, 0.62))
    m["Gelcoat"] = bk.material("Gelcoat", (0.92, 0.92, 0.9), rough=0.22)
    m["Deck"] = bk.material("Deck", (0.80, 0.79, 0.76), rough=0.78)
    m["Vinyl"] = bk.material("Vinyl", (0.88, 0.85, 0.78), rough=0.5)
    m["Cowl"] = bk.material("Cowl", (0.11, 0.11, 0.12), rough=0.28)
    m["NavLight"] = bk.material("NavLight", (0.9, 0.9, 0.9), rough=0.2, emission=(1, 1, 1), strength=1.0)
    return m


# ------------------------------------------------------------------ hull ---

def top(y, t):
    """A point on the topsides: t = 0 at the chine lip, 1 under the rub rail
    (right half, (x, z)). They flare out a little as they rise."""
    x0, z0 = CW(y) + 0.045, ZC(y) + 0.008
    x1, z1 = SW(y) - 0.008, ZS(y) - 0.05
    x = lerp(x0, x1, t) + 0.025 * math.sin(math.pi * t) * min(SW(y) / 0.6, 1.0)
    return (x, lerp(z0, z1, t))


def bottom(y, t):
    """A point on the bottom panel from the keel flat (0) to the chine (1);
    slightly convex."""
    cw, zk, zc = CW(y), ZK(y), ZC(y)
    kx = min(0.05, cw * 0.4)
    x = lerp(kx, cw - 0.015, t)
    z = lerp(zk + 0.012, zc - 0.006, t) - 0.018 * math.sin(math.pi * t) * min(cw / 0.5, 1.0)
    return (x, z)


def section(_i, y):
    """Right half, keel -> chine -> topsides -> rub rail -> gunwale ->
    deck centre: 19 points."""
    sw, zs, cw, zc, zk = SW(y), ZS(y), CW(y), ZC(y), ZK(y)
    g = gx(y)
    dz = zs + 0.045
    pts = [(0.0, zk), (min(0.05, cw * 0.4), zk + 0.012), bottom(y, 0.33), bottom(y, 0.66),
           (max(cw - 0.015, 0.0), zc - 0.006), (cw, zc), (cw + 0.045 * min(cw / 0.3, 1.0), zc + 0.008),
           top(y, 0.16), top(y, 0.45), top(y, 0.75),
           (max(sw - 0.008, 0.0), zs - 0.05), (sw + 0.03, zs - 0.035), (sw + 0.03, zs - 0.005),
           (max(sw - 0.01, 0.0), zs + 0.012), (max(sw - 0.05, 0.0), zs + 0.035),
           (g, dz), (g * 0.62, dz + CROWN * 0.6), (g * 0.3, dz + CROWN * 0.9), (0.0, dz + CROWN)]
    return pts


def in_cockpit(y):
    return CP_BACK < y < CP_FRONT


def hull_material(m):
    def f(_i, j, y0, y1):
        ym = (y0 + y1) * 0.5
        if j <= 5:
            return m["Gelcoat"]
        if j == 6:
            return m["Trim"]
        if j <= 9:
            return m["Paint"]
        if j <= 12:
            return m["Trim"]
        if j <= 14:
            return m["Gelcoat"]
        return None if in_cockpit(ym) else m["Deck"]
    return f


def build_hull(part, m):
    ys = bk.stations(BOW, STERN, 0.14, keep=[CP_FRONT, CP_BACK, 0.0], refine=[(2.6, 3.12, 0.07)])
    rings = bk.loft(part, ys, section, hull_material(m))
    # The transom: strips across between the last station's two halves.
    right, left = rings[-1]
    mats = hull_material(m)
    for j in range(len(right) - 1):
        quad = [right[j], right[j + 1], left[j + 1], left[j]]
        if len(set(quad)) < 3:
            continue
        mat = mats(len(rings) - 1, j, STERN, STERN)
        if mat is None:
            mat = m["Deck"]
        try:
            f = part.bm.faces.new(list(dict.fromkeys(quad)))
        except ValueError:
            continue
        f.material_index = part.slot(mat if j > 0 else m["Gelcoat"])
    return ys


# --------------------------------------------------------------- cockpit ---

def liner_ring(y):
    """Left cap edge -> down the liner -> across the sole -> up to the right
    cap edge (3D points)."""
    g = gx(y)
    zg = ZS(y) + 0.045
    side = [(g, zg), (g - 0.015, zg - 0.03), (g - 0.05, zg - 0.10), (g - 0.065, SOLE + 0.30),
            (g - 0.10, SOLE + 0.04), (g - 0.13, SOLE)]
    left = [(-x, y, z) for (x, z) in side]
    right = [(x, y, z) for (x, z) in reversed(side)]
    return left + [(0.0, y, SOLE)] + right


def liner_material(m):
    # Segments: 0 cap round, 1 coaming, 2 side panel (vinyl), 3 lower liner,
    # 4 sole edge, 5-6 the sole, then mirrored.
    names = ["Gelcoat", "Gelcoat", "Vinyl", "Gelcoat", "Gelcoat", "Deck", "Deck", "Gelcoat", "Gelcoat", "Vinyl",
             "Gelcoat", "Gelcoat"]
    return lambda _i, j: m[names[j]]


def bulkhead(part, mat, y, facing):
    """Closes the cockpit at station y: the liner's U and the deck above it."""
    ring = liner_ring(y)
    g = gx(y)
    zg = ZS(y) + 0.045
    deck = [(g * 0.62, y, zg + CROWN * 0.6), (g * 0.3, y, zg + CROWN * 0.9), (0.0, y, zg + CROWN),
            (-g * 0.3, y, zg + CROWN * 0.9), (-g * 0.62, y, zg + CROWN * 0.6)]
    poly = ring + deck
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in poly]
    f = bm.faces.new(vs)
    bm.normal_update()
    if f.normal.y * facing < 0:
        f.normal_flip()
    bk._append(part, bm, mat)


def console(part, m, sx, wheel):
    """A dash console against the front bulkhead on side sx (-1 = helm)."""
    x_in, x_out = 0.30 * sx, (gx(0.3) - 0.07) * sx
    cx, w = (x_in + x_out) * 0.5, abs(x_out - x_in)
    # Lower part with a toe kick, the upper part overhanging the feet.
    bk.box(part, m["Gelcoat"], (cx, 0.40, SOLE + 0.13), (w, 0.20, 0.26), bevel=0.02)
    bk.box(part, m["Gelcoat"], (cx, 0.28, SOLE + 0.40), (w, 0.44, 0.32), bevel=0.03)
    # The sloping dash face toward the seat and the top.
    bm = bmesh.new()
    prof = [(0.06, SOLE + 0.24), (0.06, SOLE + 0.48), (0.24, SOLE + 0.60), (0.50, SOLE + 0.62), (0.50, SOLE + 0.24)]
    a = [bm.verts.new((x_in, y, z)) for (y, z) in prof]
    b = [bm.verts.new((x_out, y, z)) for (y, z) in prof]
    n = len(prof)
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new([a[k], a[k1], b[k1], b[k]])
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Gelcoat"])
    # Dark dash panel on the slope with two gauges (helm) or a glovebox.
    slope = V((0.0, 0.18, 0.12)).normalized()
    nrm = V((0.0, -0.12, 0.18)).normalized()
    c = V((cx, 0.15, SOLE + 0.545)) + nrm * 0.006
    bk.box(part, m["Interior"], tuple(c), (w - 0.08, 0.19, 0.012), rot=(math.atan2(0.12, 0.18), 0, 0))
    if wheel:
        for gxo in (-0.09, 0.09):
            g = V((cx + gxo * sx, 0.15, SOLE + 0.545)) + nrm * 0.014
            bk.box(part, m["Chrome"], tuple(g), (0.075, 0.075, 0.01), bevel=0.03, segments=3,
                   rot=(math.atan2(0.12, 0.18), 0, 0))
        # Where the seated driver's hands reach (boat.tscn: steering_wheel).
        steering_wheel(part, m, (cx, -0.10, SOLE + 0.74))
        # Throttle lever on the outer side of the console.
        bk.box(part, m["Trim"], (x_out - 0.02 * sx, 0.18, SOLE + 0.66), (0.06, 0.12, 0.06), bevel=0.015)
        bk.tube(part, m["Chrome"], (x_out - 0.02 * sx, 0.18, SOLE + 0.68), (x_out - 0.02 * sx, 0.10, SOLE + 0.86), 0.01, 6)
        bk.box(part, m["Trim"], (x_out - 0.02 * sx, 0.10, SOLE + 0.87), (0.05, 0.03, 0.03), bevel=0.01)
    else:
        bk.tube(part, m["Chrome"], (x_in + 0.05 * sx, 0.06, SOLE + 0.58), (x_out - 0.05 * sx, 0.06, SOLE + 0.58), 0.012, 6)
    return (cx, x_in, x_out)


def steering_wheel(part, m, at):
    """A three-spoke wheel facing the driver, the top leaning away 28 deg."""
    tilt = math.radians(28)
    c = V(at)
    # Ring in the XZ plane (bk.torus), turned so its face looks back and up.
    bk.torus(part, m["Interior"], tuple(c), 0.165, 0.016, seg=20, tseg=6, tilt=-tilt, axis="X")
    rot = mathutils.Matrix.Rotation(-tilt, 3, "X")
    hub = c + rot @ V((0.0, 0.02, 0.0))
    bk.box(part, m["Chrome"], tuple(hub), (0.06, 0.03, 0.06), bevel=0.02, rot=(-tilt, 0, 0))
    for ang in (math.pi * 0.5, math.pi * 1.17, math.pi * 1.83):
        p = c + rot @ V((math.cos(ang) * 0.155, 0.0, math.sin(ang) * 0.155))
        bk.tube(part, m["Interior"], tuple(hub), tuple(p), 0.011, 6)
    # Column down into the dash.
    col_end = c + rot @ V((0.0, 0.36, 0.0))
    bk.tube(part, m["Trim"], tuple(hub), tuple(col_end), 0.022, 8)


def bucket_seat(part, m, x, y, z):
    """A bucket seat: cushion top at z, front edge at y."""
    back = math.radians(12)
    bk.box(part, m["Vinyl"], (x, y - 0.23, z - 0.05), (0.50, 0.46, 0.11), bevel=0.04)
    # Bolsters along the cushion sides.
    for s in (-1, 1):
        bk.box(part, m["Vinyl"], (x + s * 0.22, y - 0.25, z - 0.01), (0.07, 0.40, 0.07), bevel=0.03)
    by, bz = y - 0.50, z + 0.26
    bk.box(part, m["Vinyl"], (x, by, bz), (0.50, 0.11, 0.56), bevel=0.045, rot=(back, 0, 0))
    for s in (-1, 1):
        bk.box(part, m["Vinyl"], (x + s * 0.22, by + 0.05, bz + 0.02), (0.07, 0.07, 0.46), bevel=0.03,
               rot=(back, 0, 0))
    # Base and pedestal.
    bk.box(part, m["Interior"], (x, y - 0.25, z - 0.13), (0.40, 0.36, 0.05), bevel=0.01)
    bk.tube(part, m["Chrome"], (x, y - 0.25, SOLE), (x, y - 0.25, z - 0.15), 0.045, 12)
    bk.box(part, m["Interior"], (x, y - 0.25, SOLE + 0.01), (0.30, 0.30, 0.02), bevel=0.005)


def build_cockpit(part, m):
    ys = [y for y in bk.stations(CP_FRONT, CP_BACK, 0.14, keep=[CP_FRONT, CP_BACK])]
    rings = [liner_ring(y) for y in ys]
    ring_loft(part, rings, liner_material(m), close=False, inside=(0.0, (CP_FRONT + CP_BACK) * 0.5, -1.0))
    bulkhead(part, m["Gelcoat"], CP_FRONT, -1)
    bulkhead(part, m["Gelcoat"], CP_BACK, 1)
    # A door into the cuddy under the foredeck, between the consoles.
    bk.box(part, m["Interior"], (0.0, CP_FRONT - 0.008, SOLE + 0.36), (0.40, 0.02, 0.56), bevel=0.04)
    bk.box(part, m["Chrome"], (0.12, CP_FRONT - 0.025, SOLE + 0.40), (0.02, 0.02, 0.10), bevel=0.008)
    console(part, m, -1, True)
    console(part, m, 1, False)
    bucket_seat(part, m, -0.56, -0.12, SOLE + 0.40)
    bucket_seat(part, m, 0.56, -0.12, SOLE + 0.40)
    # Rear bench across the stern, its back against the aft bulkhead.
    w = gx(CP_BACK + 0.25) * 2.0 - 0.30
    bk.box(part, m["Gelcoat"], (0.0, CP_BACK + 0.25, SOLE + 0.17), (w, 0.48, 0.34), bevel=0.03)
    bk.box(part, m["Vinyl"], (0.0, CP_BACK + 0.26, SOLE + 0.40), (w - 0.02, 0.50, 0.12), bevel=0.045)
    bk.box(part, m["Vinyl"], (0.0, CP_BACK + 0.06, SOLE + 0.66), (w - 0.02, 0.12, 0.42), bevel=0.045,
           rot=(math.radians(-10), 0, 0))
    # Side pockets' dark openings along the liner.
    for s in (-1, 1):
        x = (gx(-1.2) - 0.07) * s
        bk.box(part, m["Interior"], (x, -1.25, SOLE + 0.20), (0.02, 1.1, 0.16), bevel=0.02)


# ------------------------------------------------------------ windscreen ---

def screen_path(n_side=4, n_corner=8, n_front=6):
    """The windscreen's foot in plan (x, y), left side aft end -> round the
    front -> right side aft end, with its inward normal."""
    pts = []
    cx, cy, rx, ry = 0.60, 0.36, 0.39, 0.44
    xs = 0.99
    for k in range(n_side):
        pts.append((-xs, lerp(0.05, cy, k / n_side), (1.0, 0.0)))
    for k in range(n_corner):
        a = lerp(-math.pi * 0.5, 0.0, k / n_corner)
        x, y = -cx + rx * math.sin(a), cy + ry * math.cos(a)
        nx, ny = -math.sin(a) / rx, -math.cos(a) / ry
        ln = math.hypot(nx, ny)
        pts.append((x, y, (nx / ln, ny / ln)))
    for k in range(n_front + 1):
        pts.append((lerp(-cx, cx, k / n_front), cy + ry, (0.0, -1.0)))
    for k in range(1, n_corner + 1):
        a = lerp(0.0, math.pi * 0.5, k / n_corner)
        x, y = cx + rx * math.sin(a), cy + ry * math.cos(a)
        nx, ny = -math.sin(a) / rx, -math.cos(a) / ry
        ln = math.hypot(nx, ny)
        pts.append((x, y, (nx / ln, ny / ln)))
    for k in range(1, n_side + 1):
        pts.append((xs, lerp(cy, 0.05, k / n_side), (-1.0, 0.0)))
    return pts


def build_windscreen(m):
    part = bk.Part("Windscreen", [])
    path = screen_path()
    rows = 4
    rings = []
    tops = []
    for (x, y, (nx, ny)) in path:
        front = max(0.0, (y - 0.05) / 0.75)          # 0 at the aft ends, 1 round the front
        h = lerp(0.10, 0.36, bk.smoothstep(0.0, 0.55, front))
        lean = lerp(0.18, 0.62, abs(ny))             # sides lean in less than the front leans back
        base = V((x, y, deck_z(y, x) + 0.02))
        tip = base + V((nx * h * lean, ny * h * lean, h))
        rings.append([tuple(base.lerp(tip, r / rows)) for r in range(rows + 1)])
        tops.append(tip)
    # Rings run along the path: transpose into rows of points for the loft.
    strips = [[rings[i][r] for i in range(len(rings))] for r in range(rows + 1)]
    ring_loft(part, strips, lambda i, j: m["Glass"], close=False, inside=(0.0, -0.4, 0.5))
    # Chrome top rail and a dark gasket along the foot.
    sweep(part, m["Chrome"], [tuple(t + V((0, 0, 0.012))) for t in tops], 0.016, seg=8)
    sweep(part, m["Trim"], [(x, y, deck_z(y, x) + 0.018) for (x, y, _n) in path], 0.022, seg=6)
    return part


# -------------------------------------------------------------- fittings ---

def build_fittings(part, m):
    # Bow rail on stanchions, joined round the stem.
    rail_ys = [1.30, 1.55, 1.85, 2.15, 2.40, 2.62, 2.80, 2.93]
    def rail_pt(y, s):
        return (s * max(SW(y) - 0.11, 0.0), y, deck_z(y, SW(y)) + 0.26)
    pts = [rail_pt(y, -1) for y in rail_ys] + [(0.0, 3.00, deck_z(3.0) + 0.26)] + [rail_pt(y, 1) for y in reversed(rail_ys)]
    sweep(part, m["Chrome"], pts, 0.014, seg=8)
    for y in (1.30, 1.95, 2.55):
        for s in (-1, 1):
            p = rail_pt(y, s)
            bk.tube(part, m["Chrome"], (p[0], p[1], deck_z(y, SW(y)) + 0.01), p, 0.012, 6)
            bk.box(part, m["Chrome"], (p[0], p[1], deck_z(y, SW(y)) + 0.01), (0.05, 0.05, 0.015), bevel=0.006)
    bk.tube(part, m["Chrome"], (0.0, 3.00, deck_z(3.0) + 0.0), (0.0, 3.00, deck_z(3.0) + 0.26), 0.012, 6)
    # Cleats: bow, midships and stern.
    def cleat(x, y, z, along=True):
        size = (0.035, 0.16, 0.025) if along else (0.16, 0.035, 0.025)
        bk.box(part, m["Chrome"], (x, y, z + 0.035), size, bevel=0.01)
        bk.box(part, m["Chrome"], (x, y, z + 0.012), (0.03, 0.05, 0.03), bevel=0.008)
    cleat(0.0, 2.55, deck_z(2.55))
    for s in (-1, 1):
        cleat(s * (SW(0.0) - 0.12), 0.0, deck_z(0.0, SW(0.0)))
        cleat(s * (SW(-2.68) - 0.12), -2.68, deck_z(-2.68, SW(-2.68)))
    # Bi-colour light on the bow: red to port, green to starboard.
    y = 2.72
    z = deck_z(y)
    bk.box(part, m["Trim"], (0.0, y, z + 0.03), (0.12, 0.08, 0.06), bevel=0.012)
    bk.box(part, m["NavLight"], (-0.032, y + 0.01, z + 0.06), (0.05, 0.07, 0.04), bevel=0.01, kind=NAV_RED)
    bk.box(part, m["NavLight"], (0.032, y + 0.01, z + 0.06), (0.05, 0.07, 0.04), bevel=0.01, kind=NAV_GREEN)
    # All-round white stern light on a pole at the starboard quarter.
    sx, sy = SW(-2.70) - 0.16, -2.70
    sz = deck_z(sy, sx)
    bk.box(part, m["Trim"], (sx, sy, sz + 0.02), (0.07, 0.07, 0.04), bevel=0.01)
    bk.tube(part, m["Chrome"], (sx, sy, sz + 0.02), (sx, sy, sz + 0.80), 0.012, 8)
    bk.box(part, m["NavLight"], (sx, sy, sz + 0.84), (0.05, 0.05, 0.07), bevel=0.02, segments=3, kind=NAV_WHITE)
    # Swim platforms either side of the motor, a boarding ladder on the right.
    for s in (-1, 1):
        x = s * 0.64
        bk.box(part, m["Gelcoat"], (x, STERN - 0.17, 0.10), (0.66, 0.36, 0.08), bevel=0.02)
        bk.box(part, m["Deck"], (x, STERN - 0.17, 0.145), (0.62, 0.32, 0.012), bevel=0.004)
        for xs in (x - 0.26, x + 0.26):
            bk.box(part, m["Gelcoat"], (xs, STERN - 0.05, 0.02), (0.05, 0.12, 0.14), bevel=0.01)
    for xs in (0.52, 0.76):
        bk.tube(part, m["Chrome"], (xs, STERN - 0.30, 0.15), (xs, STERN - 0.30, 0.42), 0.012, 6)
    bk.tube(part, m["Chrome"], (0.52, STERN - 0.30, 0.42), (0.76, STERN - 0.30, 0.42), 0.012, 6)
    # Grab handles on the gunwale beside the passenger and the bench.
    for (y0, y1) in ((-0.15, -0.55), (-1.95, -2.25)):
        for s in (-1, 1):
            x = s * (gx((y0 + y1) * 0.5) + 0.07)
            z = deck_z(y0, x)
            pts = [(x, y0, z), (x, y0 - 0.03, z + 0.06), (x, y1 + 0.03, z + 0.06), (x, y1, z)]
            sweep(part, m["Chrome"], pts, 0.011, seg=6)


# --------------------------------------------------------------- outboard ---

def rounded_ring(z, hw, yf, yb, n=16, power=3.0):
    """A superellipse in plan at height z: half width hw, from yf (front) to
    yb (back)."""
    cy, hy = (yf + yb) * 0.5, abs(yf - yb) * 0.5
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        x = hw * math.copysign(abs(c) ** (2.0 / power), c)
        y = cy + hy * math.copysign(abs(s) ** (2.0 / power), s)
        pts.append((x, y, z))
    return pts


def build_outboard(m):
    part = bk.Part("Outboard", [])
    px, py, pz = PIVOT
    # Transom bracket and swivel.
    bk.box(part, m["Trim"], (0.0, STERN - 0.05, 0.56), (0.30, 0.10, 0.34), bevel=0.02)
    bk.box(part, m["Cowl"], (0.0, py - 0.08, 0.40), (0.20, 0.18, 0.30), bevel=0.04, segments=3)
    # The cowling: horizontal rounded sections, a lower pan in Trim.
    secs = [(0.50, 0.19, -3.00, -3.52), (0.58, 0.215, -2.98, -3.58), (0.72, 0.225, -2.97, -3.62),
            (0.92, 0.23, -2.97, -3.64), (1.06, 0.22, -2.99, -3.62), (1.14, 0.19, -3.03, -3.56),
            (1.18, 0.13, -3.10, -3.48), (1.19, 0.04, -3.20, -3.36)]
    rings = [rounded_ring(z, hw, yf, yb) for (z, hw, yf, yb) in secs]
    ring_loft(part, rings, lambda i, j: m["Trim"] if i == 0 else m["Cowl"], cap_start=True, cap_end=True,
              inside=(0.0, -3.30, 0.85))
    # Leg: a streamlined shaft down to the gearcase, with the plate above it.
    leg = []
    for z in (0.52, 0.20, -0.10, -0.30, -0.46):
        ring = []
        for k in range(12):
            a = 2 * math.pi * k / 12
            ring.append((0.045 * math.sin(a), -3.18 - 0.12 * math.cos(a) - 0.02 * (math.cos(a) < 0), z))
        leg.append(ring)
    ring_loft(part, leg, lambda i, j: m["Cowl"], inside=(0.0, -3.18, 0.0))
    bk.box(part, m["Cowl"], (0.0, -3.20, -0.30), (0.26, 0.42, 0.018), bevel=0.008)
    # Gearcase torpedo along the shaft, and the skeg below it.
    torp = [(0.0, 0.0), (0.02, 0.04), (0.06, 0.062), (0.20, 0.068), (0.34, 0.06), (0.40, 0.045)]
    bm = bmesh.new()
    rings_t = []
    for (dy, r) in torp:
        rings_t.append([bm.verts.new((r * math.cos(2 * math.pi * k / 12), -3.00 - dy, PROP[2] + r * math.sin(2 * math.pi * k / 12)))
                        for k in range(12)])
    for i in range(len(rings_t) - 1):
        for k in range(12):
            k1 = (k + 1) % 12
            q = [rings_t[i][k], rings_t[i][k1], rings_t[i + 1][k1], rings_t[i + 1][k]]
            if len({v.co.to_tuple(5) for v in q}) >= 3:
                bm.faces.new(list(dict.fromkeys(q)))
    bm.faces.new(list(reversed(rings_t[-1])))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Cowl"])
    bk.box(part, m["Cowl"], (0.0, -3.24, PROP[2] - 0.13), (0.016, 0.22, 0.16), bevel=0.006)
    # A stripe of the boat's colour round the cowling and a small grille.
    bk.box(part, m["Paint"], (0.0, -3.30, 0.80), (0.468, 0.60, 0.035), bevel=0.012)
    bk.box(part, m["Trim"], (0.0, -3.63, 1.00), (0.24, 0.02, 0.06), bevel=0.01)
    obj = part.to_object(SMOOTH)
    place_object(obj, V(PIVOT), x_axis=(1, 0, 0))
    return obj


def build_propeller(m):
    part = bk.Part("Propeller", [])
    hx, hy, hz = PROP
    # Hub with a cone at the back.
    prof = [(0.0, 0.044), (0.06, 0.046), (0.10, 0.04), (0.13, 0.02), (0.14, 0.0)]
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / 12), hy + 0.05 - dy, hz + r * math.sin(2 * math.pi * k / 12)))
              for k in range(12)] for (dy, r) in prof]
    for i in range(len(rings) - 1):
        for k in range(12):
            k1 = (k + 1) % 12
            q = [rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]]
            if len({v.co.to_tuple(5) for v in q}) >= 3:
                bm.faces.new(list(dict.fromkeys(q)))
    bm.faces.new(rings[0])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Chrome"])
    # Three twisted blades.
    for b in range(3):
        a0 = 2 * math.pi * b / 3
        blade = []
        for r in (0.04, 0.08, 0.12, 0.155, 0.175):
            chord = 0.11 * math.sin(math.pi * min((r - 0.03) / 0.16, 0.95)) + 0.03
            pitch = math.radians(lerp(42, 24, (r - 0.04) / 0.135))
            radial = V((math.cos(a0), 0.0, math.sin(a0)))
            tangent = V((-math.sin(a0), 0.0, math.cos(a0)))
            axis = V((0.0, -1.0, 0.0))
            c = V((hx, hy, hz)) + radial * r
            ring = []
            for k in range(8):
                t = 2 * math.pi * k / 8
                u = math.cos(t) * chord * 0.5
                v = math.sin(t) * 0.006
                d = tangent * math.cos(pitch) + axis * math.sin(pitch)
                n = -tangent * math.sin(pitch) + axis * math.cos(pitch)
                ring.append(tuple(c + d * u + n * v))
            blade.append(ring)
        ring_loft(part, blade, lambda i, j: m["Chrome"], cap_end=True, inside=(hx, hy, hz))
    obj = part.to_object(math.radians(50))
    place_object(obj, V(PROP), x_axis=(1, 0, 0))
    return obj


# ---------------------------------------------------------------- livery ---

def livery():
    """Stripes: two sweeping bands along each side of the topsides, rising
    toward the bow."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    ys = bk.stations(2.45, STERN + 0.02, 0.12)
    for (t0, t1) in ((0.26, 0.40), (0.47, 0.53)):
        for s in (-1, 1):
            rings = []
            for y in ys:
                rise = 0.32 * bk.smoothstep(-1.0, 2.45, y)
                ring = []
                for k in range(3):
                    t = min(lerp(t0, t1, k / 2) + rise, 0.97)
                    x, z = top(y, t)
                    xa, za = top(y, max(t - 0.02, 0.0))
                    xb, zb = top(y, min(t + 0.02, 1.0))
                    nx, nz = (zb - za), -(xb - xa)
                    ln = math.hypot(nx, nz)
                    nx, nz = nx / ln, nz / ln
                    ring.append((s * (x + nx * 0.004), y, z + nz * 0.004))
                rings.append(ring)
            ring_loft(part, rings, lambda i, j: mat, close=False, inside=(0.0, 0.0, 0.3))
    return part


# ------------------------------------------------------------------ build ---

def godot(p):
    return (round(p[0], 3), round(p[2], 3), round(-p[1], 3))


def report():
    """Numbers for boat.tscn (Godot space)."""
    hull = []
    for y in (STERN, -2.0, -1.0, 0.0, 1.0, 1.8, 2.4, 2.8, 3.08):
        hull.append((0.0, y, ZK(y)))
        for s in (-1, 1):
            hull.append((s * CW(y), y, ZC(y)))
            hull.append((s * (SW(y) + 0.03), y, ZS(y) + 0.04))
    print("HULL_POINTS PackedVector3Array(" + ", ".join("%g, %g, %g" % godot(p) for p in hull) + ")")
    pts = []
    areas = []
    spacing = 1.15
    for y in (2.35, 1.25, 0.1, -1.05, -2.25):
        cw, sw = CW(y), SW(y)
        pts.append((0.0, y, ZK(y)))
        areas.append(0.8 * cw * spacing)
        for s in (-1, 1):
            pts.append((s * cw * 0.75, y, lerp(ZK(y), ZC(y), 0.75)))
            areas.append(0.6 * cw * spacing)
            pts.append((s * (sw - 0.02), y, 0.05))
            areas.append(max(sw - cw, 0.05) * 2.2 * spacing)
    print("FLOAT_POINTS PackedVector3Array(" + ", ".join("%g, %g, %g" % godot(p) for p in pts) + ")")
    print("FLOAT_AREAS PackedFloat32Array(" + ", ".join("%g" % round(a, 3) for a in areas) + ")")
    print("PROP", godot(PROP), "PIVOT", godot(PIVOT))
    print("SHEER at y=0: half width %.2f, z %.2f; deck at bow %.2f; sole %.2f" % (SW(0), ZS(0), deck_z(2.8), SOLE))


def build():
    bk.reset_scene()
    m = materials()
    hull = bk.Part("Hull", [])
    build_hull(hull, m)
    cockpit = bk.Part("Cockpit", [])
    build_cockpit(cockpit, m)
    fittings = bk.Part("FittingsStern", [])
    build_fittings(fittings, m)
    # The bow's rail and light apart from the stern's pole, platforms and
    # handles, so a dent pass only processes the end it reaches (ART_BIBLE §14).
    bow = bk.split_part(fittings, "FittingsBow", lambda c: c.y > 0.6)
    objs = [hull.to_object(SMOOTH), cockpit.to_object(SMOOTH), bow.to_object(SMOOTH), fittings.to_object(SMOOTH)]
    objs.append(build_windscreen(m).to_object(SMOOTH))
    out = build_outboard(m)
    prop = build_propeller(m)
    prop.parent = out
    prop.matrix_parent_inverse = out.matrix_world.inverted()
    objs += [out, prop]
    objs.append(livery().to_object(SMOOTH))
    for o in objs:
        print("  %-11s %5d verts" % (o.name, len(o.data.vertices)))
    bk.export(objs, "boat_body.glb")
    report()


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
