"""Generates the electric pickup body (electric_pickup_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_electric_pickup.py

Design language (ART_BIBLE.md §12): a futuristic electric pickup, asked for
by the owner's son. Bare brushed stainless steel and flat panels with crisp
creases: a triangular side view, with the bonnet and a huge windscreen
rising in one straight line to a peak over the B pillar and the roof falling
in another straight line over a covered bed (a ribbed dark cover between two
wide steel sails) to the tailgate. A near-vertical steel front face under a
full-width light bar that wraps round the corners, a second lamp strip low
on it; a black band and a full-width tail light bar along the tailgate's top
edge. Vertical flat sides with one sharp crease under the windows, the upper
sides leaning in, wide steel frames over the windows, a black B pillar.
Chunky black cladding that stands off the body: angular arch flares, rocker
strips between them, and protruding bumpers with a shelf on top that wrap
round the corners to the flares. No grille, hidden door handles, black
angular mirrors, no exhaust. One long wiper. An invented badge (a triangle)
on the tailgate; no real maker's name, badge or logo.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/electric_pickup.tscn (wheels r 0.44 at x
+-0.83, axles +-1.88). Ground is z = -0.44. Its wheel is wheel_facet.glb
(make_wheels.py: the facet aero cover on the all-terrain tyre).

The body is a LoftBody with its own section (straight lines instead of the
cars' curves) but the standard 19 points, so inner_cabin, the garage's paint
lines and the kits work as on every other vehicle. The cladding is swept
along paths (arch outlines, sills, the bumpers' plan outline): flares and
rockers are part of the shell (they dent with it), the bumpers are the
FrontBumper / RearBumper meshes that fall off.
"""
import math
import os
import sys

import bmesh
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

V = mathutils.Vector

AXLE_Y = 1.88
W = 0.985                        # half width of the flat sides (the flares stand off them)
FLOOR = -0.10                    # underbody: 34 cm ground clearance
Y_NOSE, Y_TAIL = 2.74, -2.86
Y_PEAK = -0.30                   # the roof's peak, over the B pillar
LEAN = 0.42                      # upper sides lean in (m in per m up), ~23 deg
CROWN = 0.025
# Trapezoid wheel arches: a flat top over the tyre (r 0.44, 8 cm gap) and
# straight sides down to the floor.
ARCH_TOP, ARCH_TOP_HALF, ARCH_FOOT_HALF = 0.52, 0.34, 0.58
FLARE_W, FLARE_OUT = 0.10, 0.045   # arch flare band width, how far it stands off the side
ROCKER_W, ROCKER_OUT = 0.18, 0.025
# Where the bonnet turns into the windscreen, and the glass on top.
WS_BASE = 1.66
GLASS_TOP = [(WS_BASE, -0.24), (-0.36, -1.00)]   # windscreen, roof glass
TONNEAU = (-1.10, -2.79)                          # the bed's hard cover
# The shell is black below these heights at the ends, behind the bumpers.
FRONT_BUMPER = (2.38, 0.27)
REAR_BUMPER = (-2.62, 0.28)
WINDOWS = [(1.10, 0.0), (-0.10, -1.02)]
B_PILLAR = (0.0, -0.10)
WINDOW_FRAME = 0.085             # steel over the side windows
DOOR_LINES = [(1.164, 1.156), (-0.046, -0.054), (-1.096, -1.104)]
TOP_LINES = [(WS_BASE + 0.024, WS_BASE + 0.016), (TONNEAU[0] + 0.004, TONNEAU[0] - 0.004),
             (TONNEAU[1] + 0.004, TONNEAU[1] - 0.004)]


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


belt = lin([(Y_NOSE, 0.63), (Y_TAIL, 0.68)])                     # the side crease
ridge = lin([(Y_NOSE, 0.642), (Y_PEAK, 1.31), (Y_TAIL, 0.73)])   # top edge of the upper sides
# The underside rises at the ends: a chin behind the front bumper, then the
# near-vertical steel front face up to the light bar; the departure angle
# under the rear bumper.
FRONT_FACE = [(2.42, FLOOR), (2.60, 0.0), (2.68, 0.25), (Y_NOSE, 0.60)]
ends = lin(FRONT_FACE)
tail_rise = lin([(-2.50, FLOOR), (-2.74, 0.06), (Y_TAIL, 0.10)])


def _in_bumper(y):
    return y > FRONT_BUMPER[0] or y < REAR_BUMPER[0]


def _bumper_line(y):
    return FRONT_BUMPER[1] if y > 0.0 else REAR_BUMPER[1]


def _y_on_face(z):
    """Where the front face is at height z (a station there keeps the
    bumper line straight across it)."""
    for (y0, z0), (y1, z1) in zip(FRONT_FACE, FRONT_FACE[1:]):
        if z0 <= z <= z1:
            return y0 + (y1 - y0) * (z - z0) / (z1 - z0)
    return FRONT_FACE[-1][0]


Y_FRONT_LINE = _y_on_face(FRONT_BUMPER[1])


def top_band(y):
    """Width of the steel strip along the top edge: the A pillars / roof
    rails, the wide sail tops beside the bed cover."""
    return bk.lerp(0.09, 0.15, bk.smoothstep(TONNEAU[0] + 0.05, TONNEAU[0] - 0.05, y))


def roof_edge_w(y):
    """Half width of the top edge (where the upper sides meet the top)."""
    z_sh = belt(y)
    return W - 0.026 - LEAN * (max(ridge(y), z_sh + 0.012) - z_sh)


class Truck(bk.LoftBody):
    """A LoftBody with straight-lined sections, trapezoid arches and
    rounded-off corners at the nose (plan view)."""

    def wrap(self, y):
        s = self.s
        if y > s.nose0:
            t = (y - s.nose0) / (s.y_nose - s.nose0)
            return 0.0 if t > 0.999 else 1.0 - 0.13 * t ** 1.5
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
        w_re = roof_edge_w(y)
        z6 = z_sh - 0.015
        room = max(z6 - zb, 0.0)
        z2 = zb + min(0.015, room * 0.2)
        # The shell's own black band along the sills and round the arches
        # (the swept cladding covers it).
        z3 = zb + min(bk.lerp(0.18, 0.07, a), room * 0.45)
        # Row 4 runs along the bumpers' top edge wherever it fits, so the
        # black ends on a straight line (the sides are flat, so moving the
        # row changes nothing else).
        line = _bumper_line(y)
        if y > self.s.nose0:
            # The front face's corners: no cladding, the low rows hug the
            # bottom edge so row 4 can stay on the line until the bottom
            # edge reaches it.
            z2 = zb + min(0.004, room * 0.1)
            z3 = zb + min(0.008, room * 0.2)
            z4 = line if zb + 0.012 < line else zb + min(0.012, room * 0.3)
        else:
            if _in_bumper(y) and zb < line - 0.03:
                z3 = min(z3, line - 0.02)
            z4 = line if z3 + 0.005 < line < z6 - 0.01 else bk.lerp(z3, z6, 0.33)
        p = [(0.0, zb), (W - 0.10, zb), (W - 0.045, z2), (W - 0.012, z3),
             (W, z4), (W, bk.lerp(z4, z6, 0.5)), (W, z6), (W - 0.006, z_sh)]
        # The upper side: one flat facet leaning in to the top edge, with a
        # wide steel frame over the windows.
        p7, p12 = p[-1], (w_re, z_re)
        lx, lz = p12[0] - p7[0], p12[1] - p7[1]
        ln = max(math.hypot(lx, lz), 1e-4)
        for f in (min(0.02 / ln, 0.2), 0.4, 0.7, 1.0 - min(WINDOW_FRAME / ln, 0.4)):
            p.append((p7[0] + lx * f, p7[1] + lz * f))
        p.append(p12)
        # The top: a steel edge strip, a 4 cm dark band (glass frit, cover
        # gap), then nearly flat across with a slight crown.
        ub = min(top_band(y) / max(w_re, 1e-3), 0.3)
        for u in (ub, ub + min(0.04 / max(w_re, 1e-3), 0.1), 0.38, 0.58, 0.8, 1.0):
            p.append((w_re * (1.0 - u), z_re + CROWN * (1.0 - (1.0 - u) ** 2)))
        return [(x * k, z) for (x, z) in p]

    def material_key(self, j, y):
        pts = self.section(0, y)
        zc = (pts[j][1] + pts[j + 1][1]) * 0.5
        if j <= 6:
            # Black at the ends behind the bumpers; above them the front
            # face and the tailgate are steel.
            if _in_bumper(y) and zc < _bumper_line(y):
                return "Trim"
            if y > 2.55 or y < -2.80:
                return "Paint"
            if j <= 2:
                return "Trim"                                   # underbody, rocker / arch band
            if any(bk.within(y, d) for d in DOOR_LINES):
                return "Trim"
            return "Paint"
        if j <= 10:
            if any(bk.within(y, w) for w in WINDOWS):
                return "Glass"
            if bk.within(y, B_PILLAR):
                return "GlassDark"                              # black B pillar
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

    def inner_cabin(self, shell, m, ys, y_front, y_back, every=2):
        """As LoftBody's, plus the inside of the steel upper sides (ahead of
        and between the windows), seen through the long windscreen."""
        super().inner_cabin(shell, m, ys, y_front, y_back, every)
        inner = [y for y in ys if y_front > y > y_back][::every]

        def inner_section(i, y):
            pts = self.section(i, y)
            out = []
            for j, (x, z) in enumerate(pts):
                a = pts[max(j - 1, 0)]
                b = pts[min(j + 1, len(pts) - 1)]
                tx, tz = b[0] - a[0], b[1] - a[1]
                ln = max(math.hypot(tx, tz), 1e-5)
                out.append((max(x - tz / ln * 0.018, 0.0), z + tx / ln * 0.018))
            return out

        def inner_mat(_i, j, y0, y1):
            y = (y0 + y1) * 0.5
            if 7 <= j <= 10 and not any(bk.within(y, w) for w in WINDOWS):
                return m["Interior"]
            return None
        tmp = bk.Part("inner_upper", list(shell.mats))
        bk.loft(tmp, inner, inner_section, inner_mat)
        bmesh.ops.reverse_faces(tmp.bm, faces=tmp.bm.faces[:])
        bk.merge(shell, tmp)


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
    keep=[Y_PEAK, 2.42, 2.55, 2.60, 2.68, Y_FRONT_LINE, -0.36, -1.00, TONNEAU[0], TONNEAU[1], -2.50, -2.74,
          AXLE_Y + ARCH_TOP_HALF, AXLE_Y - ARCH_TOP_HALF, -AXLE_Y + ARCH_TOP_HALF, -AXLE_Y - ARCH_TOP_HALF],
    nose_samples=(0.2, 0.4, 0.6, 0.8, 0.9, 0.97, 1.0),
    tail_samples=(0.5, 0.95, 1.0),
    station_step=0.17,
    arch_step=0.12,
)
BODY = Truck(SPEC)


# ------------------------------------------------------------ cladding ---

def _sweep(part, mat, frames, profile):
    """A closed tube: the closed `profile` [(a, b)] placed at every frame
    (point, a axis, b axis), capped at both ends, normals out."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p + ua * a + ub * b) for (a, b) in profile] for (p, ua, ub) in frames]
    n = len(profile)
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(n):
            j1 = (j + 1) % n
            bm.faces.new([r0[j], r0[j1], r1[j1], r1[j]])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bk._append(part, bm, mat)


def _dense(points, step):
    """The polyline with extra points so no piece is longer than `step`
    (dents need vertices to bend)."""
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.ceil(math.dist(a, b) / step)))
        out += [tuple(a[i] + (b[i] - a[i]) * k / n for i in range(len(a))) for k in range(1, n + 1)]
    return out


def _side_frames(path, sx, x0):
    """Frames along a side-view path [(y, z)] on the side at x = sx * x0: a
    points out of the side, b is the path's normal in side view (to the
    left of travel: away from an arch opening, up from a sill)."""
    frames = []
    for i, (y, z) in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        t = V((0, b[0] - a[0], b[1] - a[1])).normalized()
        frames.append((V((sx * x0, y, z)), V((sx, 0, 0)), V((0, t.z, -t.y))))
    return frames


def _clad_profile(width, out):
    """Cross-section of a flare or rocker strip: a lip tucked under the
    opening edge, the outer face standing `out` off the side, a bevel back
    to the body, and a back face buried in it."""
    return [(-0.03, 0.0), (out, 0.0), (out - 0.006, width * 0.65), (0.003, width), (-0.03, width)]


def _cladding(shell, m):
    """Black arch flares (trapezoids following each arch outline) and rocker
    strips along the sills between them."""
    for sx in (-1, 1):
        for ay in (AXLE_Y, -AXLE_Y):
            path = _dense([(ay + ARCH_FOOT_HALF, FLOOR), (ay + ARCH_TOP_HALF, ARCH_TOP),
                           (ay - ARCH_TOP_HALF, ARCH_TOP), (ay - ARCH_FOOT_HALF, FLOOR)], 0.11)
            _sweep(shell, m["Trim"], _side_frames(path, sx, W), _clad_profile(FLARE_W, FLARE_OUT))
        sill = _dense([(AXLE_Y - ARCH_FOOT_HALF + 0.02, FLOOR), (-AXLE_Y + ARCH_FOOT_HALF - 0.02, FLOOR)], 0.2)
        _sweep(shell, m["Trim"], _side_frames(sill, sx, W), _clad_profile(ROCKER_W, ROCKER_OUT))


def _plan_frames(half_path):
    """Frames along a plan-view path [(x, y)] (the right half, from the
    middle out), mirrored to a full path: a points outward in plan, b up."""
    pts = [(-x, y) for (x, y) in reversed(half_path[1:])] + list(half_path)
    frames = []
    for i, (x, y) in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = V((b[0] - a[0], b[1] - a[1], 0)).normalized()
        frames.append((V((x, y, 0)), t, V((0, 0, 1))))
    return frames


def _bumper(name, m, half_path, profile, outward_sign):
    """A chunky black bumper with a shelf on top, swept round the plan
    outline (front, corner chamfers, a short run back along each side)."""
    part = bk.Part(name, [])
    frames = []
    for (p, t, up) in _plan_frames(half_path):
        n = V((t.y, -t.x, 0)) * outward_sign     # outward in plan
        frames.append((p, n, up))
    _sweep(part, m["Trim"], frames, profile)
    return part


def _bumpers(m):
    front = _bumper("FrontBumper", m, _dense([(0.0, 2.745), (0.86, 2.745), (W + 0.02, 2.65), (W + 0.03, 2.43)], 0.15),
                    [(-0.11, 0.255), (-0.012, 0.255), (0.0, 0.243), (0.0, 0.04), (-0.03, -0.02), (-0.15, -0.08),
                     (-0.15, 0.10)], -1)
    rear = _bumper("RearBumper", m, _dense([(0.0, -2.97), (0.84, -2.97), (W + 0.02, -2.84), (W + 0.03, -2.57)], 0.15),
                   [(-0.11, 0.27), (-0.012, 0.27), (0.0, 0.258), (0.0, 0.03), (-0.03, -0.01), (-0.15, -0.02),
                    (-0.15, 0.12)], 1)
    return front, rear


# --------------------------------------------------------------- build ---

def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.72, 0.73, 0.75))
    shell, _f, _r, ys = BODY.build(m, "ElectricPickupBody", bumpers=False)
    _cladding(shell, m)
    front, rear = _bumpers(m)
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    BODY.inner_cabin(shell, m, ys, 1.62, -1.06)
    bk.box(shell, m["Trim"], (0, 2.50, 0.06), (1.5, 0.16, 0.14))          # crash beams behind the bumpers
    bk.box(shell, m["Trim"], (0, -2.78, 0.12), (1.5, 0.12, 0.14))
    _interior(shell, m)
    _mirrors(shell, m)
    objs = [p.to_object(math.radians(22)) for p in (shell, front, rear)]
    bk.export(objs, "electric_pickup_body.glb")


def _face_dir():
    """Projection direction onto the steel front face (from in front,
    looking back and a little up)."""
    (y0, z0), (y1, z1) = FRONT_FACE[-2], FRONT_FACE[-1]
    n = math.hypot(y1 - y0, z1 - z0)
    return (0, -(z1 - z0) / n, (y1 - y0) / n)


def _corner_dir(sx, t):
    """Projection direction onto the nose's rounded-off corner (plan view)
    at `t` (0 where it starts, 1 at the tip), and the surface point there."""
    s = SPEC
    dxdy = -W * 0.13 * 1.5 * t ** 0.5 / (s.y_nose - s.nose0)
    n = V((1.0, -dxdy, 0)).normalized()          # outward normal of x(y) on the right
    return (-sx * n.x, -n.y, 0.0), (sx * W * (1 - 0.13 * t ** 1.5), s.nose0 + t * (s.y_nose - s.nose0))


def _triangle(w, h):
    """Outline helper: a triangle, point up."""
    def f(u, v):
        return (u - 0.5) * w * (1.0 - v), (v - 0.5) * h
    return f


def _tonneau_outline(y0, y1):
    """The bed cover between the sails, narrowing toward the cab: v runs
    from y0 to y1, s across (patch from above, up = +y)."""
    yc = (y0 + y1) * 0.5

    def f(u, v):
        y = y0 + (y1 - y0) * v
        half = roof_edge_w(y) - top_band(y) - 0.05
        return (u - 0.5) * 2.0 * half, y - yc
    return f


def _details(surf, shell, front, rear, m):
    up = (0, 0, 1)
    face = _face_dir()
    back = (0, 1, 0)
    # The light bar along the nose's top edge: a black housing, a running
    # light the full width and round the corners, amber indicators near its
    # ends; the headlamps are a second strip low on the steel face, just
    # above the bumper.
    # (Patches centred on the face, so their rays pass over the bumper.)
    zb = 0.613
    bk.patch(surf, shell, m["Trim"], bk.rect(1.74, 0.04), (0, Y_NOSE, zb), face, up, lift=0.003, grid=(10, 1))
    bk.patch(surf, shell, m["Headlight"], bk.rect(1.70, 0.014), (0, Y_NOSE, zb), face, up, lift=0.006,
             grid=(10, 1), kind=bk.DRL)
    zl = 0.292
    bk.patch(surf, shell, m["Trim"], bk.rect(1.56, 0.032), (0, _y_on_face(zl), zl), face, up, lift=0.003, grid=(8, 1))
    bk.patch(surf, shell, m["Headlight"], bk.rect(1.50, 0.016), (0, _y_on_face(zl), zl), face, up, lift=0.006,
             grid=(8, 1), kind=bk.LAMP)
    for sx in (-1, 1):
        # The bar wraps round the corner in short straight pieces.
        for k, t in enumerate((0.42, 0.66, 0.86)):
            d, (cx, cy) = _corner_dir(sx, t)
            c = (cx - d[0] * 0.6, cy - d[1] * 0.6, zb)
            bk.patch(surf, shell, m["Trim"], bk.rect(0.075, 0.04), c, d, up, lift=0.003 + 0.0004 * k, grid=(2, 2))
            bk.patch(surf, shell, m["Headlight"], bk.rect(0.07, 0.014), c, d, up, lift=0.006 + 0.0004 * k, grid=(2, 1),
                     kind=bk.DRL)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.06, 0.016), (sx * 0.80, Y_NOSE, zb), face, up, lift=0.008,
                 grid=(2, 1), kind=bk.INDICATOR)
        # The tail light bar's amber ends, reverse lamps low on the
        # tailgate, reflectors in the bumper.
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.07, 0.022), (sx * 0.86, -3.2, 0.652), back, up, lift=0.007,
                 grid=(2, 1), kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.12, 0.03), (sx * 0.70, -3.2, 0.33), back, up, lift=0.005,
                 grid=(2, 1), kind=bk.LAMP)
        bk.patch(surf, rear, m["TailLight"], bk.rect(0.14, 0.025), (sx * 0.75, -3.2, 0.13), back, up, lift=0.004,
                 grid=(3, 1))
    # A wide slatted intake across the front bumper.
    bk.patch(surf, front, m["Trim"], bk.rect(1.10, 0.10, 0.2), (0, 3.2, 0.13), (0, -1, 0), up, lift=0.004,
             grid=(8, 2), kind=bk.GRILLE_SLATS)
    # Tailgate: a black band along the top edge, the tail light bar under
    # it, the invented badge.
    bk.patch(surf, shell, m["Trim"], bk.rect(1.84, 0.055), (0, -3.2, 0.6975), back, up, lift=0.003, grid=(10, 1))
    bk.patch(surf, shell, m["TailLight"], bk.rect(1.62, 0.022), (0, -3.2, 0.652), back, up, lift=0.005, grid=(10, 1),
             kind=bk.LAMP)
    bk.patch(surf, shell, m["Chrome"], _triangle(0.12, 0.08), (0, -3.2, 0.50), back, up, lift=0.005, grid=(3, 3))
    bk.patch(surf, shell, m["Paint"], _triangle(0.07, 0.045), (0, -3.2, 0.492), back, up, lift=0.0065, grid=(3, 3))
    # The bed cover's ribs (slats every 26 mm, vehicle_trim.gdshader).
    y0, y1 = TONNEAU[0] - 0.04, TONNEAU[1] + 0.03
    bk.patch(surf, shell, m["Trim"], _tonneau_outline(y0, y1), (0, (y0 + y1) * 0.5, 3.0), (0, 0, -1), (0, 1, 0),
             lift=0.004, grid=(4, 12), kind=bk.GRILLE_SLATS)
    # One long wiper resting at the bottom of the windscreen.
    a = math.atan2(1.31 - 0.642, Y_NOSE - Y_PEAK)
    yw = WS_BASE - 0.08
    bk.box(shell, m["Trim"], (0.05, yw, ridge(yw) + 0.02), (1.25, 0.022, 0.014), rot=(-a, 0, 0))
    # A tow hitch under the rear bumper.
    bk.box(shell, m["Trim"], (0, -2.98, -0.04), (0.07, 0.14, 0.07))


def _interior(shell, m):
    """A dark cabin round the seated driver (the scene's seat numbers,
    ART_BIBLE.md §34): a deep flat dash running forward under the long
    windscreen with a big landscape screen in the middle, two front seats
    and a rear bench, a wide console, and a wall behind the rear bench (the
    bed is behind it)."""
    im = m["Interior"]
    bk.box(shell, im, (0, 0.06, -0.05), (1.86, 2.26, 0.02))                  # floor
    bk.box(shell, im, (0, 1.195, 0.50), (1.86, 0.89, 0.24))                  # dash
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
    bk.box(shell, im, (0, -1.04, 0.27), (1.92, 0.03, 0.66))
    bk.box(shell, im, (0, -1.04, 0.86), (1.48, 0.03, 0.54))
    # Steering wheel where the seated driver's hands reach (the scene's
    # steering_wheel), on a column into the dash.
    c = (-0.42, 0.51, 0.59)
    bk.torus(shell, m["Trim"], c, 0.17, 0.018, 16, 5, tilt=math.radians(-25))
    bk.box(shell, m["Trim"], (c[0], c[1] - 0.005, c[2]), (0.1, 0.03, 0.08))
    bk.tube(shell, m["Trim"], (-0.42, 0.54, 0.58), (-0.42, 0.86, 0.48), 0.025, 8)


def _mirrors(shell, m):
    """Black angular mirrors on the front corner of the doors, swept back,
    on short arms."""
    for sx in (-1, 1):
        y, z = 1.13, belt(1.13) + 0.085
        x_side = W - 0.006 - LEAN * (z - belt(y))
        x = sx * (x_side + 0.11)
        rot = (0, 0, math.radians(-14 * sx))
        bk.box(shell, m["Trim"], (x, y, z), (0.19, 0.075, 0.10), rot=rot)
        bk.box(shell, m["Chrome"], (x + sx * 0.005, y - 0.04, z), (0.16, 0.006, 0.08), rot=rot)
        bk.box(shell, m["Trim"], (sx * (x_side + 0.01), y + 0.02, z - 0.03), (0.06, 0.05, 0.04))


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
