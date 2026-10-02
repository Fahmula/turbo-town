"""Generates the van body (van_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_van.py

Design language (ART_BIBLE.md §12): a modern European-style medium van
(passenger "kombi"). One box with a short sloping bonnet, a steep
windscreen and a tall, nearly upright body; big side windows with black
pillars; unpainted black lower cladding and bumpers all round; a sliding-door
rail; big black mirrors; tall corner tail lights and twin rear doors.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/van.tscn (wheels r 0.36 at x +-0.86, axles
+-1.50). Ground is z = -0.36. Wheels: wheel_steel.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.50
ARCH_R = 0.36 + 0.05


def _cladding(body, j, y):
    """Black plastic sills all round; the bumpers are black up to their top."""
    if j <= 3:
        return "Trim"
    if j == 4 and not (-2.34 < y < 2.22):
        return "Trim"
    return ""


SPEC = bk.BodySpec(
    y_nose=2.46, y_tail=-2.52, nose0=2.25, tail0=-2.42, nose_p=2.0, tail_p=5.0,
    floor=-0.18,
    axles=[(AXLE_Y, ARCH_R), (-AXLE_Y, ARCH_R)],
    width=bk.curve([(2.25, 0.90), (2.0, 0.95), (1.5, 0.972), (0.0, 0.978), (-1.5, 0.978), (-2.42, 0.97)]),
    shoulder=bk.curve([(2.46, 0.30), (2.3, 0.48), (2.1, 0.60), (1.85, 0.67), (1.72, 0.70), (0.0, 0.72),
                       (-2.52, 0.73)]),
    # The roof runs all the way to the back, so the rear never closes down.
    ws_base=1.72, roof_front=0.85, roof_rear=-2.6, rw_base=-2.6,
    roof_edge=bk.curve([(1.72, 0.70), (1.45, 0.98), (1.15, 1.28), (0.85, 1.55), (0.6, 1.60),
                        (0.0, 1.62), (-1.0, 1.62), (-2.0, 1.615), (-2.52, 1.60)]),
    glass_top=1.55,
    crown=bk.curve([(2.46, 0.0), (2.0, 0.02), (1.72, 0.02), (1.5, 0.03), (0.0, 0.03), (-2.52, 0.03)]),
    roof_w=bk.curve([(1.72, 0.88), (0.85, 0.87), (-2.52, 0.87)]),
    windows=[(1.62, 0.92), (0.80, -0.55), (-0.68, -2.30)],   # cab door, sliding door, rear quarter
    pillar_mat="Trim",
    door_lines=[(1.722, 1.714), (0.804, 0.796), (-0.656, -0.664)],
    top_lines=[(2.304, 2.296), (1.72, 1.69)],
    bumper_split=(2.22, -2.34), bumper_row=5,     # bumpers = the full black cladding
    shoulder_inset=0.035, hood_edge_inset=0.10, bulge=0.008,
    station_step=0.18,
    material_override=_cladding,
)
BODY = bk.LoftBody(SPEC)


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.902, 0.902, 0.882))
    shell, front, rear, ys = BODY.build(m, "VanBody")
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    bk.box(shell, m["Trim"], (0, 2.14, -0.05), (1.40, 0.2, 0.16))        # crash beams
    bk.box(shell, m["Trim"], (0, -2.30, -0.05), (1.40, 0.2, 0.16))
    _interior(shell, m, ys)
    for sx in (-1, 1):
        # Big black mirrors on arms.
        bk.box(shell, m["Trim"], (sx * 1.10, 1.58, 0.98), (0.07, 0.15, 0.30), bevel=0.02, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.10, 1.505, 0.98), (0.055, 0.006, 0.26))
        bk.tube(shell, m["Trim"], (sx * 0.95, 1.64, 0.86), (sx * 1.08, 1.6, 0.9), 0.02, 6)
        bk.tube(shell, m["Trim"], (sx * 0.95, 1.64, 1.08), (sx * 1.08, 1.6, 1.06), 0.02, 6)
    objs = [p.to_object(math.radians(60)) for p in (shell, front, rear)]
    bk.export(objs, "van_body.glb")


def _details(surf, shell, front, rear, m):
    fwd = (0, -1, -0.35)
    back = (0, 1, 0)
    up = (0, 0, 1)
    for sx in (-1, 1):
        # Large headlights sweeping up the bonnet edge.
        hx = sx * 0.6
        bk.patch(surf, shell, m["Trim"], bk.rect(0.40, 0.18, 0.5), (hx, 2.6, 0.48), fwd, up, lift=0.003)
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.37, 0.15, 0.5), (hx, 2.6, 0.48), fwd, up, lift=0.005)
        bk.patch(surf, shell, m["Headlight"], bk.ellipse(0.13, 0.10), (hx + sx * 0.07, 2.6, 0.48), fwd, up, lift=0.007, kind=bk.LAMP)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.30, 0.025), (hx, 2.6, 0.545), fwd, up, lift=0.007, grid=(4, 1), kind=bk.DRL)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.11, 0.055, 0.3), (hx - sx * 0.10, 2.6, 0.47), fwd, up, lift=0.007, grid=3,
                 kind=bk.INDICATOR)
        # Fog lamps in the black bumper.
        bk.patch(surf, front, m["Chrome"], bk.ellipse(0.09, 0.06), (sx * 0.66, 2.6, 0.02), (0, -1, 0), up, lift=0.004)
        # Tall corner tail lights with a reverse lamp in the middle.
        tx = sx * 0.80
        bk.patch(surf, shell, m["Trim"], bk.rect(0.15, 0.60), (tx, -2.7, 0.62), back, up, lift=0.003, grid=(2, 6))
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.12, 0.25), (tx, -2.7, 0.78), back, up, lift=0.005, grid=(2, 3), kind=bk.LAMP)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.12, 0.09), (tx, -2.7, 0.58), back, up, lift=0.005, grid=2, kind=bk.LAMP)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.12, 0.12), (tx, -2.7, 0.45), back, up, lift=0.005, grid=2, kind=bk.INDICATOR)
        # Rear door windows (dark glass painted on), handles.
        bk.patch(surf, shell, m["GlassDark"], bk.rect(0.56, 0.52, 0.15), (sx * 0.36, -2.7, 1.20), back, up, lift=0.004)
        # Black rubbing strip along the sides.
        bk.patch(surf, shell, m["Trim"], bk.rect(3.9, 0.06), (sx * 1.3, -0.05, 0.28), (-sx, 0, 0), up, lift=0.004, grid=(16, 1))
        # Sliding door rail and handle (right side only, like a real van; both
        # sides get the rail so it reads from either side).
        bk.patch(surf, shell, m["Trim"], bk.rect(1.5, 0.03), (sx * 1.3, -1.45, 0.66), (-sx, 0, 0), up, lift=0.004, grid=(8, 1))
        bk.patch(surf, shell, m["Trim"], bk.rect(0.16, 0.03), (sx * 1.3, 0.62, 0.62), (-sx, 0, 0), up, lift=0.004, grid=3)
        bk.patch(surf, shell, m["Trim"], bk.rect(0.16, 0.03), (sx * 1.3, -0.40, 0.62), (-sx, 0, 0), up, lift=0.004, grid=3)
    # Grille between the headlights, badge, rear door seam and handles.
    bk.patch(surf, shell, m["Trim"], bk.rect(0.70, 0.14, 0.3), (0, 2.6, 0.36), (0, -1, -0.2), up, lift=0.003, kind=bk.GRILLE_SLATS)
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.09, 0.06), (0, 2.6, 0.36), (0, -1, -0.2), up, lift=0.006)
    bk.patch(surf, shell, m["Trim"], bk.rect(0.012, 1.3), (0, -2.7, 0.88), back, up, lift=0.004, grid=(1, 6))
    bk.patch(surf, shell, m["Trim"], bk.rect(0.14, 0.03), (-0.12, -2.7, 0.70), back, up, lift=0.005, grid=2)
    bk.patch(surf, shell, m["TailLight"], bk.rect(0.30, 0.03), (0, -2.7, 1.55), back, up, lift=0.005, grid=(3, 1), kind=bk.BRAKE_ONLY)
    bk.patch(surf, rear, m["Chrome"], bk.rect(0.5, 0.11), (0, -2.7, 0.0), back, up, lift=0.004, grid=2)   # plate holder
    # Side step under the sliding door.
    for sx in (-1, 1):
        bk.box(shell, m["Trim"], (sx * 0.93, 0.15, -0.19), (0.16, 0.9, 0.05))


def _interior(shell, m, ys):
    BODY.inner_cabin(shell, m, ys, 1.6, -2.36, every=3)
    im = m["Interior"]
    bk.box(shell, im, (0, -0.3, -0.12), (1.80, 4.0, 0.02))                   # floor
    bk.box(shell, im, (0, 1.55, 0.55), (1.80, 0.32, 0.28))                   # dash
    for sx in (-1, 1):
        x = sx * 0.45
        bk.box(shell, im, (x, 0.95, 0.12), (0.52, 0.52, 0.16), bevel=0.04, segments=1)
        bk.box(shell, im, (x, 0.64, 0.52), (0.52, 0.14, 0.66), bevel=0.05, rot=(math.radians(-10), 0, 0), segments=1)
    for y in (-0.25, -1.25):                                                  # two rear benches
        bk.box(shell, im, (0, y, 0.10), (1.7, 0.5, 0.16), bevel=0.04, segments=1)
        bk.box(shell, im, (0, y - 0.28, 0.48), (1.7, 0.13, 0.62), bevel=0.05, rot=(math.radians(-8), 0, 0), segments=1)
    c = (-0.45, 1.28, 0.70)
    bk.torus(shell, m["Trim"], c, 0.19, 0.02, 16, 5, tilt=math.radians(-35))
    bk.tube(shell, m["Trim"], (-0.45, 1.31, 0.69), (-0.45, 1.5, 0.58), 0.025, 8)


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
