"""Generates the sports car body (car_body.glb). Its wheel is built by
make_wheels.py (wheel.glb).

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

SPEC = bk.BodySpec(
    y_nose=2.20, y_tail=-2.20, nose0=2.02, tail0=-2.06,
    floor=-0.24,                 # 13 cm ground clearance
    axles=[(AXLE_Y, ARCH_R), (-AXLE_Y, ARCH_R)],
    # Plan view: half width at door-middle height (wide haunches at the back).
    width=bk.curve([(2.02, 0.865), (1.80, 0.925), (1.35, 0.955), (0.95, 0.94), (0.30, 0.932),
                    (-0.55, 0.94), (-1.35, 0.968), (-1.80, 0.935), (-2.06, 0.885)]),
    # Side view: the shoulder / belt line, peaking over both axles.
    shoulder=bk.curve([(2.20, 0.13), (2.10, 0.21), (1.95, 0.31), (1.70, 0.42), (1.38, 0.49),
                       (1.05, 0.475), (0.62, 0.465), (0.0, 0.475), (-0.70, 0.50), (-1.10, 0.53),
                       (-1.38, 0.555), (-1.75, 0.545), (-2.02, 0.515), (-2.20, 0.43)]),
    # The cabin's roof edge from the windscreen base to the deck (fastback).
    ws_base=0.62, roof_front=-0.02, roof_rear=-0.72, rw_base=-1.58,
    roof_edge=bk.curve([(0.62, 0.465), (0.40, 0.60), (0.19, 0.73), (-0.02, 0.85), (-0.20, 0.868),
                        (-0.37, 0.872), (-0.55, 0.866), (-0.72, 0.85), (-0.95, 0.785), (-1.25, 0.68),
                        (-1.58, 0.553)]),
    glass_top=0.85,
    # Negative = the bonnet dips between the fender peaks.
    crown=bk.curve([(2.2, 0.0), (2.0, -0.005), (1.6, -0.03), (1.0, -0.028), (0.66, -0.02), (0.55, 0.02),
                    (0.3, 0.025), (-0.02, 0.03), (-0.7, 0.03), (-1.4, 0.02), (-1.62, -0.01), (-2.2, -0.01)]),
    roof_w=bk.curve([(0.62, 0.66), (-0.02, 0.62), (-0.7, 0.60), (-1.58, 0.64)]),
    windows=[(0.56, -0.655), (-0.715, -1.22)],       # door glass, rear quarter (black B-pillar)
    door_lines=[(0.884, 0.876), (-0.647, -0.655)],
    top_lines=[(2.004, 1.996), (0.62, 0.585), (-1.58, -1.60), (-2.056, -2.064)],  # bonnet, cowl, boot lid
    bumper_split=(1.80, -1.80),
)
BODY = bk.LoftBody(SPEC)


def build_body():
    bk.reset_scene()
    m = bk.vehicle_materials()
    shell, front, rear, ys = BODY.build(m, "CarBody")
    surf = bk.Surface([shell, front, rear])
    _lights_and_details(surf, shell, front, rear, m)

    # Crash beams behind the bumpers (seen once a bumper falls off).
    bk.box(shell, m["Trim"], (0, 1.93, -0.11), (1.30, 0.22, 0.17))
    bk.box(shell, m["Trim"], (0, -1.95, -0.10), (1.30, 0.20, 0.17))

    _interior(shell, m, ys)
    _mirrors(shell, m)
    wing = _wing(m)
    stripes = _stripes(surf)

    objs = [shell.to_object(math.radians(60)), front.to_object(math.radians(60)),
            rear.to_object(math.radians(60)), wing.to_object(math.radians(60)),
            stripes.to_object(math.radians(60))]
    bk.export(objs, "car_body.glb")


def _stripes(surf):
    """Optional twin racing stripes over the bonnet, roof and boot lid (a
    separate "Stripes" mesh: the game hides it unless the player turns
    stripes on in the garage; VehicleBodyVisual picks a contrasting colour)."""
    part = bk.Part("Stripes", [])
    mat = bk.material("Stripe", (0.93, 0.93, 0.91), rough=0.3)
    down, along = (0, 0, -1), (0, 1, 0)
    for sx in (-1, 1):
        for (y0, y1, n) in ((2.12, 0.66, 20), (-0.06, -0.68, 6), (-1.63, -2.11, 6)):
            bk.patch(surf, part, mat, bk.rect(0.16, y0 - y1), (sx * 0.11, (y0 + y1) / 2, 2.0),
                     down, along, lift=0.005, grid=(1, n))
    return part


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
    BODY.inner_cabin(shell, m, ys, 0.58, -1.56)
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
    c = (-0.40, 0.22, 0.34)
    bk.torus(shell, m["Trim"], c, 0.17, 0.018, 16, 5, tilt=math.radians(-25))
    bk.box(shell, m["Trim"], (c[0], c[1] - 0.005, c[2] - 0.002), (0.10, 0.03, 0.08))
    bk.tube(shell, m["Trim"], (-0.40, 0.25, 0.33), (-0.40, 0.45, 0.26), 0.025, 8)


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


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build_body()
