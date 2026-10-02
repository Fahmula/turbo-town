"""Generates the buggy body (buggy_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_buggy.py

Design language (ART_BIBLE.md §12): a classic desert sand-rail / dune
buggy. A small painted tub with a rounded nose deck and an open cockpit
(rubber-edged rim, inner walls, floor), round headlight pods and a fuel cap
on the nose, a full tube roll cage with a roof light bar, an exposed rear
engine with air filter and chrome exhausts, long-travel suspension arms with
coil-overs, two bucket seats, a tube front bumper (FrontBumper), a rear bar
(RearBumper) and a rear wing (Spoiler). Optional nose stripes (garage).

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/buggy.tscn (wheels r 0.42 at x +-0.92,
axles +-1.25). Ground is z = -0.42. Wheels: wheel_offroad.glb, outboard of
the tub (inner tyre face x +-0.75), so the tub needs no arches.
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.25
COWL = 0.50                # the closed nose deck ends here; the tub is open behind
WALL = 0.035               # tub wall thickness
FLOOR_IN = -0.02           # cockpit floor (the underbody is at -0.06)

# The whole tub's outer shape. The nose (y > COWL) is lofted with the
# standard section; the open part reuses its outer points so they match.
FULL = bk.LoftBody(bk.BodySpec(
    y_nose=1.80, y_tail=-1.58, nose0=1.62, tail0=-1.50, nose_p=2.2, tail_p=4.0,
    floor=-0.06,
    width=bk.curve([(1.62, 0.42), (1.2, 0.51), (0.5, 0.60), (-0.5, 0.62), (-1.5, 0.60)]),
    # Side line: high at the cowl, dipping round the seats, up again over the engine.
    shoulder=bk.curve([(1.80, 0.10), (1.6, 0.26), (1.2, 0.36), (0.6, 0.44), (0.4, 0.43), (0.05, 0.31),
                       (-0.55, 0.30), (-0.95, 0.41), (-1.58, 0.42)]),
    crown=bk.curve([(1.8, 0.0), (1.4, 0.04), (0.5, 0.04)]),
    bumper_split=(9.0, -9.0),
    shoulder_inset=0.03, hood_edge_inset=0.06, bulge=0.006,
    station_step=0.15,
    keep=[COWL],
))


def _tub_section(_i, y):
    """Outer side up to the shoulder, a rounded rim, the inner wall back down
    and the cockpit floor to the centre line."""
    pts = FULL.section(0, y)[:9]
    x8, z8 = pts[8]
    rim = [(max(x8 - WALL * 0.5, 0.0), z8 + 0.008)]
    inner = [(max(x - WALL, 0.0), z) for (x, z) in reversed(pts[3:9])]
    x3 = inner[-1][0]
    floor = [(max(x3 - 0.02, 0.0), FLOOR_IN), (0.0, FLOOR_IN)]
    return pts + rim + inner + floor


def _tub_material(m):
    def f(_i, j, _y0, _y1):
        if j <= 2:
            return m["Trim"]                             # underbody, sills
        if j <= 7:
            return m["Paint"]
        if j <= 9:
            return m["Trim"]                             # rubber rim edge
        return m["Interior"]                             # inner walls, floor
    return f


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.878, 0.4, 0.106))
    m["Cage"] = bk.material("Cage", (0.12, 0.12, 0.14), rough=0.5, metal=0.3)
    shell = bk.Part("BuggyBody", [])
    ys = FULL.stations()
    bk.loft(shell, [y for y in ys if y >= COWL], FULL.section,
            lambda _i, j, y0, y1: m[FULL.material_key(j, (y0 + y1) * 0.5)])
    bk.loft(shell, [y for y in ys if y <= COWL], _tub_section, _tub_material(m))
    surf = bk.Surface([shell])
    _nose(surf, shell, m)
    _cage(shell, m)
    _engine(shell, m)
    _cockpit(shell, m)
    _suspension(shell, m)
    front = bk.Part("FrontBumper", [])
    bk.tube(front, m["Cage"], (-0.46, 1.90, -0.02), (0.46, 1.90, -0.02), 0.04, 10)
    for sx in (-1, 1):
        bk.tube(front, m["Cage"], (sx * 0.46, 1.90, -0.02), (sx * 0.34, 1.62, 0.20), 0.035, 8)
        bk.tube(front, m["Cage"], (sx * 0.46, 1.90, -0.02), (sx * 0.30, 1.62, -0.05), 0.035, 8)
        bk.box(front, m["Headlight"], (sx * 0.30, 1.925, -0.02), (0.07, 0.012, 0.04), kind=bk.AUX)      # fog lamps
    rear = bk.Part("RearBumper", [])
    bk.tube(rear, m["Cage"], (-0.55, -1.74, 0.06), (0.55, -1.74, 0.06), 0.04, 10)
    for sx in (-1, 1):
        bk.tube(rear, m["Cage"], (sx * 0.55, -1.74, 0.06), (sx * 0.45, -1.62, 0.06), 0.035, 8)
    wing = _wing(m)
    stripes = _stripes(surf)
    objs = [p.to_object(math.radians(55)) for p in (shell, front, rear, wing, stripes)]
    bk.export(objs, "buggy_body.glb")


def _nose(surf, shell, m):
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Round headlight pods on short stalks, pointing forward.
        c = (sx * 0.30, 1.40, 0.44)
        bk.tube(shell, m["Cage"], (c[0], c[1] - 0.02, 0.30), (c[0], c[1] - 0.02, c[2]), 0.016, 6)
        bk.tube(shell, m["Chrome"], (c[0], c[1] - 0.06, c[2]), (c[0], c[1] + 0.05, c[2]), 0.075, 14)
        bk.tube(shell, m["Headlight"], (c[0], c[1] + 0.05, c[2]), (c[0], c[1] + 0.056, c[2]), 0.064, 14, kind=bk.LAMP)
    # Fuel cap and hood pins on the deck.
    bk.tube(shell, m["Chrome"], (0.26, 0.80, 0.39), (0.26, 0.80, 0.43), 0.055, 12)
    for sx in (-1, 1):
        bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.04, 0.04), (sx * 0.36, 1.50, 1.0), (0, 0, -1), (0, 1, 0),
                 lift=0.004, grid=2)
    # Dash across the cowl closes the nose from the cockpit.
    bk.box(shell, m["Interior"], (0, COWL - 0.02, 0.22), (1.18, 0.04, 0.50))
    bk.box(shell, m["Interior"], (0, COWL - 0.07, 0.42), (1.0, 0.12, 0.08), bevel=0.02, segments=1)
    bk.patch(surf, shell, m["Trim"], bk.rect(0.9, 0.03), (0, 1.73, 0.06), (0, -1, 0), up, lift=0.004, grid=(4, 1))


def _cage(shell, m):
    c = m["Cage"]

    def t(a, b, r=0.035):
        bk.tube(shell, c, a, b, r, 10)
    sh = FULL.s.shoulder
    for sx in (-1, 1):
        t((sx * 0.57, -0.80, sh(-0.80)), (sx * 0.50, -0.74, 1.30))  # main hoop legs
        t((sx * 0.57, 0.46, sh(0.46)), (sx * 0.48, 0.12, 1.28))    # A-pillars
        t((sx * 0.48, 0.12, 1.28), (sx * 0.50, -0.74, 1.30))       # roof rails
        t((sx * 0.50, -0.74, 1.30), (sx * 0.45, -1.64, 0.44))      # rear braces
        t((sx * 0.45, -1.64, 0.44), (sx * 0.45, -1.64, 0.06), 0.03)  # rear frame posts
        t(_at((sx * 0.57, 0.46, sh(0.46)), (sx * 0.48, 0.12, 1.28), 0.70),
          _at((sx * 0.57, -0.80, sh(-0.80)), (sx * 0.50, -0.74, 1.30), 0.70), 0.03)  # side bars
        t((sx * 0.70, 0.42, 0.04), (sx * 0.70, -0.76, 0.04), 0.03)  # nerf bars
        t((sx * 0.70, 0.42, 0.04), (sx * 0.58, 0.46, 0.10), 0.025)
        t((sx * 0.70, -0.76, 0.04), (sx * 0.60, -0.80, 0.10), 0.025)
    t((-0.48, 0.12, 1.28), (0.48, 0.12, 1.28))
    t((-0.50, -0.74, 1.30), (0.50, -0.74, 1.30))
    t((-0.50, -0.74, 1.30), (0.57, -0.80, sh(-0.80)), 0.03)       # diagonal brace
    t((-0.45, -1.64, 0.44), (0.45, -1.64, 0.44), 0.03)
    # Light bar on the roof with four lamps.
    bk.box(shell, c, (0, 0.13, 1.36), (0.86, 0.1, 0.09), bevel=0.015, segments=1)
    for k in range(4):
        bk.box(shell, m["Headlight"], (-0.3 + k * 0.2, 0.182, 1.36), (0.13, 0.012, 0.06), kind=bk.AUX)
    # Tail and reverse lamps on the back of the tub.
    for sx in (-1, 1):
        bk.box(shell, m["TailLight"], (sx * 0.32, -1.585, 0.33), (0.12, 0.03, 0.06), kind=bk.LAMP)
        bk.box(shell, m["ReverseLight"], (sx * 0.14, -1.585, 0.33), (0.07, 0.03, 0.05), kind=bk.LAMP)


def _at(a, b, z):
    """The point at height z on the line a-b."""
    f = (z - a[2]) / (b[2] - a[2])
    return tuple(p + (q - p) * f for p, q in zip(a, b))


def _engine(shell, m):
    top = FULL.s.shoulder(-0.84)
    bk.box(shell, m["Interior"], (0, -0.84, (FLOOR_IN + top) / 2), (1.18, 0.03, top - FLOOR_IN))       # firewall
    bk.box(shell, m["Trim"], (0, -1.15, 0.28), (0.50, 0.52, 0.34), bevel=0.04, segments=1)      # block
    for sx in (-1, 1):
        bk.box(shell, m["Chrome"], (sx * 0.31, -1.15, 0.26), (0.12, 0.40, 0.22), bevel=0.02, segments=1)  # heads
        bk.tube(shell, m["Chrome"], (sx * 0.20, -1.32, 0.14), (sx * 0.24, -1.74, 0.26), 0.04, 10)  # exhausts
        bk.tube(shell, m["Trim"], (sx * 0.24, -1.739, 0.259), (sx * 0.24, -1.745, 0.261), 0.03, 10)
    bk.tube(shell, m["Chrome"], (0, -1.02, 0.45), (0, -1.02, 0.60), 0.12, 14)                  # air filter
    bk.tube(shell, m["Trim"], (0, -1.02, 0.60), (0, -1.02, 0.615), 0.06, 10)


def _cockpit(shell, m):
    im = m["Trim"]
    for sx in (-1, 1):
        x = sx * 0.27
        bk.box(shell, im, (x, -0.42, 0.04), (0.40, 0.44, 0.10), bevel=0.03, segments=1)     # buckets
        bk.box(shell, im, (x, -0.66, 0.40), (0.40, 0.10, 0.62), bevel=0.04, rot=(math.radians(-12), 0, 0),
               segments=1)
        for z in (0.24, 0.52):                                                               # side bolsters
            bk.box(shell, im, (x + sx * 0.19, -0.60, z), (0.04, 0.16, 0.22), bevel=0.015, segments=1)
    bk.torus(shell, im, (-0.27, 0.20, 0.62), 0.15, 0.018, 14, 5, tilt=math.radians(-25))
    bk.tube(shell, im, (-0.27, 0.23, 0.61), (-0.27, COWL - 0.1, 0.44), 0.022, 8)
    bk.tube(shell, m["Chrome"], (0.0, 0.05, -0.02), (0.0, 0.05, 0.36), 0.015, 6)              # gear stick
    bk.tube(shell, im, (0.0, 0.05, 0.36), (0.0, 0.05, 0.40), 0.03, 8)


def _suspension(shell, m):
    f = m["Cage"]
    for sx in (-1, 1):
        for y in (AXLE_Y, -AXLE_Y):
            d = math.copysign(1, y)
            x_in = FULL.s.width(y) - 0.03
            for dy in (0.20, -0.20):
                bk.tube(shell, f, (sx * x_in, y + dy * d, 0.0), (sx * 0.71, y, -0.02), 0.022, 8)  # A-arms
            top = (sx * (x_in + 0.02), y - 0.14 * d, FULL.s.shoulder(y) + 0.02)
            bot = (sx * 0.70, y - 0.04 * d, -0.01)
            bk.tube(shell, m["Chrome"], top, bot, 0.022, 8)                                  # shock shaft
            lo = tuple(a + (b - a) * 0.15 for a, b in zip(top, bot))
            hi = tuple(a + (b - a) * 0.6 for a, b in zip(top, bot))
            bk.tube(shell, m["Paint"], lo, hi, 0.045, 10)                                     # spring


def _wing(m):
    """Rear wing: an airfoil with end plates on two posts from the rear frame.
    The mesh must be called "Spoiler"."""
    part = bk.Part("Spoiler", [])
    bm = bmesh.new()
    chord, thick, span, y0, z0 = 0.36, 0.045, 1.36, -1.52, 1.16
    prof = []
    for k in range(7):
        tt = k / 6.0
        half = thick * 0.5 * (math.sin(math.pi * min(tt * 1.15, 1.0)) ** 0.7 + 0.15)
        prof.append((y0 - chord * tt, half))
    top = [(y, z0 + h - 0.12 * (y0 - y)) for (y, h) in prof]
    bot = [(y, z0 - h * 0.6 - 0.12 * (y0 - y)) for (y, h) in reversed(prof)]
    loop = top + bot
    left = [bm.verts.new((-span / 2, y, z)) for (y, z) in loop]
    right = [bm.verts.new((span / 2, y, z)) for (y, z) in loop]
    n = len(loop)
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new([left[k], left[k1], right[k1], right[k]])
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, m["Paint"])
    for sx in (-1, 1):
        bk.box(part, m["Paint"], (sx * 0.686, y0 - chord * 0.5, z0 - 0.04), (0.012, 0.42, 0.16))   # end plates
        bk.tube(part, m["Cage"], (sx * 0.40, -1.64, 0.44), (sx * 0.40, -1.66, z0 - 0.03), 0.028, 8)
    return part


def _stripes(surf):
    """Optional twin stripes over the nose deck (garage only)."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    for sx in (-1, 1):
        bk.patch(surf, part, mat, bk.rect(0.11, 1.18), (sx * 0.085, 1.13, 2.0), (0, 0, -1), (0, 1, 0),
                 lift=0.005, grid=(1, 14))
    return part


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
