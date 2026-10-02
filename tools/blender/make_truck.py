"""Generates the delivery truck body (truck_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_truck.py

Design language (ART_BIBLE.md §12): a Japanese-style cab-over light truck.
Flat-fronted cab with a near-vertical wrap-round windscreen, a black bumper
band with headlights above it and a black grille band, cab steps and big
mirrors on arms; a white aluminium cargo box with corner posts, ribs, a
livery band in the cab colour and a roller door; visible chassis rails, fuel
tank, side guards, mud flaps and a rear under-run bar.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/box_truck.tscn (wheels r 0.45 at x +-0.95,
axles +-1.90; cab over the front axle). Ground is z = -0.45. The scene's
"TURBO DELIVERY" labels sit on the box sides (x +-1.165, z 1.75, y -1.425).
Wheels: wheel_steel.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.90
ARCH_R = 0.45 + 0.06
BOX_FRONT, BOX_BACK = 0.98, -3.80
BOX_BOTTOM, BOX_TOP, BOX_HW = 0.55, 2.85, 1.15


def _cab_materials(body, j, y):
    if y > 2.75 and j <= 4:
        return "Trim"                                    # black bumper band
    if body.region(y) == "rw" and j >= 13:
        return "Paint"                                   # solid cab back
    return ""


CAB = bk.LoftBody(bk.BodySpec(
    y_nose=3.06, y_tail=1.04, nose0=2.90, tail0=1.07, nose_p=3.0, tail_p=8.0,
    floor=-0.12,
    axles=[(AXLE_Y, ARCH_R)],
    width=lambda y: 1.04,
    shoulder=bk.curve([(3.06, 0.90), (2.9, 0.94), (1.04, 0.97)]),
    ws_base=3.05, roof_front=2.80, roof_rear=1.10, rw_base=1.04,
    roof_edge=bk.curve([(3.05, 0.95), (3.0, 1.30), (2.95, 1.65), (2.86, 1.90), (2.75, 1.99), (2.3, 2.02),
                        (1.5, 2.02), (1.10, 2.0), (1.04, 0.97)]),
    glass_top=1.92,
    crown=bk.curve([(3.06, 0.04), (2.8, 0.04), (2.6, 0.03), (1.04, 0.03)]),
    roof_w=lambda y: 0.94,
    windows=[(2.74, 1.60)],
    pillar_mat="Trim",
    door_lines=[(2.794, 2.786), (1.564, 1.556)],
    bumper_split=(2.75, -9.0), bumper_row=5,
    shoulder_inset=0.03, hood_edge_inset=0.08, bulge=0.005,
    station_step=0.16,
    material_override=_cab_materials,
))


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.902, 0.902, 0.882))
    m["Box"] = bk.material("Box", (0.88, 0.88, 0.86), rough=0.55)
    shell, front, _rear, ys = CAB.build(m, "TruckBody")
    _cargo_box(shell, m)
    surf = bk.Surface([shell, front])
    _details(surf, shell, front, m)
    _chassis(shell, m)
    bk.box(shell, m["Trim"], (0, 2.92, 0.05), (1.5, 0.2, 0.2))            # crash beam
    rear = bk.Part("RearBumper", [])
    bk.box(rear, m["Trim"], (0, -3.84, 0.02), (2.1, 0.1, 0.13), bevel=0.015, segments=1)
    for sx in (-1, 1):
        bk.box(rear, m["Trim"], (sx * 0.5, -3.78, 0.3), (0.06, 0.06, 0.5))
    _interior(shell, m, ys)
    objs = [p.to_object(math.radians(55)) for p in (shell, front, rear)]
    bk.export(objs, "truck_body.glb")


def _cargo_box(shell, m):
    """Aluminium box: dentable panels, corner posts, top rails, side ribs,
    a livery band and a roller door."""
    mid_y = (BOX_FRONT + BOX_BACK) / 2
    length = BOX_FRONT - BOX_BACK
    mid_z = (BOX_BOTTOM + BOX_TOP) / 2
    height = BOX_TOP - BOX_BOTTOM
    bk.panel_box(shell, m["Box"], (0, mid_y, mid_z), (BOX_HW * 2, length, height), step=0.4)
    post = m["Chrome"]
    for sx in (-1, 1):
        for y in (BOX_FRONT, BOX_BACK):
            bk.box(shell, post, (sx * BOX_HW, y, mid_z), (0.06, 0.06, height + 0.02))
        bk.box(shell, post, (sx * BOX_HW, mid_y, BOX_TOP), (0.06, length, 0.06))
        bk.box(shell, post, (sx * BOX_HW, mid_y, BOX_BOTTOM), (0.07, length, 0.08))
        for k in range(1, 6):                                                 # ribs
            y = BOX_FRONT - length * k / 6
            bk.box(shell, m["Box"], (sx * (BOX_HW + 0.012), y, mid_z), (0.024, 0.05, height - 0.1))
        bk.box(shell, m["Paint"], (sx * (BOX_HW + 0.006), mid_y, BOX_BOTTOM + 0.22), (0.014, length - 0.1, 0.16))
    for y in (BOX_FRONT, BOX_BACK):
        bk.box(shell, post, (0, y, BOX_TOP), (BOX_HW * 2, 0.06, 0.06))
    # Roller door: slats and a handle on the back face.
    for k in range(12):
        z = BOX_BOTTOM + 0.12 + k * 0.18
        bk.box(shell, m["Box"], (0, BOX_BACK - 0.01, z), (BOX_HW * 2 - 0.2, 0.012, 0.03))
    bk.box(shell, m["Trim"], (0, BOX_BACK - 0.03, BOX_BOTTOM + 0.2), (0.4, 0.04, 0.06))
    # Rear lights low on the box, clearance lights at the top corners.
    for sx in (-1, 1):
        bk.box(shell, m["TailLight"], (sx * 0.86, BOX_BACK - 0.025, BOX_BOTTOM + 0.13), (0.20, 0.03, 0.12), kind=bk.LAMP)
        bk.box(shell, m["TailLight"], (sx * 1.04, BOX_BACK - 0.025, BOX_BOTTOM + 0.13), (0.12, 0.03, 0.12), kind=bk.INDICATOR)
        bk.box(shell, m["ReverseLight"], (sx * 0.62, BOX_BACK - 0.025, BOX_BOTTOM + 0.13), (0.12, 0.03, 0.1), kind=bk.LAMP)
        bk.box(shell, m["TailLight"], (sx * 1.0, BOX_BACK - 0.025, BOX_TOP - 0.1), (0.08, 0.03, 0.05), kind=bk.DRL)


def _details(surf, shell, front, m):
    fwd = (0, -1, 0)
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Rectangular headlights above the bumper band, turn lamps outside.
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.34, 0.17), (sx * 0.70, 3.3, 0.42), fwd, up, lift=0.004)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.28, 0.12), (sx * 0.70, 3.3, 0.42), fwd, up, lift=0.006, kind=bk.LAMP)
        bk.patch(surf, front, m["Headlight"], bk.rect(0.18, 0.07), (sx * 0.70, 3.3, 0.12), fwd, up, lift=0.004, grid=2,
                 kind=bk.INDICATOR)
        # Cab steps and big black mirrors (plus a kerb mirror).
        bk.box(shell, m["Trim"], (sx * 1.02, 2.1, -0.02), (0.14, 0.5, 0.04))
        bk.box(shell, m["Trim"], (sx * 1.02, 2.1, 0.32), (0.12, 0.5, 0.04))
        bk.box(shell, m["Trim"], (sx * 1.24, 2.86, 1.45), (0.07, 0.18, 0.40), bevel=0.02, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.24, 2.77, 1.45), (0.055, 0.006, 0.35))
        bk.tube(shell, m["Trim"], (sx * 1.0, 2.85, 1.3), (sx * 1.22, 2.86, 1.3), 0.02, 6)
        bk.tube(shell, m["Trim"], (sx * 1.0, 2.85, 1.62), (sx * 1.22, 2.86, 1.62), 0.02, 6)
        bk.box(shell, m["Trim"], (sx * 1.12, 3.0, 1.1), (0.06, 0.12, 0.12))
        # Door handles.
        bk.patch(surf, shell, m["Trim"], bk.rect(0.16, 0.04), (sx * 1.4, 1.75, 0.92), (-sx, 0, 0), up, lift=0.004, grid=3)
    # Grille band and badge on the flat front, small rear window on the cab back.
    bk.patch(surf, shell, m["Trim"], bk.rect(1.10, 0.16), (0, 3.3, 0.66), fwd, up, lift=0.004, grid=(6, 2), kind=bk.GRILLE_SLATS)
    bk.patch(surf, shell, m["Chrome"], bk.rect(0.32, 0.06), (0, 3.3, 0.82), fwd, up, lift=0.004, grid=2)


def _chassis(shell, m):
    t = m["Trim"]
    for sx in (-1, 1):
        bk.box(shell, t, (sx * 0.45, -1.45, 0.40), (0.12, 4.9, 0.30))           # frame rails
        bk.box(shell, t, (sx * 1.05, -0.2, 0.2), (0.05, 1.5, 0.05))            # side guard
        bk.box(shell, t, (sx * 1.05, -0.2, 0.0), (0.05, 1.5, 0.05))
        for y in (0.45, -0.85):                                                # its hangers
            bk.box(shell, t, (sx * 1.05, y, 0.27), (0.04, 0.05, 0.56))
        bk.box(shell, t, (sx * 0.95, -2.5, 0.15), (0.42, 0.03, 0.72))          # mud flap
    for y in (0.6, -0.9, -2.4, -3.6):
        bk.box(shell, t, (0, y, 0.40), (0.9, 0.1, 0.16))                       # cross members
    bk.tube(shell, m["Chrome"], (0.72, -0.1, 0.30), (0.72, -0.85, 0.30), 0.2, 14)   # fuel tank
    bk.box(shell, t, (-0.72, -0.6, 0.33), (0.3, 0.5, 0.36))                     # battery box
    bk.tube(shell, m["Chrome"], (-0.6, -2.9, -0.05), (-1.0, -3.0, -0.05), 0.045, 10)


def _interior(shell, m, ys):
    CAB.inner_cabin(shell, m, ys, 2.86, 1.08)
    im = m["Interior"]
    bk.box(shell, im, (0, 2.0, 0.45), (1.9, 1.6, 0.03))                       # floor (cab floor is high)
    bk.box(shell, im, (0, 2.82, 0.86), (1.96, 0.3, 0.22))                     # dash
    for x in (-0.55, 0.0, 0.55):
        bk.box(shell, im, (x, 1.9, 0.6), (0.48, 0.48, 0.14), bevel=0.04, segments=1)
        bk.box(shell, im, (x, 1.62, 1.0), (0.48, 0.12, 0.62), bevel=0.05, rot=(math.radians(-8), 0, 0), segments=1)
    c = (-0.55, 2.58, 1.02)
    bk.torus(shell, m["Trim"], c, 0.21, 0.02, 16, 5, tilt=math.radians(-55))
    bk.tube(shell, m["Trim"], (-0.55, 2.6, 0.99), (-0.55, 2.8, 0.82), 0.03, 8)


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
