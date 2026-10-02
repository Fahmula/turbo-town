"""Generates the monster truck body (monster_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_monster.py

Design language (ART_BIBLE.md §12): a retro 80s/90s show truck. A boxy,
upright regular-cab pickup body with quad square headlights, a chrome grille
and bumper, lifted high on a visible tube chassis: four-link suspension
bars, chrome coil-over shocks, solid axles with diff housings, skid plate.
Roll bar in the bed, roof light bar, chrome exhaust stacks. Optional bold
side stripes (garage only).

The body is narrow enough (half width 0.92) that the giant tyres sit fully
outboard, so suspension travel never pushes them through it.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/monster_truck.tscn (wheels r 0.95 at x
+-1.32, axles +-1.65). Ground is z = -0.95. Wheels: wheel_offroad.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.65
FLOOR = 0.72                 # body underside: high above the axles
HALF_W = 0.92
RAIL, BED_FLOOR = 1.46, 1.0
BED_FRONT, BED_BACK = -0.62, -2.25


def _cab_materials(body, j, y):
    if y > 2.12 and j <= 4:
        return "Chrome"
    return ""


CAB = bk.LoftBody(bk.BodySpec(
    y_nose=2.30, y_tail=-0.55, nose0=2.18, tail0=-0.52, nose_p=4.0, tail_p=8.0,
    floor=FLOOR,
    width=lambda y: HALF_W,
    shoulder=bk.curve([(2.30, 1.25), (2.25, 1.38), (2.1, 1.42), (0.92, 1.44), (-0.55, 1.46)]),
    ws_base=0.92, roof_front=0.42, roof_rear=-0.48, rw_base=-0.55,
    roof_edge=bk.curve([(0.92, 1.44), (0.75, 1.64), (0.58, 1.84), (0.42, 2.0), (0.0, 2.03), (-0.48, 2.02),
                        (-0.55, 1.47)]),
    glass_top=2.0,
    crown=bk.curve([(2.30, 0.0), (2.1, 0.02), (0.92, 0.02), (0.6, 0.025), (-0.55, 0.02)]),
    roof_w=lambda y: 0.80,
    windows=[(0.82, -0.44)],
    pillar_mat="Paint",
    door_lines=[(0.954, 0.946), (-0.476, -0.484)],
    top_lines=[(2.124, 2.116), (0.92, 0.89)],
    bumper_split=(2.12, -9.0), bumper_row=5,
    shoulder_inset=0.025, hood_edge_inset=0.10, bulge=0.004,
    station_step=0.16,
    material_override=_cab_materials,
))


def _bed_section(body, y):
    s = body.s
    k = body.wrap(y)
    w = HALF_W
    zb = FLOOR
    iw = w - 0.07
    p = [(0.0, zb), (w - 0.06, zb), (w - 0.012, zb + 0.03), (w - 0.002, zb + 0.09),
         (w + 0.004, bk.lerp(zb + 0.09, RAIL, 0.4)), (w + 0.004, bk.lerp(zb + 0.09, RAIL, 0.8)),
         (w, RAIL - 0.025), (w - 0.012, RAIL), (iw + 0.012, RAIL), (iw, RAIL - 0.025),
         (iw, BED_FLOOR + 0.02), (iw - 0.02, BED_FLOOR), (iw * 0.5, BED_FLOOR), (0.0, BED_FLOOR)]
    return [(x * k, z) for (x, z) in p]


def _bed_materials(body, j, y):
    if j <= 2:
        return "Trim"
    if j <= 6:
        return "Paint"
    return "Trim"                                        # rail caps and liner


BED = bk.LoftBody(bk.BodySpec(
    y_nose=BED_FRONT, y_tail=BED_BACK, nose0=BED_FRONT - 0.03, tail0=BED_BACK + 0.03, nose_p=8.0, tail_p=8.0,
    floor=FLOOR, width=lambda y: HALF_W, shoulder=lambda y: RAIL,
    bumper_split=(9.0, -9.0), station_step=0.16, nose_samples=(0.5, 1.0), tail_samples=(0.5, 1.0),
    section_override=_bed_section, material_override=_bed_materials,
))


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.32, 0.16, 0.5))
    m["Frame"] = bk.material("Frame", (0.12, 0.12, 0.14), rough=0.5, metal=0.4)
    shell, front, _rear, ys = CAB.build(m, "MonsterBody")
    bed, _f, _r, _b = BED.build(m, "bed")
    bk.merge(shell, bed)
    surf = bk.Surface([shell, front])
    _details(surf, shell, front, m)
    _chassis(shell, m)
    bk.box(shell, m["Frame"], (0, 2.05, FLOOR + 0.12), (1.3, 0.16, 0.16))    # crash beam
    rear = bk.Part("RearBumper", [])
    bk.box(rear, m["Chrome"], (0, -2.33, FLOOR + 0.06), (1.86, 0.16, 0.2), bevel=0.02, segments=1)
    _interior(shell, m, ys)
    stripes = _stripes(surf)
    objs = [p.to_object(math.radians(55)) for p in (shell, front, rear, stripes)]
    bk.export(objs, "monster_body.glb")


def _details(surf, shell, front, m):
    fwd = (0, -1, 0)
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Quad square headlights either side of the grille.
        for k in (0, 1):
            x = sx * (0.52 + k * 0.2)
            bk.patch(surf, shell, m["Chrome"], bk.rect(0.18, 0.16), (x, 2.6, 1.15), fwd, up, lift=0.004, grid=2)
            bk.patch(surf, shell, m["Headlight"], bk.rect(0.14, 0.12), (x, 2.6, 1.15), fwd, up, lift=0.006, grid=2, kind=bk.LAMP)
        # Tail lights on the bed corners, door handle, big mirrors.
        bk.patch(surf, shell, m["Trim"], bk.rect(0.12, 0.34), (sx * 0.84, -2.6, 1.20), (0, 1, 0), up, lift=0.003, grid=(2, 3))
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.09, 0.2), (sx * 0.84, -2.6, 1.25), (0, 1, 0), up, lift=0.005, grid=2, kind=bk.LAMP)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.09, 0.07), (sx * 0.84, -2.6, 1.10), (0, 1, 0), up, lift=0.005, grid=2,
                 kind=bk.LAMP)
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.15, 0.03), (sx * 1.3, 0.0, 1.38), (-sx, 0, 0), up, lift=0.004, grid=3)
        bk.box(shell, m["Chrome"], (sx * 1.02, 0.80, 1.62), (0.06, 0.14, 0.2), bevel=0.02, segments=1)
        bk.tube(shell, m["Chrome"], (sx * 0.9, 0.84, 1.55), (sx * 1.0, 0.82, 1.58), 0.015, 6)
        # Chrome exhaust stacks behind the cab.
        bk.tube(shell, m["Chrome"], (sx * 0.72, -0.60, 1.30), (sx * 0.72, -0.60, 2.35), 0.06, 12)
        bk.tube(shell, m["Trim"], (sx * 0.72, -0.60, 2.349), (sx * 0.72, -0.60, 2.352), 0.045, 12)
        # Roll bar in the bed.
        bk.tube(shell, m["Frame"], (sx * 0.78, -0.9, 1.0), (sx * 0.74, -0.9, 2.05), 0.045, 10)
        bk.tube(shell, m["Frame"], (sx * 0.74, -0.9, 2.05), (sx * 0.72, -1.5, 1.42), 0.04, 10)
    bk.tube(shell, m["Frame"], (-0.74, -0.9, 2.05), (0.74, -0.9, 2.05), 0.045, 10)
    # Chrome grille with dark slots.
    bk.patch(surf, shell, m["Chrome"], bk.rect(0.62, 0.24), (0, 2.6, 1.13), fwd, up, lift=0.004, grid=(4, 2))
    for k in range(3):
        bk.patch(surf, shell, m["Trim"], bk.rect(0.56, 0.035), (0, 2.6, 1.05 + k * 0.075), fwd, up, lift=0.006, grid=(4, 1))
    # Roof light bar with four lamps.
    bk.box(shell, m["Frame"], (0, 0.2, 2.10), (1.30, 0.14, 0.11))
    for k in range(4):
        bk.box(shell, m["Headlight"], (-0.48 + k * 0.32, 0.272, 2.10), (0.2, 0.012, 0.08), kind=bk.AUX)


def _chassis(shell, m):
    f = m["Frame"]
    for sx in (-1, 1):
        bk.box(shell, f, (sx * 0.42, 0.0, 0.52), (0.12, 4.2, 0.18))            # frame rails
        for y in (AXLE_Y, -AXLE_Y):
            d = math.copysign(1, y)
            # Four-link bars from the frame to the axle.
            bk.tube(shell, f, (sx * 0.42, y - 0.75 * d, 0.48), (sx * 0.6, y, 0.12), 0.05, 8)
            bk.tube(shell, f, (sx * 0.30, y - 0.95 * d, 0.40), (sx * 0.5, y, -0.12), 0.05, 8)
            # Coil-over shock: chrome body, painted spring, mounted to the frame.
            top = (sx * 0.62, y - 0.25 * d, 0.70)
            bot = (sx * 0.82, y - 0.05 * d, 0.02)
            bk.tube(shell, m["Chrome"], top, bot, 0.05, 10)
            mid = tuple((a + b) / 2 for a, b in zip(top, bot))
            bk.tube(shell, m["Paint"], tuple(a + (b - a) * 0.25 for a, b in zip(top, mid)),
                    tuple(b + (a - b) * 0.25 for a, b in zip(top, mid)), 0.075, 10)
    for y in (AXLE_Y, -AXLE_Y):
        bk.tube(shell, f, (-0.95, y, 0.0), (0.95, y, 0.0), 0.10, 12)          # axle
        bk.box(shell, f, (0.0, y, 0.0), (0.42, 0.34, 0.36), bevel=0.05, segments=1)   # diff
    for y in (1.0, 0.0, -1.0):
        bk.box(shell, f, (0, y, 0.52), (0.84, 0.1, 0.12))                       # cross members
    bk.box(shell, f, (0, 2.0, 0.40), (0.9, 0.5, 0.04), rot=(math.radians(-15), 0, 0))   # skid plate
    bk.tube(shell, f, (0.0, 0.6, 0.45), (0.0, -0.9, 0.45), 0.06, 8)            # drive shaft


def _interior(shell, m, ys):
    CAB.inner_cabin(shell, m, ys, 0.86, -0.50)
    im = m["Interior"]
    bk.box(shell, im, (0, 0.2, FLOOR + 0.05), (1.6, 1.2, 0.02))
    bk.box(shell, im, (0, 0.78, 1.30), (1.66, 0.28, 0.22))
    bk.box(shell, im, (0, -0.15, FLOOR + 0.20), (1.5, 0.5, 0.16), bevel=0.04, segments=1)   # bench seat
    bk.box(shell, im, (0, -0.38, 1.25), (1.5, 0.12, 0.62), bevel=0.05, segments=1)
    c = (-0.40, 0.55, 1.42)
    bk.torus(shell, m["Trim"], c, 0.19, 0.02, 16, 5, tilt=math.radians(-28))
    bk.tube(shell, m["Trim"], (-0.40, 0.58, 1.41), (-0.40, 0.76, 1.32), 0.025, 8)


def _stripes(surf):
    """Optional bold side stripes running from the front wing to the bed."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    for sx in (-1, 1):
        for (z, h) in ((1.20, 0.10), (1.06, 0.05)):
            for (y0, y1, n) in ((2.16, -0.50, 11), (-0.67, -2.20, 7)):         # cab, bed
                bk.patch(surf, part, mat, bk.rect(y0 - y1, h), (sx * 1.6, (y0 + y1) / 2, z), (-sx, 0, 0), (0, 0, 1),
                         lift=0.005, grid=(n, 1))
    return part


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
