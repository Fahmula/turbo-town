"""Generates the sedan body (sedan_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_sedan.py

Design language (ART_BIBLE.md §12): a sensible mid-2000s Japanese-style
family sedan. Three boxes, an upright cabin with six side windows, black
B-pillars, chrome window trim and grille bar, body-coloured bumpers, big
swept headlights and wide tail lights that wrap onto the boot lid. Taller
and plainer than the sports car on purpose.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/sedan.tscn (wheels r 0.34 at x +-0.80,
axles +-1.40). Ground is z = -0.34. Its wheel is wheel_sedan.glb
(make_wheels.py).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.40
ARCH_R = 0.34 + 0.045
WINDOWS = [(0.72, -0.20), (-0.28, -1.0), (-1.06, -1.30)]


def _chrome_belt(body, j, y):
    """Chrome window trim along the belt line (instead of black)."""
    span = (WINDOWS[0][0], WINDOWS[-1][1])
    if j == 7 and bk.within(y, span):
        return "Chrome"
    return ""


SPEC = bk.BodySpec(
    y_nose=2.33, y_tail=-2.33, nose0=2.12, tail0=-2.15, nose_p=2.2, tail_p=3.5,
    floor=-0.20,
    axles=[(AXLE_Y, ARCH_R), (-AXLE_Y, ARCH_R)],
    width=bk.curve([(2.12, 0.855), (1.85, 0.895), (1.40, 0.91), (0.6, 0.91), (-0.6, 0.912),
                    (-1.40, 0.915), (-1.9, 0.905), (-2.15, 0.875)]),
    # A fairly straight belt that rises gently toward the high boot deck.
    shoulder=bk.curve([(2.33, 0.20), (2.2, 0.30), (2.0, 0.40), (1.6, 0.47), (1.0, 0.50), (0.78, 0.51),
                       (0.0, 0.53), (-0.8, 0.555), (-1.5, 0.58), (-2.0, 0.585), (-2.2, 0.56), (-2.33, 0.46)]),
    ws_base=0.78, roof_front=0.02, roof_rear=-1.0, rw_base=-1.62,
    roof_edge=bk.curve([(0.78, 0.51), (0.55, 0.68), (0.30, 0.87), (0.02, 1.07), (-0.25, 1.095),
                        (-0.5, 1.10), (-0.75, 1.095), (-1.0, 1.07), (-1.2, 0.95), (-1.42, 0.76),
                        (-1.62, 0.585)]),
    glass_top=1.07,
    crown=bk.curve([(2.33, 0.0), (2.0, 0.02), (1.0, 0.025), (0.8, 0.02), (0.6, 0.03), (0.0, 0.035),
                    (-1.0, 0.035), (-1.6, 0.02), (-2.33, 0.015)]),
    roof_w=bk.curve([(0.78, 0.70), (0.02, 0.66), (-0.5, 0.65), (-1.0, 0.66), (-1.62, 0.70)]),
    windows=WINDOWS,
    pillar_mat="Trim",
    door_lines=[(0.954, 0.946), (-0.236, -0.244), (-0.996, -1.004)],
    top_lines=[(2.104, 2.096), (0.78, 0.745), (-1.62, -1.645), (-2.126, -2.134)],
    bumper_split=(1.92, -1.92),
    shoulder_inset=0.035, hood_edge_inset=0.10, bulge=0.010,
    rocker_mat="Paint",
    station_step=0.165,
    material_override=_chrome_belt,
)
BODY = bk.LoftBody(SPEC)


def build():
    bk.reset_scene()
    m = bk.vehicle_materials()
    shell, front, rear, ys = BODY.build(m, "SedanBody")
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    bk.box(shell, m["Trim"], (0, 2.02, -0.07), (1.32, 0.2, 0.15))     # crash beams
    bk.box(shell, m["Trim"], (0, -2.04, -0.04), (1.32, 0.2, 0.15))
    _interior(shell, m, ys)
    for sx in (-1, 1):
        bk.box(shell, m["Paint"], (sx * 1.0, 0.63, 0.64), (0.15, 0.09, 0.11), bevel=0.03, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.0, 0.584, 0.64), (0.12, 0.006, 0.085))
        bk.box(shell, m["Trim"], (sx * 0.92, 0.66, 0.58), (0.08, 0.05, 0.05))
    objs = [p.to_object(math.radians(60)) for p in (shell, front, rear)]
    bk.export(objs, "sedan_body.glb")


def _details(surf, shell, front, rear, m):
    fwd = (0, -1, -0.3)
    back = (0, 1, -0.1)
    up = (0, 0, 1)
    side = lambda sx: (-sx, 0, 0)  # noqa: E731
    for sx in (-1, 1):
        # Big swept headlights: chrome reflector, clear strip, two lamps.
        hx = sx * 0.55
        bk.patch(surf, shell, m["Trim"], bk.rect(0.40, 0.15, 0.4), (hx, 2.4, 0.26), fwd, up, lift=0.003)
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.37, 0.125, 0.4), (hx, 2.4, 0.26), fwd, up, lift=0.005)
        bk.patch(surf, shell, m["Headlight"], bk.ellipse(0.11, 0.08), (hx + sx * 0.07, 2.4, 0.26), fwd, up, lift=0.007, kind=bk.LAMP)
        bk.patch(surf, shell, m["Headlight"], bk.ellipse(0.09, 0.07), (hx - sx * 0.07, 2.4, 0.25), fwd, up, lift=0.007, kind=bk.LAMP)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.042, 0.06, 0.3), (hx + sx * 0.157, 2.4, 0.255), fwd, up, lift=0.007, grid=3,
                 kind=bk.INDICATOR)
        # Fog lamps in the bumper.
        bk.patch(surf, front, m["Chrome"], bk.ellipse(0.10, 0.06), (sx * 0.62, 2.4, -0.06), (0, -1, 0), up, lift=0.004)
        # Tail lights wrapping from the wing onto the boot lid.
        tx = sx * 0.59
        bk.patch(surf, shell, m["Trim"], bk.rect(0.42, 0.15, 0.3), (tx, -2.4, 0.45), back, up, lift=0.003)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.39, 0.125, 0.3), (tx, -2.4, 0.45), back, up, lift=0.005, kind=bk.LAMP)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.10, 0.05, 0.3), (sx * 0.72, -2.4, 0.475), back, up, lift=0.007, grid=3,
                 kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.11, 0.045), (sx * 0.46, -2.4, 0.43), back, up, lift=0.007, grid=3, kind=bk.LAMP)
        # Chrome door handles.
        for y in (0.30, -0.62):
            bk.patch(surf, shell, m["Chrome"], bk.rect(0.15, 0.025), (sx * 1.2, y, 0.46), side(sx), up, lift=0.004, grid=3)
    # Chrome grille bar over a dark grille, and the bumper's lower intake.
    bk.patch(surf, shell, m["Trim"], bk.rect(0.66, 0.11, 0.3), (0, 2.4, 0.15), (0, -1, -0.1), up, lift=0.003, kind=bk.GRILLE_SLATS)
    bk.patch(surf, shell, m["Chrome"], bk.rect(0.68, 0.025, 0.3), (0, 2.4, 0.20), (0, -1, -0.1), up, lift=0.005, grid=3)
    bk.patch(surf, front, m["Trim"], bk.rect(0.78, 0.07, 0.5), (0, 2.4, -0.07), (0, -1, 0), up, lift=0.003, kind=bk.GRILLE_MESH)
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.08, 0.05), (0, 2.4, 0.15), (0, -1, -0.1), up, lift=0.007)
    # Chrome garnish on the boot between the lights, plate recess below.
    bk.patch(surf, shell, m["Chrome"], bk.rect(0.40, 0.03), (0, -2.4, 0.46), back, up, lift=0.004, grid=3)
    bk.patch(surf, rear, m["Trim"], bk.rect(0.52, 0.13), (0, -2.4, -0.05), (0, 1, 0), up, lift=0.003)
    # Exhaust.
    bk.tube(shell, m["Chrome"], (0.55, -2.15, -0.17), (0.55, -2.36, -0.17), 0.035, 10)
    bk.tube(shell, m["Trim"], (0.55, -2.3595, -0.17), (0.55, -2.3615, -0.17), 0.026, 10)


def _interior(shell, m, ys):
    BODY.inner_cabin(shell, m, ys, 0.74, -1.58)
    im = m["Interior"]
    bk.box(shell, im, (0, -0.4, -0.14), (1.66, 2.1, 0.02))                    # floor
    bk.box(shell, im, (0, 0.62, 0.38), (1.68, 0.32, 0.22))                   # dash
    bk.box(shell, im, (0, -1.35, 0.52), (1.64, 0.5, 0.02))                   # parcel shelf
    bk.box(shell, im, (0, 0.1, -0.03), (0.2, 0.7, 0.2))                      # console
    for sx in (-1, 1):
        x = sx * 0.40
        bk.box(shell, im, (x, -0.02, -0.03), (0.50, 0.50, 0.15), bevel=0.04, segments=1)
        bk.box(shell, im, (x, -0.33, 0.33), (0.50, 0.13, 0.62), bevel=0.05, rot=(math.radians(-12), 0, 0), segments=1)
        bk.box(shell, im, (x, -0.40, 0.70), (0.26, 0.10, 0.14), rot=(math.radians(-12), 0, 0))
    bk.box(shell, im, (0, -0.92, -0.01), (1.5, 0.48, 0.16), bevel=0.04, segments=1)  # rear bench
    bk.box(shell, im, (0, -1.15, 0.30), (1.5, 0.13, 0.55), bevel=0.05, rot=(math.radians(-15), 0, 0), segments=1)
    c = (-0.40, 0.38, 0.42)
    bk.torus(shell, m["Trim"], c, 0.18, 0.018, 16, 5, tilt=math.radians(-25))
    bk.box(shell, m["Trim"], (c[0], c[1] - 0.005, c[2]), (0.1, 0.03, 0.08))
    bk.tube(shell, m["Trim"], (-0.40, 0.41, 0.41), (-0.40, 0.6, 0.34), 0.025, 8)


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
