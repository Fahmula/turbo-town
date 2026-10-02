"""Generates the pickup body (pickup_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_pickup.py

Design language (ART_BIBLE.md §12): a full-size American-style pickup. Tall
flat bonnet with a power bulge, a huge chrome-framed grille, big square
headlights, chrome bumpers, black wheel-arch flares, an upright crew cab
with running boards, and a separate open bed (black liner, wheel tubs,
tailgate, tall tail lights). Optional racing stripes (garage only).

Built from two lofts: the front + cab (standard section) and the bed (a U
section). Conventions: front = Blender +Y, origin at wheel-centre height
between the axles, matching scenes/vehicles/pickup.tscn (wheels r 0.40 at
x +-0.86, axles +-1.60). Ground is z = -0.40. Wheels: wheel_offroad.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.60
ARCH_R = 0.40 + 0.06
FLOOR = -0.14
BED_FRONT, BED_BACK = -0.70, -2.68
RAIL = 0.64
BED_FLOOR = 0.12


def _cab_materials(body, j, y):
    if y > 2.28 and j <= 4:
        return "Chrome"                                  # chrome front bumper
    if j in (2, 3) and abs(y - AXLE_Y) < ARCH_R + 0.05:
        return "Trim"                                    # black wheel-arch flare
    return ""


CAB = bk.LoftBody(bk.BodySpec(
    y_nose=2.58, y_tail=-0.64, nose0=2.40, tail0=-0.60, nose_p=3.0, tail_p=6.0,
    floor=FLOOR,
    axles=[(AXLE_Y, ARCH_R)],
    width=bk.curve([(2.40, 0.94), (2.0, 0.965), (1.6, 0.97), (0.5, 0.965), (-0.64, 0.965)]),
    shoulder=bk.curve([(2.58, 0.42), (2.5, 0.55), (2.3, 0.60), (1.8, 0.62), (0.98, 0.64), (-0.64, 0.66)]),
    ws_base=0.98, roof_front=0.42, roof_rear=-0.56, rw_base=-0.64,
    roof_edge=bk.curve([(0.98, 0.64), (0.80, 0.86), (0.60, 1.08), (0.42, 1.27), (0.2, 1.31), (-0.2, 1.32),
                        (-0.56, 1.31), (-0.64, 0.68)]),
    glass_top=1.27,
    crown=bk.curve([(2.58, 0.0), (2.3, 0.03), (1.2, 0.035), (0.98, 0.02), (0.6, 0.03), (-0.64, 0.03)]),
    roof_w=bk.curve([(0.98, 0.84), (0.42, 0.80), (-0.64, 0.80)]),
    windows=[(0.90, -0.02), (-0.10, -0.52)],
    pillar_mat="Trim",
    door_lines=[(1.074, 1.066), (-0.056, -0.064)],
    top_lines=[(2.424, 2.416), (0.98, 0.95)],
    bumper_split=(2.28, -9.0), bumper_row=5,
    shoulder_inset=0.03, hood_edge_inset=0.10, bulge=0.006,
    station_step=0.16,
    material_override=_cab_materials,
))


def _bed_section(body, y):
    """U section: outer side, a capped rail, the inner wall and the floor."""
    s = body.s
    k = body.wrap(y)
    w = s.width(min(max(y, s.tail0), s.nose0))
    zb, a = body.arch(y)
    off3 = bk.lerp(0.035, 0.012, a)
    off4 = bk.lerp(0.10, 0.03, a)
    z4 = zb + off4
    iw = w - 0.075                                       # inner wall
    # Over the wheels the side follows the arch, but the middle of the
    # underside stays below the bed floor (or it would poke through).
    p = [(0.0, min(zb, BED_FLOOR - 0.04)), (w - 0.07, zb), (w - 0.012, zb + off3), (w - 0.002, z4),
         (w + 0.006, bk.lerp(z4, RAIL, 0.4)), (w + 0.006, bk.lerp(z4, RAIL, 0.8)),
         (w, RAIL - 0.025), (w - 0.012, RAIL), (iw + 0.012, RAIL), (iw, RAIL - 0.025),
         (iw, BED_FLOOR + 0.02), (iw - 0.02, BED_FLOOR), (iw * 0.5, BED_FLOOR), (0.0, BED_FLOOR)]
    return [(x * k, z) for (x, z) in p]


def _bed_materials(body, j, y):
    if j <= 2:
        return "Trim"
    if j == 3 and abs(y + AXLE_Y) < ARCH_R + 0.05:
        return "Trim"                                    # flare
    if j <= 6:
        return "Paint"
    if j == 7:
        return "Trim"                                    # black rail cap
    return "Trim"                                        # bed liner


BED = bk.LoftBody(bk.BodySpec(
    y_nose=BED_FRONT, y_tail=BED_BACK, nose0=BED_FRONT - 0.03, tail0=BED_BACK + 0.03, nose_p=8.0, tail_p=8.0,
    floor=FLOOR,
    axles=[(-AXLE_Y, ARCH_R)],
    width=lambda y: 0.965,
    shoulder=lambda y: RAIL,
    bumper_split=(9.0, -9.0),
    station_step=0.16,
    nose_samples=(0.5, 1.0), tail_samples=(0.5, 1.0),
    section_override=_bed_section,
    material_override=_bed_materials,
))


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.784, 0.137, 0.106))
    shell, front, _rear, ys = CAB.build(m, "PickupBody")
    bed, _f, _r, _bys = BED.build(m, "bed")
    bk.merge(shell, bed)
    surf = bk.Surface([shell, front])
    _details(surf, shell, front, m)
    bk.box(shell, m["Trim"], (0, 2.36, -0.04), (1.4, 0.2, 0.16))          # crash beam
    rear = bk.Part("RearBumper", [])
    bk.box(rear, m["Chrome"], (0, -2.77, -0.06), (1.84, 0.16, 0.2), bevel=0.02, segments=1)
    bk.box(rear, m["Trim"], (0, -2.80, 0.045), (0.5, 0.11, 0.012))         # step pad
    bk.box(shell, m["Trim"], (0, -2.70, -0.06), (1.3, 0.12, 0.12))         # hitch beam behind it
    _interior(shell, m, ys)
    stripes = _stripes(surf)
    objs = [p.to_object(math.radians(60)) for p in (shell, front, rear, stripes)]
    bk.export(objs, "pickup_body.glb")


def _details(surf, shell, front, m):
    fwd = (0, -1, -0.15)
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Big square headlights beside the grille.
        hx = sx * 0.72
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.26, 0.22), (hx, 2.8, 0.27), fwd, up, lift=0.004)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.20, 0.08), (hx, 2.8, 0.31), fwd, up, lift=0.006, kind=bk.LAMP)
        # Amber parking / turn lamp under it.
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.20, 0.06), (hx, 2.8, 0.215), fwd, up, lift=0.006, kind=bk.INDICATOR)
        # Fog lamps in the chrome bumper.
        bk.patch(surf, front, m["Headlight"], bk.ellipse(0.10, 0.07), (sx * 0.62, 2.8, -0.03), (0, -1, 0), up, lift=0.004, kind=bk.AUX)
        # Door handles, running boards, big mirrors.
        for y in (0.42, -0.42):
            bk.patch(surf, shell, m["Trim"], bk.rect(0.17, 0.035), (sx * 1.3, y, 0.55), (-sx, 0, 0), up, lift=0.004, grid=3)
        bk.box(shell, m["Trim"], (sx * 1.03, 0.2, -0.13), (0.16, 1.5, 0.05))
        bk.box(shell, m["Trim"], (sx * 0.97, 0.2, -0.105), (0.04, 1.3, 0.04))
        bk.box(shell, m["Trim"], (sx * 1.14, 0.84, 0.82), (0.07, 0.16, 0.26), bevel=0.02, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.14, 0.757, 0.82), (0.055, 0.006, 0.22))
        bk.tube(shell, m["Trim"], (sx * 0.95, 0.88, 0.76), (sx * 1.12, 0.85, 0.76), 0.02, 6)
        # Bed: tall tail lights on the rear corners, wheel tubs inside.
        bk.patch(surf, shell, m["Trim"], bk.rect(0.13, 0.42), (sx * 0.88, -3.0, 0.40), (0, 1, 0), up, lift=0.003, grid=(2, 4))
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.10, 0.24), (sx * 0.88, -3.0, 0.47), (0, 1, 0), up, lift=0.005, grid=(2, 3),
                 kind=bk.LAMP)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.10, 0.055), (sx * 0.88, -3.0, 0.565), (0, 1, 0), up, lift=0.007, grid=2,
                 kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.10, 0.08), (sx * 0.88, -3.0, 0.29), (0, 1, 0), up, lift=0.005, grid=2,
                 kind=bk.LAMP)
        bk.box(shell, m["Trim"], (sx * 0.76, -AXLE_Y, 0.30), (0.25, 0.92, 0.38), bevel=0.06, segments=1)
    # Big chrome-framed grille with a dark mesh and a centre bar; badge.
    bk.patch(surf, shell, m["Chrome"], bk.rect(1.10, 0.28), (0, 2.8, 0.26), fwd, up, lift=0.004, grid=(6, 3))
    bk.patch(surf, shell, m["Trim"], bk.rect(1.02, 0.21), (0, 2.8, 0.26), fwd, up, lift=0.006, grid=(6, 3), kind=bk.GRILLE_MESH)
    bk.patch(surf, shell, m["Chrome"], bk.rect(1.02, 0.03), (0, 2.8, 0.26), fwd, up, lift=0.008, grid=(6, 1))
    bk.patch(surf, shell, m["Chrome"], bk.rect(0.16, 0.09), (0, 2.8, 0.26), fwd, up, lift=0.010, grid=2)
    # Cab back: third brake light. Tailgate handle.
    bk.patch(surf, shell, m["TailLight"], bk.rect(0.26, 0.03), (0, -1.2, 1.26), (0, 1, 0), up, lift=0.004, grid=(3, 1), kind=bk.BRAKE_ONLY)
    bk.patch(surf, shell, m["Trim"], bk.rect(0.22, 0.05), (0, -3.0, 0.52), (0, 1, 0), up, lift=0.004, grid=2)
    bk.tube(shell, m["Chrome"], (0.55, -2.4, -0.13), (0.55, -2.72, -0.13), 0.04, 10)


def _interior(shell, m, ys):
    CAB.inner_cabin(shell, m, ys, 0.92, -0.58)
    im = m["Interior"]
    bk.box(shell, im, (0, 0.2, -0.08), (1.8, 1.5, 0.02))                     # floor
    bk.box(shell, im, (0, 0.82, 0.50), (1.84, 0.30, 0.24))                   # dash
    for sx in (-1, 1):
        x = sx * 0.44
        bk.box(shell, im, (x, 0.30, 0.06), (0.52, 0.52, 0.16), bevel=0.04, segments=1)
        bk.box(shell, im, (x, 0.0, 0.46), (0.52, 0.13, 0.66), bevel=0.05, rot=(math.radians(-10), 0, 0), segments=1)
    bk.box(shell, im, (0, -0.32, 0.06), (1.7, 0.46, 0.16), bevel=0.04, segments=1)   # rear bench
    bk.box(shell, im, (0, -0.52, 0.44), (1.7, 0.12, 0.62), bevel=0.05, segments=1)
    c = (-0.44, 0.58, 0.62)
    bk.torus(shell, m["Trim"], c, 0.19, 0.02, 16, 5, tilt=math.radians(-28))
    bk.tube(shell, m["Trim"], (-0.44, 0.61, 0.61), (-0.44, 0.8, 0.52), 0.025, 8)


def _stripes(surf):
    """Optional twin stripes over the bonnet and roof (garage only)."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    for sx in (-1, 1):
        for (y0, y1, n) in ((2.44, 1.02, 16), (0.36, -0.50, 6)):
            bk.patch(surf, part, mat, bk.rect(0.20, y0 - y1), (sx * 0.15, (y0 + y1) / 2, 3.0),
                     (0, 0, -1), (0, 1, 0), lift=0.005, grid=(1, n))
    return part


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
