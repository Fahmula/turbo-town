"""Generates the electric SUV body (suv_body.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_suv.py

Design language (ART_BIBLE.md §12): a modern electric family SUV, asked for
by the owner's son. A smooth egg-shaped body with no grille: a rounded nose
with slim swept headlights and a narrow black intake low in the bumper; a
huge windscreen that runs on up into the roof over the front seats; a high,
smooth belt; a gently arched roof that falls to a short tailgate with a lip;
slim tail lights wrapping round the corners; flush door handles; no exhaust.
The rear doors are gull-wing doors that fold in two (WingDoors opens them
when someone on foot comes close), each with a glass panel in the roof.
An invented badge; no real maker's name, badge or logo.

Conventions: front = Blender +Y, origin at wheel-centre height between the
axles, matching scenes/vehicles/suv.tscn (wheels r 0.37 at x +-0.85, axles
+-1.48). Ground is z = -0.37. Its wheel is wheel_aero.glb (make_wheels.py).

The rear doors are four extra meshes cut out of the shell: WingDoorUpperL/R
(the roof half, hinged on the roof's centre line) and WingDoorLowerL/R (the
side half with the window, hinged on the roof edge). They are modelled in
place (closed) with the origin at the vehicle's origin like every other body
mesh; the hinge lines are printed on export and set on the scene's WingDoors
node.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

AXLE_Y = 1.48
ARCH_R = 0.37 + 0.04
# Shut lines of the gull-wing doors: the B pillar and the C pillar. They run
# up the sides and across the roof.
B_LINE = (-0.146, -0.154)
C_LINE = (-1.196, -1.204)
# The doors' roof windows (the side windows' span).
ROOF_GLASS = (-0.22, -1.12)


def _materials(body, j, y):
    """The gull-wing doors' shut lines go over the roof rail too; each door
    has a glass panel in the roof and they meet on a black spine."""
    on_line = bk.within(y, B_LINE) or bk.within(y, C_LINE)
    if on_line and j in (11, 12):
        return "Trim"
    if body.region(y) == "roof":
        if j in (14, 15, 16) and bk.within(y, ROOF_GLASS):
            return "Glass"
        if j == 17 and bk.within(y, (B_LINE[1], C_LINE[0])):
            return "Trim"
    return ""


SPEC = bk.BodySpec(
    y_nose=2.42, y_tail=-2.56, nose0=2.14, tail0=-2.30, nose_p=1.9, tail_p=3.2,
    floor=-0.16,                 # 21 cm ground clearance
    axles=[(AXLE_Y, ARCH_R), (-AXLE_Y, ARCH_R)],
    width=bk.curve([(2.14, 0.90), (1.95, 0.955), (1.48, 0.985), (0.8, 0.99), (-0.6, 0.992),
                    (-1.48, 0.998), (-1.95, 0.985), (-2.30, 0.94)]),
    # A rounded nose rising to a short bonnet, then a high belt that climbs
    # gently to the tailgate's lip.
    shoulder=bk.curve([(2.42, 0.24), (2.38, 0.36), (2.30, 0.44), (2.16, 0.50), (1.9, 0.55), (1.5, 0.59),
                       (1.18, 0.615), (0.3, 0.625), (-0.5, 0.635), (-1.2, 0.66), (-1.8, 0.70), (-2.2, 0.735),
                       (-2.38, 0.76), (-2.48, 0.745), (-2.56, 0.64)]),
    # The windscreen sweeps from the bonnet up over the front seats; the roof
    # arches over the gull-wing doors and falls to a raked rear window.
    ws_base=1.18, roof_front=-0.08, roof_rear=-1.36, rw_base=-2.38,
    roof_edge=bk.curve([(1.18, 0.615), (1.0, 0.74), (0.75, 0.88), (0.45, 1.02), (0.15, 1.13), (-0.15, 1.20),
                        (-0.5, 1.245), (-0.85, 1.255), (-1.15, 1.235), (-1.4, 1.19), (-1.65, 1.12), (-1.9, 1.01),
                        (-2.15, 0.885), (-2.38, 0.76)]),
    glass_top=1.14,
    crown=bk.curve([(2.42, 0.0), (2.22, 0.03), (1.6, 0.05), (1.18, 0.045), (0.6, 0.055), (0.0, 0.065),
                    (-0.8, 0.07), (-1.4, 0.065), (-2.0, 0.045), (-2.38, 0.035), (-2.56, 0.02)]),
    roof_w=bk.curve([(1.18, 0.82), (0.2, 0.76), (-0.6, 0.74), (-1.36, 0.745), (-2.38, 0.80)]),
    windows=[(1.02, -0.08), (-0.22, -1.12), (-1.28, -1.92)],   # front door, gull-wing door, rear quarter
    pillar_mat="Trim",
    door_lines=[(1.024, 1.016), B_LINE, C_LINE],
    top_lines=[(2.224, 2.216), (1.18, 1.155), B_LINE, C_LINE, (-1.336, -1.344)],
    bumper_split=(2.05, -2.22),
    shoulder_inset=0.04, hood_edge_inset=0.10, bulge=0.012,
    rocker_mat="Paint",
    station_step=0.15,
    material_override=_materials,
)
BODY = bk.LoftBody(SPEC)


def build():
    bk.reset_scene()
    m = bk.vehicle_materials((0.90, 0.90, 0.89))
    shell, front, rear, ys = BODY.build(m, "SuvBody")
    surf = bk.Surface([shell, front, rear])
    _details(surf, shell, front, rear, m)
    BODY.inner_cabin(shell, m, ys, 1.15, -2.34)
    doors = _cut_doors(shell)
    bk.box(shell, m["Trim"], (0, 2.16, -0.06), (1.40, 0.2, 0.16))        # crash beams
    bk.box(shell, m["Trim"], (0, -2.28, -0.05), (1.40, 0.2, 0.16))
    _interior(shell, m)
    _mirrors(shell, m)
    objs = [p.to_object(math.radians(60)) for p in [shell, front, rear] + doors]
    bk.export(objs, "suv_body.glb")
    _print_hinges()


def _cut_doors(shell):
    """Cuts each gull-wing door (outer skin, its handle and window, the
    inner door card and headliner behind it) out of the shell, in two
    halves: the roof half (above the roof edge) and the side half."""
    def door(sx, upper):
        def pick(c):
            if c.x * sx <= 0.0 or not (C_LINE[0] < c.y < B_LINE[1]):
                return False
            pts = BODY.section(0, c.y)
            if c.z <= pts[3][1] + 1e-4:          # the sill stays on the body
                return False
            above = c.z > pts[12][1] - 0.004     # pts[12] = the roof edge
            return above == upper
        return pick
    parts = []
    for sx, side in ((-1, "L"), (1, "R")):
        parts.append(bk.split_part(shell, "WingDoorUpper" + side, door(sx, True)))
        parts.append(bk.split_part(shell, "WingDoorLower" + side, door(sx, False)))
    return parts


def _print_hinges():
    """Hinge lines for the scene's WingDoors node, in Godot coordinates
    (x = lateral, y = height): the centre hinge at the top of the roof and
    the fold on the roof edge, both averaged over the door's length."""
    ys = [C_LINE[0] + (B_LINE[1] - C_LINE[0]) * k / 8 for k in range(9)]
    top = max(BODY.section(0, y)[-1][1] for y in ys)
    edge = [BODY.section(0, y)[12] for y in ys]
    ex = sum(p[0] for p in edge) / len(edge)
    ez = sum(p[1] for p in edge) / len(edge)
    print("wing door hinges: centre (0, %.3f), fold (%.3f, %.3f)" % (top, ex, ez))


def _details(surf, shell, front, rear, m):
    up = (0, 0, 1)
    back = (0, 1, -0.1)
    side = lambda sx: (-sx, 0, 0)  # noqa: E731
    for sx in (-1, 1):
        # Slim swept headlights on the nose's corners: a dark housing, a
        # light strip along the top (DRL), a projector lamp and an amber
        # indicator at the outer end.
        corner = (-sx * 0.42, -1, -0.28)
        hx = sx * 0.62
        hz = 0.40
        bk.patch(surf, shell, m["Trim"], bk.rect(0.48, 0.115, 0.6), (hx, 2.6, hz), corner, up, lift=0.003, grid=(8, 3))
        bk.patch(surf, shell, m["Chrome"], bk.rect(0.45, 0.09, 0.6), (hx, 2.6, hz), corner, up, lift=0.005, grid=(8, 3))
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.42, 0.02, 0.4), (hx, 2.6, hz + 0.034), corner, up, lift=0.007,
                 grid=(8, 1), kind=bk.DRL)
        for k, r in ((-1, 0.05), (0, 0.045)):
            bk.patch(surf, shell, m["Headlight"], bk.ellipse(r * 1.7, r), (hx - sx * (0.06 + 0.09 * k), 2.6, hz - 0.012), corner, up,
                     lift=0.007, kind=bk.LAMP)
        bk.patch(surf, shell, m["Headlight"], bk.rect(0.07, 0.04, 0.3), (hx + sx * 0.16, 2.6, hz - 0.005), corner, up,
                 lift=0.007, grid=3, kind=bk.INDICATOR)
        # Slim tail lights wrapping round the corners under the lip, with the
        # reverse lamp at the inner end and an amber indicator.
        rc = (-sx * 0.35, 1, -0.1)
        tx = sx * 0.66
        tz = 0.62
        bk.patch(surf, shell, m["Trim"], bk.rect(0.48, 0.10, 0.5), (tx, -2.7, tz), rc, up, lift=0.003, grid=(6, 3))
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.45, 0.075, 0.5), (tx, -2.7, tz), rc, up, lift=0.005, grid=(6, 3),
                 kind=bk.LAMP)
        bk.patch(surf, shell, m["TailLight"], bk.rect(0.09, 0.03, 0.3), (sx * 0.81, -2.7, tz - 0.015), rc, up, lift=0.007,
                 grid=3, kind=bk.INDICATOR)
        bk.patch(surf, shell, m["ReverseLight"], bk.rect(0.08, 0.03), (sx * 0.49, -2.7, tz - 0.015), rc, up, lift=0.007,
                 grid=3, kind=bk.LAMP)
        # Reflectors low in the rear bumper.
        bk.patch(surf, rear, m["TailLight"], bk.rect(0.12, 0.025), (sx * 0.72, -2.7, -0.02), back, up, lift=0.004, grid=(3, 1))
        # Flush door handles: front door and gull-wing door.
        for y in (0.26, -0.80):
            bk.patch(surf, shell, m["Chrome"], bk.rect(0.17, 0.022), (sx * 1.2, y, 0.47), side(sx), up, lift=0.003, grid=(3, 1))
    # The smooth nose: a narrow black intake low in the bumper (no grille),
    # a small invented badge (a ring round a dot).
    bk.patch(surf, front, m["Trim"], bk.rect(0.92, 0.075, 0.5), (0, 2.6, -0.06), (0, -1, 0), up, lift=0.003,
             kind=bk.GRILLE_MESH)
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.075, 0.075), (0, 2.6, 0.32), (0, -1, -0.2), up, lift=0.005)
    bk.patch(surf, shell, m["Paint"], bk.ellipse(0.05, 0.05), (0, 2.6, 0.32), (0, -1, -0.2), up, lift=0.0065)
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.02, 0.02), (0, 2.6, 0.32), (0, -1, -0.2), up, lift=0.008)
    # Tailgate: badge, a plate recess, a third brake light at the top of the
    # rear window, a black diffuser.
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.06, 0.06), (0, -2.7, 0.62), back, up, lift=0.005)
    bk.patch(surf, shell, m["Paint"], bk.ellipse(0.04, 0.04), (0, -2.7, 0.62), back, up, lift=0.0065)
    bk.patch(surf, shell, m["Chrome"], bk.ellipse(0.016, 0.016), (0, -2.7, 0.62), back, up, lift=0.008)
    bk.patch(surf, shell, m["Trim"], bk.rect(0.52, 0.13), (0, -2.7, 0.36), back, up, lift=0.003)
    bk.patch(surf, shell, m["TailLight"], bk.rect(0.36, 0.02), (0, -1.40, 1.30), (0, 0.3, -1), (0, 1, 0), lift=0.005,
             grid=(4, 1), kind=bk.BRAKE_ONLY)
    bk.patch(surf, rear, m["Trim"], bk.rect(1.20, 0.10, 0.3), (0, -2.7, -0.10), (0, 1, 0), up, lift=0.003,
             kind=bk.GRILLE_SLATS)


def _interior(shell, m):
    """A dark cabin round the seated driver (the scene's seat numbers,
    ART_BIBLE.md §34): a high floor over the battery, a slim dash with a big
    landscape screen in the middle, two rows of seats, a long console."""
    im = m["Interior"]
    bk.box(shell, im, (0, -0.55, -0.05), (1.74, 2.9, 0.02))                  # floor
    bk.box(shell, im, (0, -1.95, 0.12), (1.66, 0.62, 0.02))                  # boot floor
    bk.box(shell, im, (0, 0.70, 0.47), (1.74, 0.36, 0.20))                   # dash
    bk.box(shell, im, (0, 0.12, 0.08), (0.24, 0.80, 0.24))                   # console
    # The big screen, standing on the dash (dark glass).
    bk.box(shell, im, (0, 0.50, 0.66), (0.38, 0.04, 0.24), rot=(math.radians(-18), 0, 0))
    bk.box(shell, m["GlassDark"], (0, 0.477, 0.664), (0.35, 0.006, 0.21), rot=(math.radians(-18), 0, 0))
    for sx in (-1, 1):
        x = sx * 0.40
        bk.box(shell, im, (x, 0.08, 0.085), (0.52, 0.52, 0.15), bevel=0.04, segments=1)                     # cushion
        bk.box(shell, im, (x, -0.23, 0.48), (0.52, 0.13, 0.66), bevel=0.05, rot=(math.radians(-12), 0, 0), segments=1)
        bk.box(shell, im, (x, -0.31, 0.87), (0.26, 0.10, 0.15), rot=(math.radians(-12), 0, 0))           # headrest
        # Second row: two seats under the gull-wing doors.
        bk.box(shell, im, (x, -0.92, 0.10), (0.56, 0.50, 0.15), bevel=0.04, segments=1)
        bk.box(shell, im, (x, -1.21, 0.48), (0.56, 0.13, 0.62), bevel=0.05, rot=(math.radians(-14), 0, 0), segments=1)
        bk.box(shell, im, (x, -1.29, 0.85), (0.26, 0.10, 0.14), rot=(math.radians(-14), 0, 0))
    # Steering wheel where the seated driver's hands reach (the scene's
    # steering_wheel).
    c = (-0.40, 0.31, 0.57)
    bk.torus(shell, m["Trim"], c, 0.18, 0.018, 16, 5, tilt=math.radians(-25))
    bk.box(shell, m["Trim"], (c[0], c[1] - 0.005, c[2]), (0.1, 0.03, 0.08))
    bk.tube(shell, m["Trim"], (-0.40, 0.34, 0.56), (-0.40, 0.66, 0.46), 0.025, 8)


def _mirrors(shell, m):
    """Body-coloured mirror caps on black arms at the front of the doors."""
    for sx in (-1, 1):
        bk.box(shell, m["Paint"], (sx * 1.06, 0.70, 0.71), (0.17, 0.11, 0.115), bevel=0.035, segments=1)
        bk.box(shell, m["Chrome"], (sx * 1.06, 0.643, 0.71), (0.14, 0.006, 0.09))
        bk.box(shell, m["Trim"], (sx * 0.97, 0.72, 0.65), (0.08, 0.06, 0.05))


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build()
