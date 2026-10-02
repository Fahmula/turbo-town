"""Generates the city bus body (bus_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_bus.py

Design language (ART_BIBLE.md §12): a modern low-floor city bus. Boxy body
with rounded roof corners, a huge near-vertical windscreen with a
destination display above it, a continuous dark window band that dips at
the front, glass doors on the right side, livery paint below, a light grey
roof with an air-con unit, black bumpers and arch trim, "rabbit ear"
mirrors, an engine grille and tall tail lights at the back. Opaque tinted
glass (no interior).

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/bus.tscn (wheels r 0.50 at x +-1.00, axles
+-2.20). Ground is z = -0.50. The scene's "TURBO TOWN" label sits in front of
the destination display (y 4.17, z 2.37). Wheels: wheel_steel.glb.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 2.20
ARCH_R = 0.50 + 0.05
REAR_GLASS_CUT = -4.38     # rear window only on the upper part of the back


def _materials(body, j, y):
    reg = body.region(y)
    if (y > 4.05 or y < -4.25) and j <= 4:
        return "Trim"                                    # black bumpers
    if j in (2, 3) and any(abs(y - ay) < ARCH_R + 0.05 for ay in (AXLE_Y, -AXLE_Y)):
        return "Trim"                                    # arch trim
    if reg == "roof" and j >= 14:
        return "Roof"                                    # light grey roof
    if reg == "rw" and j >= 13:
        return ("Trim" if j == 13 else "Glass") if y > REAR_GLASS_CUT else "Paint"
    return ""


SPEC = bk.BodySpec(
    y_nose=4.31, y_tail=-4.47, nose0=4.12, tail0=-4.30, nose_p=2.5, tail_p=3.0,
    floor=-0.18,
    axles=[(AXLE_Y, ARCH_R), (-AXLE_Y, ARCH_R)],
    width=lambda y: 1.25,
    # Window line: dips at the front (the big windscreen starts low).
    shoulder=bk.curve([(4.31, 0.25), (4.25, 0.45), (4.10, 0.60), (3.8, 0.66), (0.0, 0.68), (-4.47, 0.68)]),
    ws_base=4.30, roof_front=4.10, roof_rear=-4.30, rw_base=-4.46,
    roof_edge=bk.curve([(4.30, 0.30), (4.27, 1.0), (4.22, 1.7), (4.17, 2.15), (4.10, 2.38), (3.9, 2.46),
                        (0.0, 2.50), (-4.2, 2.48), (-4.30, 2.42), (-4.38, 1.55), (-4.46, 0.70)]),
    glass_top=2.38,
    crown=lambda y: 0.04,
    roof_w=lambda y: 1.12,
    windows=[(4.00, 3.05), (2.95, 1.55), (1.45, -0.05), (-0.15, -1.65), (-1.75, -3.25), (-3.35, -4.20)],
    pillar_mat="Trim",
    bumper_split=(4.05, -4.25), bumper_row=5,
    shoulder_inset=0.03, hood_edge_inset=0.06, bulge=0.004,
    station_step=0.30, arch_step=0.12,
    keep=[REAR_GLASS_CUT],
    material_override=_materials,
)
BODY = bk.LoftBody(SPEC)


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.91, 0.71, 0.118), glass_alpha=1.0)
    m["Roof"] = bk.material("Roof", (0.82, 0.82, 0.80), rough=0.5)
    shell, front, rear, ys = BODY.build(m, "BusBody")
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    bk.box(shell, m["Trim"], (0, 4.12, -0.06), (2.0, 0.2, 0.18))          # crash beams
    bk.box(shell, m["Trim"], (0, -4.30, -0.06), (2.0, 0.2, 0.18))
    objs = [p.to_object(math.radians(55)) for p in (shell, front, rear)]
    bk.export(objs, "bus_body.glb")


def _door(surf, shell, m, y0, y1):
    """A two-leaf glass door on the right side, floor to window top."""
    c = (y0 + y1) / 2
    side = (-1, 0, 0)
    up = (0, 0, 1)
    # Dense vertical sampling: the side bulges between belt and sill.
    bk.patch(surf, shell, m["Trim"], bk.rect(y0 - y1 + 0.08, 2.40), (2.0, c, 1.05), side, up, lift=0.005, grid=(2, 18))
    for k in (-1, 1):
        yc = c + k * (y0 - y1) / 4
        bk.patch(surf, shell, m["GlassDark"], bk.rect((y0 - y1) / 2 - 0.06, 2.20), (2.0, yc, 1.08), side, up, lift=0.008, grid=(1, 17))


def _details(surf, shell, front, rear, m):
    fwd = (0, -1, 0)
    back = (0, 1, 0)
    up = (0, 0, 1)
    # Doors (right side only): front door in the overhang, middle door.
    _door(surf, shell, m, 3.88, 3.06)
    _door(surf, shell, m, 0.52, -0.32)
    for sx in (-1, 1):
        # Headlights low on the front corners, turn lamps.
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.36, 0.16, 0.3), (sx * 0.85, 4.6, 0.20), fwd, up, lift=0.004)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.30, 0.11, 0.3), (sx * 0.85, 4.6, 0.20), fwd, up, lift=0.006, kind=bk.LAMP)
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.15, 0.10, 0.3), (sx * 0.555, 4.6, 0.20), fwd, up, lift=0.004, grid=2)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.12, 0.075, 0.3), (sx * 0.555, 4.6, 0.20), fwd, up, lift=0.006, grid=3,
                 kind=bk.INDICATOR)
        # Tall tail lights and reverse lamps on the rear corners.
        bk.patch(surf, shell, m["Trim"], bk.rect(0.18, 0.62), (sx * 1.0, -4.8, 0.62), back, up, lift=0.003, grid=(2, 6))
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.14, 0.20), (sx * 1.0, -4.8, 0.81), back, up, lift=0.005, grid=(2, 3), kind=bk.LAMP)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.14, 0.13), (sx * 1.0, -4.8, 0.615), back, up, lift=0.005, grid=2,
                 kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.14, 0.10), (sx * 1.0, -4.8, 0.45), back, up, lift=0.005, grid=2, kind=bk.LAMP)
        # Rabbit-ear mirrors on arms from the front top corners.
        bk.tube(shell, m["Trim"], (sx * 1.2, 4.05, 2.2), (sx * 1.38, 4.30, 2.05), 0.025, 6)
        bk.box(shell, m["Trim"], (sx * 1.40, 4.33, 1.80), (0.07, 0.16, 0.38), bevel=0.02, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.40, 4.248, 1.80), (0.055, 0.006, 0.33))
    # Destination display above the windscreen (the scene's label sits on it).
    bk.patch(surf, shell, m["GlassDark"], bk.rect(1.9, 0.30), (0, 4.6, 2.36), (0, -1, -0.2), up, lift=0.004, grid=(6, 2))
    # Badge and a grille slot between the headlights.
    bk.patch(surf, shell, m["Trim"], bk.rect(0.9, 0.06), (0, 4.6, 0.18), fwd, up, lift=0.004, grid=(4, 1), kind=bk.GRILLE_SLATS)
    # Back: engine grille with louvres, plate, rear window frame handled by the loft.
    bk.patch(surf, shell, m["Trim"], bk.rect(1.5, 0.75), (0, -4.8, 0.82), back, up, lift=0.003, grid=(6, 3))
    for k in range(6):
        bk.patch(surf, shell, m["Roof"], bk.rect(1.40, 0.03), (0, -4.8, 0.52 + k * 0.12), back, up, lift=0.005, grid=(4, 1))
    bk.patch(surf, rear, m["Chrome"], bk.rect(0.5, 0.11), (0, -4.8, -0.04), back, up, lift=0.004, grid=2)
    # Air-con unit on the roof.
    bk.box(shell, m["Roof"], (0, -1.6, 2.62), (1.5, 1.8, 0.24), bevel=0.06, segments=1)
    bk.box(shell, m["Trim"], (0, -1.6, 2.745), (1.1, 1.2, 0.012))


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
