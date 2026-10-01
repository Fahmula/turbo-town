"""Generates the sports car body and its alloy wheel as .glb files.

Run headless from the project root:
    blender -b -P tools/blender/make_car.py

Stylized-realism design (ART_BIBLE.md §12-14): a generic, unbranded
front-engined sports coupe with a long bonnet, fender peaks over the wheels,
a fastback cabin and a small wing. Built with body_kit's loft, so panels are
curved and evenly meshed for dents.

Conventions (Blender is Z-up; glTF export converts to Godot's Y-up):
  * Front points to Blender +Y (Godot -Z), right is +X.
  * Origin is at wheel-centre height, centred between the axles, matching
    scenes/vehicles/sports_car.tscn (wheels at x=+-0.83, y=+-1.35, radius 0.37).
  * Ground is at z = -0.37.
Material and part names are the game's contract (ART_BIBLE.md §13):
Paint, Glass, Headlight, TailLight, ReverseLight; FrontBumper, RearBumper and
Spoiler are separate meshes (named exactly that) so they can fall off.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

WHEEL_R = 0.37
WHEEL_X = 0.83
AXLE_Y = 1.35
ARCH_R = WHEEL_R + 0.04          # fender lip radius (4 cm gap)
Z_FLOOR = -0.24                  # underbody (13 cm ground clearance)
Y_NOSE, Y_TAIL = 2.20, -2.20
NOSE0, TAIL0 = 2.02, -2.06       # where the plan view starts rounding off

# Plan view: half width at door-middle height.
WIDTH = bk.curve([(2.02, 0.865), (1.80, 0.925), (1.35, 0.955), (0.95, 0.94), (0.30, 0.932),
                  (-0.55, 0.94), (-1.35, 0.968), (-1.80, 0.935), (-2.06, 0.885)])
# Side view: the shoulder / belt line (fender peaks over both axles).
SHOULDER = bk.curve([(2.20, 0.13), (2.10, 0.21), (1.95, 0.31), (1.70, 0.42), (1.38, 0.49),
                     (1.05, 0.475), (0.62, 0.465), (0.0, 0.475), (-0.70, 0.50), (-1.10, 0.53),
                     (-1.38, 0.555), (-1.75, 0.545), (-2.02, 0.515), (-2.20, 0.43)])
# Side view: the cabin's roof edge, from the windscreen base to the deck.
WS_BASE, RW_BASE = 0.62, -1.58
ROOF_EDGE = bk.curve([(0.62, 0.465), (0.40, 0.60), (0.19, 0.73), (-0.02, 0.85), (-0.20, 0.868),
                      (-0.37, 0.872), (-0.55, 0.866), (-0.72, 0.85), (-0.95, 0.785), (-1.25, 0.68),
                      (-1.58, 0.553)])
# How much the top centre rises above the edges (negative = bonnet dips
# between the fender peaks).
CROWN = bk.curve([(2.2, 0.0), (2.0, -0.005), (1.6, -0.03), (1.0, -0.028), (0.66, -0.02), (0.55, 0.02),
                  (0.3, 0.025), (-0.02, 0.03), (-0.7, 0.03), (-1.4, 0.02), (-1.62, -0.01), (-2.2, -0.01)])
ROOF_W = bk.curve([(0.62, 0.66), (-0.02, 0.62), (-0.7, 0.60), (-1.58, 0.64)])

# Regions along the car (face mid-points).
SIDE_GLASS = (0.56, -1.22)
B_PILLAR = (-0.655, -0.715)
DOOR_LINES = [(0.884, 0.876), (-0.647, -0.655)]
HOOD_FRONT_LINE = (2.004, 1.996)
COWL = (0.62, 0.585)
DECK_FRONT_LINE = (-1.58, -1.60)
DECK_REAR_LINE = (-2.056, -2.064)
BUMPER_SPLIT = 1.80


def wrap(y):
    """Plan-view rounding at the nose and tail: 1 inside, falling to 0 at
    the tips."""
    if y > NOSE0:
        t = (y - NOSE0) / (Y_NOSE - NOSE0)
        return max(0.0, 1.0 - t ** 2.4) ** (1 / 2.4)
    if y < TAIL0:
        t = (TAIL0 - y) / (TAIL0 - Y_TAIL)
        return max(0.0, 1.0 - t ** 3.0) ** (1 / 3.0)
    return 1.0


def arch(y):
    """Underbody height here (raised over the wheels) and how much we're in
    an arch (0..1)."""
    for ay in (AXLE_Y, -AXLE_Y):
        dy = y - ay
        if abs(dy) <= ARCH_R + 1e-6:
            return math.sqrt(max(ARCH_R * ARCH_R - dy * dy, 0.0)), 1.0
    return Z_FLOOR, 0.0


def has_cabin(y):
    return RW_BASE < y < WS_BASE


def section(_i, y):
    yc = min(max(y, TAIL0), NOSE0)
    k = wrap(y)
    w = WIDTH(yc)
    z_sh = SHOULDER(y)
    z_re = z_sh + 0.004
    g = 0.0
    if has_cabin(y):
        z_re = max(z_re, ROOF_EDGE(y))
        g = bk.smoothstep(0.0, 1.0, (z_re - z_sh) / (0.85 - z_sh))
    z_rc = z_re + CROWN(y)
    w_sh = w - 0.04
    w_re = bk.lerp(w_sh - 0.11, ROOF_W(y), g)
    band = bk.lerp(0.008, 0.045, bk.smoothstep(0.0, 0.12, g))
    zb, a = arch(y)
    off3 = bk.lerp(0.035, 0.012, a)
    off4 = bk.lerp(0.10, 0.03, a)
    p = []
    p.append((0.0, zb))
    p.append((w - 0.07, zb))
    p.append((w - 0.012, zb + off3))
    p.append((w - 0.002 + 0.006 * a, zb + off4))
    z4 = zb + off4
    z7 = z_sh - 0.035
    p.append((w + 0.007, bk.lerp(z4, z7, 0.33)))
    p.append((w + 0.012, bk.lerp(z4, z7, 0.70)))
    p.append((w_sh + 0.012, z7))
    p8 = (w_sh - 0.01, z_sh)
    p13 = (w_re, z_re)
    p.append(p8)
    lx, lz = p13[0] - p8[0], p13[1] - p8[1]
    ln = max(math.hypot(lx, lz), 1e-4)
    for f in (min(0.03 / ln, 0.2), 0.45, 0.75, 1.0 - min(band / ln, 0.4)):
        p.append((p8[0] + lx * f, p8[1] + lz * f))
    p.append(p13)
    u_band = min(band / max(w_re, 1e-3), 0.25)
    for u in (u_band, 0.3, 0.5, 0.7, 0.86, 1.0):
        x = w_re * (1.0 - u)
        z = z_re + (z_rc - z_re) * (1.0 - (1.0 - u) ** 2)
        p.append((x, z))
    # Plan-view rounding at the ends squeezes everything toward the centre.
    return [(x * k, z) for (x, z) in p]


def region(y):
    if y > WS_BASE:
        return "hood"
    if y > -0.02:
        return "ws"
    if y > -0.72:
        return "roof"
    if y > RW_BASE:
        return "rw"
    return "deck"


def within(y, rng):
    return min(rng) < y < max(rng)


def material_fn(m):
    def f(_i, j, y0, y1):
        y = (y0 + y1) * 0.5
        reg = region(y)
        cabin = reg in ("ws", "roof", "rw")
        if j == 0:
            return m["Trim"]                           # underbody
        if j <= 2:
            return m["Trim"]                           # black sills / lower lips
        if j <= 6:
            if any(within(y, d) for d in DOOR_LINES) and j >= 3:
                return m["Trim"]
            return m["Paint"]
        if j == 7:
            return m["Trim"] if within(y, SIDE_GLASS) else m["Paint"]
        if j <= 10:
            if within(y, B_PILLAR) and within(y, SIDE_GLASS):
                return m["Trim"]
            return m["Glass"] if within(y, SIDE_GLASS) else m["Paint"]
        if j <= 12:
            return m["Paint"] if cabin else m["Trim"]  # pillars / shut gaps
        # Top: bonnet, windscreen, roof, rear window, deck.
        if within(y, HOOD_FRONT_LINE) or within(y, COWL) or within(y, DECK_FRONT_LINE) or within(y, DECK_REAR_LINE):
            return m["Trim"]
        if reg in ("ws", "rw"):
            return m["Trim"] if j == 13 else m["Glass"]
        return m["Paint"]
    return f


def build_body():
    bk.reset_scene()
    m = bk.vehicle_materials()
    ys = bk.stations(
        Y_NOSE, Y_TAIL, 0.14,
        keep=[NOSE0, TAIL0, WS_BASE, RW_BASE, -0.02, -0.72, BUMPER_SPLIT, -BUMPER_SPLIT,
              *SIDE_GLASS, *B_PILLAR, *[v for d in DOOR_LINES for v in d], *HOOD_FRONT_LINE,
              *COWL, *DECK_FRONT_LINE, *DECK_REAR_LINE,
              AXLE_Y + ARCH_R + 0.006, AXLE_Y + ARCH_R, AXLE_Y - ARCH_R, AXLE_Y - ARCH_R - 0.006,
              -AXLE_Y + ARCH_R + 0.006, -AXLE_Y + ARCH_R, -AXLE_Y - ARCH_R, -AXLE_Y - ARCH_R - 0.006]
             + [NOSE0 + t * (Y_NOSE - NOSE0) for t in (0.3, 0.55, 0.72, 0.85, 0.93, 0.98, 1.0)]
             + [TAIL0 - t * (TAIL0 - Y_TAIL) for t in (0.35, 0.6, 0.8, 0.92, 0.98, 1.0)],
        refine=[(AXLE_Y + ARCH_R, AXLE_Y - ARCH_R, 0.09), (-AXLE_Y + ARCH_R, -AXLE_Y - ARCH_R, 0.09)])
    shell = bk.Part("CarBody", [])
    bk.loft(shell, ys, section, material_fn(m))

    # Bumpers: the lower front and rear fascia rows, thickened so they look
    # solid when they tumble away.
    def lower(c):
        return c.z < _row_height(c.y) + 1e-4
    front = bk.split_part(shell, "FrontBumper", lambda c: c.y > BUMPER_SPLIT and lower(c))
    rear = bk.split_part(shell, "RearBumper", lambda c: c.y < -BUMPER_SPLIT and lower(c))

    bk.thicken(front, 0.018)
    bk.thicken(rear, 0.018)
    surf = bk.Surface([shell, front, rear])
    _lights_and_details(surf, shell, front, rear, m)

    # Crash beams behind the bumpers (seen once a bumper falls off).
    bk.box(shell, m["Trim"], (0, 1.93, -0.11), (1.30, 0.22, 0.17))
    bk.box(shell, m["Trim"], (0, -1.95, -0.10), (1.30, 0.20, 0.17))

    _interior(shell, m, ys)
    _mirrors(shell, m)
    wing = _wing(m)

    objs = [shell.to_object(math.radians(60)), front.to_object(math.radians(60)),
            rear.to_object(math.radians(60)), wing.to_object(math.radians(60))]
    bk.export(objs, "car_body.glb")


def _row_height(y):
    """Height of the bumper's top edge (section point 4) at station y."""
    p = section(0, y)
    return p[4][1]


def _lights_and_details(surf, shell, front, rear, m):
    fwd = (0, -1, -0.25)
    back = (0, 1, -0.15)
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Headlights: a chrome reflector housing with a light strip and two
        # projector lamps, wrapping round the front corners.
        hx = sx * 0.62
        bk.patch(surf, shell, m["Trim"], bk.rect(0.42, 0.115, 0.5), (hx, 2.3, 0.165), fwd, up, lift=0.003)
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.39, 0.09, 0.5), (hx, 2.3, 0.165), fwd, up, lift=0.005)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.36, 0.022, 0.3), (hx, 2.3, 0.198), fwd, up, lift=0.007, grid=4)
        for k in (-1, 1):
            bk.patch(surf, shell, m["Headlight"], bk.ellipse(0.075, 0.055), (hx + k * 0.085, 2.3, 0.15), fwd, up, lift=0.007, grid=4)
        # Tail lights: wide red units with a white reverse lamp inside.
        tx = sx * 0.6
        bk.patch(surf, shell, m["Trim"], bk.rect(0.50, 0.105, 0.4), (tx, -2.3, 0.36), back, up, lift=0.003)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.47, 0.08, 0.4), (tx, -2.3, 0.36), back, up, lift=0.005)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.09, 0.04), (sx * 0.30, -2.3, 0.352), back, up, lift=0.007, grid=3)
        # Door handle.
        bk.patch(surf, shell, m["Trim"], bk.rect(0.16, 0.025), (sx * 1.2, -0.42, 0.405), (-sx, 0, 0), up, lift=0.004, grid=3)
        # Exhaust tips (a dark disc on the end reads as the hollow pipe).
        bk.tube(shell, m["Chrome"], (sx * 0.30, -2.05, -0.17), (sx * 0.30, -2.24, -0.17), 0.045, 12)
        bk.tube(shell, m["Trim"], (sx * 0.30, -2.2395, -0.17), (sx * 0.30, -2.2415, -0.17), 0.034, 12)
    # Thin light bar linking the tail lights.
    bk.patch(surf, shell, m["TailLight"], bk.rect(0.60, 0.012), (0, -2.3, 0.392), back, up, lift=0.005, grid=4)
    # Grille between the headlights and the big intake in the bumper.
    bk.patch(surf, shell, m["Trim"], bk.rect(0.62, 0.075, 0.5), (0, 2.3, 0.07), (0, -1, 0), up, lift=0.003)
    bk.patch(surf, front, m["Trim"], bk.rect(1.0, 0.075, 0.6), (0, 2.3, -0.075), (0, -1, 0), up, lift=0.003)
    # Rear diffuser.
    bk.patch(surf, rear, m["Trim"], bk.rect(1.10, 0.09, 0.3), (0, -2.3, -0.14), (0, 1, 0), up, lift=0.003)
    # Badge on the nose.
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.07, 0.045), (0, 2.3, 0.135), fwd, up, lift=0.006, grid=4)


def _interior(shell, m, ys):
    """A simple dark cabin so the glass doesn't look into an empty shell:
    door cards and headliner (an inner copy of the shell), floor, dash,
    seats, steering wheel and parcel shelf."""
    inner = [y for y in ys if 0.58 > y > -1.56][::2]

    def inner_section(i, y):
        pts = section(i, y)
        out = []
        for j, (x, z) in enumerate(pts):
            a = pts[max(j - 1, 0)]
            b = pts[min(j + 1, len(pts) - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            ln = max(math.hypot(tx, tz), 1e-5)
            nx, nz = tz / ln, -tx / ln          # outward for this winding
            out.append((max(x - nx * 0.018, 0.0), z - nz * 0.018))
        return out

    def inner_mat(_i, j, y0, y1):
        y = (y0 + y1) * 0.5
        if 3 <= j <= 6:
            return m["Interior"]                       # door cards
        if 11 <= j and region(y) == "roof":
            return m["Interior"]                       # headliner
        if j in (11, 12):
            return m["Interior"]                       # inside of the pillars
        return None
    tmp = bk.Part("inner", list(shell.mats))
    bk.loft(tmp, inner, inner_section, inner_mat)
    import bmesh
    bmesh.ops.reverse_faces(tmp.bm, faces=tmp.bm.faces[:])
    _merge(shell, tmp)

    im = m["Interior"]
    bk.box(shell, im, (0, -0.18, -0.175), (1.66, 1.50, 0.02))                 # floor
    bk.box(shell, im, (0, 0.47, 0.33), (1.66, 0.30, 0.20))                  # dash
    bk.box(shell, im, (0, -1.25, 0.43), (1.62, 0.62, 0.02))                  # parcel shelf (over the arches)
    bk.box(shell, im, (0, -0.95, 0.135), (1.62, 0.05, 0.59))                 # bulkhead behind seats
    bk.box(shell, im, (0, -0.05, -0.06), (0.20, 0.95, 0.20))                 # console
    for sx in (-1, 1):
        x = sx * 0.40
        bk.box(shell, im, (x, -0.33, -0.08), (0.50, 0.52, 0.16), bevel=0.04, segments=1)                 # cushion
        bk.box(shell, im, (x, -0.66, 0.28), (0.50, 0.14, 0.62), bevel=0.05, rot=(math.radians(-14), 0, 0), segments=1)  # back
        bk.box(shell, im, (x, -0.74, 0.64), (0.26, 0.10, 0.14), rot=(math.radians(-14), 0, 0))           # headrest
    # Steering wheel (left-hand drive) on its column.
    _steering_wheel(shell, m["Trim"], (-0.40, 0.22, 0.34))
    bk.tube(shell, m["Trim"], (-0.40, 0.25, 0.33), (-0.40, 0.45, 0.26), 0.025, 8)


def _steering_wheel(part, mat, c):
    import bmesh
    import mathutils
    bm = bmesh.new()
    ring_r, tube_r, seg, tseg = 0.17, 0.018, 16, 5
    rings = []
    for a in range(seg):
        ang = 2 * math.pi * a / seg
        ring = []
        for b in range(tseg):
            t = 2 * math.pi * b / tseg
            r = ring_r + tube_r * math.cos(t)
            ring.append(bm.verts.new((r * math.cos(ang), tube_r * math.sin(t), r * math.sin(ang))))
        rings.append(ring)
    for a in range(seg):
        r0, r1 = rings[a], rings[(a + 1) % seg]
        for b in range(tseg):
            bm.faces.new([r0[b], r1[b], r1[(b + 1) % tseg], r0[(b + 1) % tseg]])
    # Tilt toward the driver.
    bm.transform(mathutils.Matrix.Translation(c) @ mathutils.Matrix.Rotation(math.radians(-25), 4, "X"))
    bk._append(part, bm, mat)
    bk.box(part, mat, (c[0], c[1] - 0.005, c[2] - 0.002), (0.10, 0.03, 0.08))


def _merge(dst, src):
    import bmesh
    vmap = {v: dst.bm.verts.new(v.co) for v in src.bm.verts}
    for f in src.bm.faces:
        nf = dst.bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = dst.slot(src.mats[f.material_index])
    src.bm.free()


def _mirrors(shell, m):
    for sx in (-1, 1):
        bk.box(shell, m["Paint"], (sx * 1.02, 0.47, 0.565), (0.17, 0.10, 0.085), bevel=0.03, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.02, 0.418, 0.565), (0.14, 0.006, 0.065))
        bk.box(shell, m["Trim"], (sx * 0.95, 0.49, 0.52), (0.08, 0.05, 0.04))


def _wing(m):
    """Rear wing: an extruded airfoil with end plates on two stands. The mesh
    must be called "Spoiler": that's the name VehicleDamage knocks off."""
    part = bk.Part("Spoiler", [])
    import bmesh
    bm = bmesh.new()
    chord, thick, span = 0.27, 0.035, 1.56
    prof = []
    for k in range(7):
        t = k / 6.0
        yy = -1.86 - chord * t
        half = thick * 0.5 * (math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.7 + 0.15)
        prof.append((yy, half))
    top = [(y, 0.775 + h - 0.05 * (y + 1.86)) for (y, h) in prof]
    bot = [(y, 0.775 - h * 0.6 - 0.05 * (y + 1.86)) for (y, h) in reversed(prof)]
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
        bk.box(part, m["Paint"], (sx * 0.79, -1.99, 0.75), (0.012, 0.32, 0.12))   # end plate
        bk.box(part, m["Trim"], (sx * 0.52, -1.97, 0.63), (0.03, 0.12, 0.24))    # stand
    return part


def build_wheel():
    """19-inch five double-spoke alloy with a low-profile tyre and a brake
    disc. Axis is X; +X is the outer face."""
    bk.reset_scene()
    tire_m = bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9)
    rim_m = bk.material("Rim", (0.72, 0.73, 0.75), rough=0.32, metal=1.0)
    hub_m = bk.material("Hub", (0.24, 0.24, 0.26), rough=0.5, metal=0.6)
    part = bk.Part("Wheel", [])
    R = WHEEL_R
    tyre = [(-0.112, 0.243), (-0.124, 0.27), (-0.127, 0.30), (-0.124, 0.33), (-0.114, 0.355),
            (-0.098, 0.366), (-0.07, 0.37), (-0.05, 0.364), (-0.035, 0.37), (-0.008, 0.37),
            (0.0, 0.364), (0.008, 0.37), (0.035, 0.37), (0.05, 0.364), (0.07, 0.37), (0.098, 0.366),
            (0.114, 0.355), (0.124, 0.33), (0.127, 0.30), (0.124, 0.27), (0.112, 0.243)]
    tyre = [(x, r * R / 0.37) for (x, r) in tyre]
    bk.lathe(part, tire_m, tyre, 36)
    rim = [(0.112, 0.243), (0.122, 0.248), (0.126, 0.24), (0.118, 0.232), (0.102, 0.226),
           (0.04, 0.222), (-0.06, 0.222), (-0.104, 0.232), (-0.112, 0.243)]
    bk.lathe(part, rim_m, rim, 36)
    # Brake disc behind the spokes, and the hub face.
    bk.lathe(part, hub_m, [(-0.035, 0.07), (-0.035, 0.175), (-0.012, 0.175), (-0.012, 0.07)], 28, loop=True)
    bk.lathe(part, rim_m, [(0.06, 0.0), (0.06, 0.07), (0.088, 0.078), (0.098, 0.06), (0.104, 0.03), (0.105, 0.0)], 20)
    # Five split spokes (a narrow V each), dished toward the rim.
    for k in range(5):
        base = 2 * math.pi * k / 5
        for side in (-1, 1):
            bk.spoke(part, rim_m, (0.097, 0.068, base + side * 0.09, 0.016),
                     (0.116, 0.225, base + side * 0.2, 0.013), 0.024)
    # Lug nuts.
    for k in range(5):
        a = 2 * math.pi * (k + 0.5) / 5
        c = (0.104, math.cos(a) * 0.042, math.sin(a) * 0.042)
        bk.tube(part, hub_m, (c[0] - 0.01, c[1], c[2]), (c[0] + 0.006, c[1], c[2]), 0.009, 6)
    obj = part.to_object(math.radians(42))
    bk.export([obj], "wheel.glb")


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build_body()
    build_wheel()
