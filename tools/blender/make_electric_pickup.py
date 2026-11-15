"""Generates the electric pickup body (electric_pickup_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_electric_pickup.py

Design language (ART_BIBLE.md §12): a futuristic electric pickup, asked for
by the owner's son. Bare brushed stainless steel and flat panels with crisp
creases: a triangular side view, with the bonnet and a huge windscreen
rising in one straight line to a peak over the B pillar and the roof falling
in another straight line over a covered bed (a dark hard cover between two
steel sails) to the tailgate. A sloped front face with a full-width light
bar along its top edge; a full-width tail light bar along the tailgate's top
edge. Vertical flat sides with one sharp crease under the windows, the
upper sides leaning in. Angular (trapezoid) wheel arches with black
cladding, black rockers and bumpers. No grille, no door handles (hidden), no
exhaust. One long wiper. An invented badge (a triangle) on the tailgate; no
real maker's name, badge or logo.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/electric_pickup.tscn (wheels r 0.44 at x
+-0.84, axles +-1.88). Ground is z = -0.44. Its wheel is wheel_facet.glb
(make_wheels.py: the facet aero cover on the all-terrain tyre).

The body is a LoftBody with its own section (straight lines instead of the
cars' curves) but the standard 19 points, so inner_cabin, the garage's paint
lines and the kits work as on every other vehicle.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.88
W = 1.01                         # half width of the flat sides
FLOOR = -0.10                    # underbody: 34 cm ground clearance
Y_NOSE, Y_TAIL = 2.74, -2.86
Y_PEAK = -0.30                   # the roof's peak, over the B pillar
LEAN = 0.42                      # upper sides lean in (m in per m up), ~23 deg
CROWN = 0.025
# Trapezoid wheel arches: a flat top over the tyre (r 0.44, 9 cm gap) and
# straight sides down to the floor.
ARCH_TOP, ARCH_TOP_HALF, ARCH_FOOT_HALF = 0.53, 0.34, 0.58
# Where the bonnet turns into the windscreen, and the glass on top.
WS_BASE = 1.25
GLASS_TOP = [(WS_BASE, -0.24), (-0.36, -1.00)]   # windscreen, roof glass
TONNEAU = (-1.10, -2.79)                          # the bed's hard cover
# Bumpers (they come off in crashes): below these heights at the ends.
FRONT_BUMPER = (2.38, 0.30)
REAR_BUMPER = (-2.62, 0.26)
WINDOWS = [(1.05, 0.0), (-0.10, -1.02)]
DOOR_LINES = [(1.224, 1.216), (-0.046, -0.054), (-1.096, -1.104)]
TOP_LINES = [(1.274, 1.266), (TONNEAU[0] + 0.004, TONNEAU[0] - 0.004), (TONNEAU[1] + 0.004, TONNEAU[1] - 0.004)]


def lin(points):
    """Piecewise-straight function through (t, value) points, flat beyond."""
    pts = sorted(points)

    def f(t):
        if t <= pts[0][0]:
            return pts[0][1]
        for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
            if t <= t1:
                return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
        return pts[-1][1]
    return f


belt = lin([(Y_NOSE, 0.60), (Y_TAIL, 0.66)])                    # the side crease
ridge = lin([(Y_NOSE, 0.612), (Y_PEAK, 1.31), (Y_TAIL, 0.71)])   # top edge of the upper sides
# The underside rises at the ends: a chin and a sloped front face up to the
# light bar, and the departure angle under the rear bumper.
ends = lin([(2.40, FLOOR), (2.62, 0.04), (Y_NOSE, 0.55)])
tail_rise = lin([(-2.50, FLOOR), (-2.74, 0.06), (Y_TAIL, 0.10)])


def in_bed(y):
    return y < TONNEAU[0]


def _in_bumper(y):
    return y > FRONT_BUMPER[0] or y < REAR_BUMPER[0]


def _bumper_line(y):
    return FRONT_BUMPER[1] if y > 0.0 else REAR_BUMPER[1]


# Where the sloped front face crosses the bumper line (a station, so the
# bumper's top edge is straight across the face).
Y_FRONT_LINE = 2.62 + (FRONT_BUMPER[1] - 0.04) / (0.55 - 0.04) * (Y_NOSE - 2.62)


def top_band(y):
    """Width of the steel strip along the top edge: a slim A pillar / roof
    rail, the wide sail tops beside the bed cover."""
    return bk.lerp(0.05, 0.13, bk.smoothstep(TONNEAU[0] + 0.05, TONNEAU[0] - 0.05, y))


class Truck(bk.LoftBody):
    """A LoftBody with straight-lined sections, trapezoid arches and
    chamfered corners (plan view)."""

    def wrap(self, y):
        s = self.s
        if y > s.nose0:
            t = (y - s.nose0) / (s.y_nose - s.nose0)
            return 0.0 if t > 0.999 else 1.0 - 0.10 * t
        if y < s.tail0:
            t = (s.tail0 - y) / (s.tail0 - s.y_tail)
            return 0.0 if t > 0.999 else 1.0 - 0.05 * t
        return 1.0

    def arch(self, y):
        z = max(ends(y), tail_rise(y))
        a = 0.0
        for ay, _r in self.s.axles:
            dy = abs(y - ay)
            if dy < ARCH_FOOT_HALF:
                if dy <= ARCH_TOP_HALF:
                    za = ARCH_TOP
                else:
                    za = bk.lerp(ARCH_TOP, FLOOR, (dy - ARCH_TOP_HALF) / (ARCH_FOOT_HALF - ARCH_TOP_HALF))
                if za > z:
                    z, a = za, 1.0
        return z, a

    def section(self, _i, y):
        k = self.wrap(y)
        zb, a = self.arch(y)
        z_sh = belt(y)
        z_re = max(ridge(y), z_sh + 0.012)
        w_re = W - 0.02 - 0.006 - LEAN * (z_re - z_sh)
        z6 = z_sh - 0.015
        room = max(z6 - zb, 0.0)
        z2 = zb + min(0.015, room * 0.2)
        # Black cladding: a tall rocker along the sills, a narrower flare
        # round the arches.
        z3 = zb + min(bk.lerp(0.15, 0.07, a), room * 0.45)
        # Row 4 runs along the bumpers' top edge wherever it fits, so the
        # bumpers end on a straight line (the sides are flat, so moving the
        # row changes nothing else).
        line = _bumper_line(y)
        if y > self.s.nose0:
            # The sloped front face's corners: no cladding, the low rows
            # hug the bottom edge so row 4 can stay on the line until the
            # bottom edge reaches it.
            z2 = zb + min(0.004, room * 0.1)
            z3 = zb + min(0.008, room * 0.2)
            z4 = line if zb + 0.012 < line else zb + min(0.012, room * 0.3)
        else:
            if _in_bumper(y) and zb < line - 0.03:
                z3 = min(z3, line - 0.02)
            z4 = line if z3 + 0.005 < line < z6 - 0.01 else bk.lerp(z3, z6, 0.33)
        p = [(0.0, zb), (W - 0.10, zb), (W - 0.045, z2), (W - 0.012, z3),
             (W, z4), (W, bk.lerp(z4, z6, 0.5)), (W, z6), (W - 0.006, z_sh)]
        # The upper side: one flat facet leaning in to the top edge (a
        # window frame strip 4.5 cm deep under it).
        p7, p12 = p[-1], (w_re, z_re)
        lx, lz = p12[0] - p7[0], p12[1] - p7[1]
        ln = max(math.hypot(lx, lz), 1e-4)
        for f in (min(0.02 / ln, 0.2), 0.4, 0.75, 1.0 - min(0.045 / ln, 0.4)):
            p.append((p7[0] + lx * f, p7[1] + lz * f))
        p.append(p12)
        # The top: a steel edge strip, a 3 cm dark band (glass frit, cover
        # gap), then nearly flat across with a slight crown.
        ub = min(top_band(y) / max(w_re, 1e-3), 0.3)
        for u in (ub, ub + min(0.03 / max(w_re, 1e-3), 0.1), 0.35, 0.55, 0.78, 1.0):
            p.append((w_re * (1.0 - u), z_re + CROWN * (1.0 - (1.0 - u) ** 2)))
        return [(x * k, z) for (x, z) in p]

    def material_key(self, j, y):
        pts = self.section(0, y)
        zc = (pts[j][1] + pts[j + 1][1]) * 0.5
        if j <= 6:
            # Bumpers wrap round the corners in black; above them the front
            # face and the tailgate are steel.
            if _in_bumper(y) and zc < _bumper_line(y):
                return "Trim"
            if y > 2.55 or y < -2.80:
                return "Paint"
            if j == 0:
                return "Trim"                                   # underbody
            if j <= 2:
                return "Trim"                                   # rocker / arch cladding
            if any(bk.within(y, d) for d in DOOR_LINES):
                return "Trim"
            return "Paint"
        if j <= 10:
            if any(bk.within(y, w) for w in WINDOWS):
                return "Glass"
            if any(bk.within(y, d) for d in DOOR_LINES):
                return "Trim"
            return "Paint"
        if j <= 12:
            return "Paint"                                      # window frame, pillar / rail / sail top
        if any(bk.within(y, d) for d in TOP_LINES):
            return "Trim"
        if any(bk.within(y, g) for g in GLASS_TOP):
            return "Trim" if j == 13 else "Glass"
        if bk.within(y, TONNEAU):
            return "Trim"                                       # bed cover
        return "Paint"


SPEC = bk.BodySpec(
    y_nose=Y_NOSE, y_tail=Y_TAIL, nose0=2.62, tail0=-2.80,
    floor=FLOOR,
    axles=[(AXLE_Y, ARCH_FOOT_HALF), (-AXLE_Y, ARCH_FOOT_HALF)],
    width=lambda y: W,
    shoulder=belt,
    roof_edge=ridge,
    # Regions (inner_cabin puts the headliner under "roof"): the windscreen
    # runs to the peak, the headliner is under the roof glass behind it.
    ws_base=WS_BASE, roof_front=-0.24, roof_rear=-1.02, rw_base=-1.10,
    glass_top=1.31,
    windows=WINDOWS,
    door_lines=DOOR_LINES,
    top_lines=TOP_LINES,
    bumper_split=(FRONT_BUMPER[0], REAR_BUMPER[0]),
    keep=[Y_PEAK, 2.40, 2.55, Y_FRONT_LINE, WS_BASE, -0.36, -1.00, TONNEAU[0], TONNEAU[1], -2.50, -2.74,
          AXLE_Y + ARCH_TOP_HALF, AXLE_Y - ARCH_TOP_HALF, -AXLE_Y + ARCH_TOP_HALF, -AXLE_Y - ARCH_TOP_HALF],
    nose_samples=(0.25, 0.5, 0.75, 0.96, 1.0),
    tail_samples=(0.5, 0.95, 1.0),
    station_step=0.14,
)
BODY = Truck(SPEC)


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.72, 0.73, 0.75))
    shell, _f, _r, ys = BODY.build(m, "ElectricPickupBody", bumpers=False)
    front = bk.split_part(shell, "FrontBumper", lambda c: c.y > FRONT_BUMPER[0] and c.z < FRONT_BUMPER[1])
    rear = bk.split_part(shell, "RearBumper", lambda c: c.y < REAR_BUMPER[0] and c.z < REAR_BUMPER[1])
    for part in (front, rear):
        bk.thicken(part, 0.018)
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    BODY.inner_cabin(shell, m, ys, 1.20, -1.06)
    bk.box(shell, m["Trim"], (0, 2.46, 0.04), (1.5, 0.16, 0.14))          # crash beams
    bk.box(shell, m["Trim"], (0, -2.70, 0.08), (1.5, 0.16, 0.14))
    _interior(shell, m)
    _mirrors(shell, m)
    objs = [p.to_object(math.radians(22)) for p in (shell, front, rear)]
    bk.export(objs, "electric_pickup_body.glb")


def _front_dir():
    """Projection direction onto the sloped front face (from in front,
    looking back and a little up)."""
    dy, dz = Y_NOSE - 2.62, 0.55 - 0.04
    n = math.hypot(dy, dz)
    return (0, -dz / n, dy / n)


def _triangle(w, h):
    """Outline helper: a triangle, point up."""
    def f(u, v):
        return (u - 0.5) * w * (1.0 - v), (v - 0.5) * h
    return f


def _details(surf, shell, front, rear, m):
    up = (0, 0, 1)
    fwd = _front_dir()
    back = (0, 1, 0)
    # The light bar along the top of the front face: a black housing, a
    # full-width running light, the headlamps in its outer thirds, amber
    # indicators at the very ends.
    zb = 0.52
    bk.patch(surf, shell, m["Trim"], bk.rect(1.76, 0.05), (0, 3.0, zb), fwd, up, lift=0.003, grid=(16, 2))
    bk.patch(surf, shell, m["Headlight"], bk.rect(1.70, 0.016), (0, 3.0, zb + 0.008), fwd, up, lift=0.006,
             grid=(16, 1), kind=bk.DRL)
    for sx in (-1, 1):
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.36, 0.018), (sx * 0.60, 3.0, zb - 0.012), fwd, up, lift=0.007,
                 grid=(6, 1), kind=bk.LAMP)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.06, 0.03), (sx * 0.84, 3.0, zb), fwd, up, lift=0.008,
                 grid=(2, 1), kind=bk.INDICATOR)
        # A slim intake each side low in the bumper, a tow point between.
        bk.patch(surf, front, m["Trim"], bk.rect(0.36, 0.05), (sx * 0.52, 3.0, 0.15), (0, -1, 0.3), up, lift=0.004,
                 grid=(4, 1), kind=bk.GRILLE_MESH)
        # The tail light bar along the tailgate's top edge (tail and brake
        # light), amber indicators at its ends, reverse lamps low on the
        # tailgate, reflectors in the bumper.
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.08, 0.035), (sx * 0.89, -3.1, 0.60), back, up, lift=0.007,
                 grid=(2, 1), kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.12, 0.03), (sx * 0.70, -3.1, 0.33), back, up, lift=0.005,
                 grid=(2, 1), kind=bk.LAMP)
        bk.patch(surf, rear, m["TailLight"], bk.rect(0.14, 0.025), (sx * 0.78, -3.1, 0.17), back, up, lift=0.004,
                 grid=(3, 1))
    bk.patch(surf, shell, m["Trim"], bk.rect(1.84, 0.06), (0, -3.1, 0.60), back, up, lift=0.003, grid=(16, 2))
    bk.patch(surf, shell, m["TailLight"], bk.rect(1.62, 0.03), (0, -3.1, 0.60), back, up, lift=0.005, grid=(16, 1),
             kind=bk.LAMP)
    # Tailgate: the invented badge and a plate recess in the bumper.
    bk.patch(surf, shell, m["Chrome"], _triangle(0.12, 0.08), (0, -3.1, 0.44), back, up, lift=0.005, grid=(3, 3))
    bk.patch(surf, shell, m["Paint"], _triangle(0.07, 0.045), (0, -3.1, 0.432), back, up, lift=0.0065, grid=(3, 3))
    bk.patch(surf, rear, m["Trim"], bk.rect(0.52, 0.12), (0, -3.1, 0.18), back, up, lift=0.004, grid=2)
    # One long wiper resting at the bottom of the windscreen.
    a = math.atan2(1.31 - 0.612, Y_NOSE - Y_PEAK)
    y0 = WS_BASE - 0.08
    bk.box(shell, m["Trim"], (0.05, y0, ridge(y0) + 0.02), (1.25, 0.022, 0.014), rot=(-a, 0, 0))
    # A tow hitch under the rear bumper.
    bk.box(shell, m["Trim"], (0, -2.90, 0.06), (0.07, 0.14, 0.07))


def _interior(shell, m):
    """A dark cabin round the seated driver (the scene's seat numbers,
    ART_BIBLE.md §34): a deep flat dash under the long windscreen with a big
    landscape screen in the middle, two front seats and a rear bench, a wide
    console, and a wall behind the rear bench (the bed is behind it)."""
    im = m["Interior"]
    bk.box(shell, im, (0, 0.06, -0.05), (1.86, 2.26, 0.02))                  # floor
    bk.box(shell, im, (0, 0.98, 0.50), (1.86, 0.46, 0.24))                   # dash
    bk.box(shell, im, (0, 0.30, 0.08), (0.30, 0.90, 0.24))                   # console
    bk.box(shell, im, (0, 0.73, 0.73), (0.46, 0.04, 0.27), rot=(math.radians(-20), 0, 0))
    bk.box(shell, m["GlassDark"], (0, 0.707, 0.737), (0.43, 0.006, 0.24), rot=(math.radians(-20), 0, 0))
    for sx in (-1, 1):
        x = sx * 0.42
        bk.box(shell, im, (x, 0.28, 0.105), (0.52, 0.52, 0.15), bevel=0.04, segments=1)                     # cushion
        bk.box(shell, im, (x, -0.03, 0.50), (0.52, 0.13, 0.66), bevel=0.05, rot=(math.radians(-12), 0, 0), segments=1)
        bk.box(shell, im, (x, -0.11, 0.89), (0.26, 0.10, 0.15), rot=(math.radians(-12), 0, 0))           # headrest
    # Rear bench, and the wall behind it.
    bk.box(shell, im, (0, -0.56, 0.10), (1.70, 0.50, 0.15), bevel=0.04, segments=1)
    bk.box(shell, im, (0, -0.86, 0.46), (1.70, 0.13, 0.62), bevel=0.05, rot=(math.radians(-14), 0, 0), segments=1)
    bk.box(shell, im, (0, -1.04, 0.27), (1.96, 0.03, 0.66))
    bk.box(shell, im, (0, -1.04, 0.86), (1.50, 0.03, 0.54))
    # Steering wheel where the seated driver's hands reach (the scene's
    # steering_wheel), on a column into the dash.
    c = (-0.42, 0.51, 0.59)
    bk.torus(shell, m["Trim"], c, 0.17, 0.018, 16, 5, tilt=math.radians(-25))
    bk.box(shell, m["Trim"], (c[0], c[1] - 0.005, c[2]), (0.1, 0.03, 0.08))
    bk.tube(shell, m["Trim"], (-0.42, 0.54, 0.58), (-0.42, 0.86, 0.48), 0.025, 8)


def _mirrors(shell, m):
    """Small angular mirrors on the doors below the A pillar: steel caps on
    black arms."""
    for sx in (-1, 1):
        y, z = 1.12, 0.72
        x = sx * (W - 0.006 - LEAN * (z - belt(y)) + 0.10)
        bk.box(shell, m["Paint"], (x, y, z), (0.16, 0.10, 0.11))
        bk.box(shell, m["Chrome"], (x, y - 0.052, z), (0.13, 0.006, 0.085))
        bk.box(shell, m["Trim"], (x - sx * 0.09, y + 0.01, z - 0.04), (0.08, 0.05, 0.04))


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
