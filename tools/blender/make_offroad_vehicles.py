"""Generates the pickup, buggy and monster truck bodies plus a knobbly
off-road wheel as .glb files in assets/models/.

Run headless from the project root:
    blender -b -P tools/blender/make_offroad_vehicles.py

Each body's origin is at wheel-centre height, midway between its axles.
Axle positions / wheel radii must match the vehicle scenes in
scenes/vehicles/ (listed in each builder's docstring).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vehicle_kit import *  # noqa: E402,F401,F403


def cut_box(target, center, size):
    cutter = add_box("cut", center, size, target.data.materials[0])
    boolean_cut(target, cutter)


def build_pickup():
    """Wheels: radius 0.40, x +-0.86, axles y +-1.60."""
    reset_scene()
    m = standard_materials((0.85, 0.2, 0.15))
    parts = []
    front = extrude_profile("Front", [
        (-0.64, -0.14), (2.44, -0.14), (2.58, 0.04), (2.58, 0.38), (2.46, 0.54),
        (1.05, 0.62), (-0.64, 0.62),
    ], 1.94)
    front.data.materials.append(m["paint"])
    cut_wheel_arches(front, (1.6,), 0.49)
    bevel(front, 0.06, 3)
    parts.append(front)
    bed = extrude_profile("Bed", [(-2.68, -0.12), (-0.62, -0.12), (-0.62, 0.66), (-2.68, 0.66)], 1.94)
    bed.data.materials.append(m["paint"])
    cut_wheel_arches(bed, (-1.6,), 0.49)
    cut_box(bed, (0, -1.66, 0.48), (1.74, 1.9, 0.6))
    bevel(bed, 0.04, 2)
    parts.append(bed)
    parts.append(add_box("BedFloor", (0, -1.66, 0.17), (1.74, 1.9, 0.04), m["trim"]))
    cab = extrude_profile("Cab", [(1.05, 0.6), (0.42, 1.3), (-0.5, 1.32), (-0.6, 1.26), (-0.6, 0.6)], 1.82,
        taper_top=0.1, top_z=1.3)
    cab.data.materials.append(m["glass"])
    bevel(cab, 0.04, 2)
    parts.append(cab)
    parts.append(add_box("Roof", (0, -0.05, 1.33), (1.58, 0.9, 0.05), m["paint"], bevel=0.02))
    for sx in (-1, 1):
        parts.append(slope_box("APillar", (1.05, 0.6), (0.46, 1.27), 0.08, 0.08, m["paint"], x=sx * 0.86, outward=0.0))
        parts.append(add_box("BPillar", (sx * 0.87, -0.58, 0.95), (0.06, 0.1, 0.7), m["paint"]))
        parts.append(add_box("Headlight", (sx * 0.66, 2.58, 0.36), (0.38, 0.06, 0.16), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.9, -2.69, 0.44), (0.12, 0.05, 0.3), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.9, -2.69, 0.2), (0.12, 0.05, 0.1), m["reverse"]))
        parts.append(add_box("Mirror", (sx * 1.03, 0.9, 0.82), (0.12, 0.12, 0.16), m["trim"], bevel=0.02))
        parts.append(add_box("Step", (sx * 1.0, 0.0, -0.12), (0.14, 1.0, 0.05), m["chrome"]))
    parts.append(add_box("Grille", (0, 2.59, 0.24), (1.0, 0.05, 0.28), m["chrome"]))
    parts.append(add_box("FrontBumper", (0, 2.55, -0.08), (1.96, 0.18, 0.18), m["chrome"], bevel=0.03))
    parts.append(add_box("RearBumper", (0, -2.72, -0.06), (1.96, 0.16, 0.16), m["chrome"], bevel=0.03))
    parts.append(add_box("RearWindow", (0, -0.61, 1.0), (1.4, 0.03, 0.42), m["glass"]))
    truck = join(parts, "PickupBody")
    smooth_by_angle(truck, math.radians(35))
    export([truck], "pickup_body.glb")


def build_buggy():
    """Wheels: radius 0.42, x +-0.92, axles y +-1.25."""
    reset_scene()
    m = standard_materials((1.0, 0.5, 0.1))
    cage = make_material("Cage", srgb((0.12, 0.12, 0.14)), rough=0.5, metal=0.3)
    parts = []
    tub = extrude_profile("Tub", [
        (-1.55, -0.08), (1.45, -0.08), (1.78, 0.18), (1.52, 0.36), (0.55, 0.42),
        (-1.0, 0.46), (-1.62, 0.34),
    ], 1.24)
    tub.data.materials.append(m["paint"])
    cut_box(tub, (0, -0.25, 0.5), (1.0, 1.25, 0.3))
    bevel(tub, 0.05, 2)
    parts.append(tub)
    for sx in (-1, 1):
        # Fenders over the wheels.
        parts.append(add_box("FenderF", (sx * 0.92, 1.25, 0.44), (0.42, 0.95, 0.05), m["paint"], bevel=0.02))
        parts.append(add_box("FenderR", (sx * 0.92, -1.25, 0.46), (0.42, 0.95, 0.05), m["paint"], bevel=0.02))
        # Roll cage: two hoops joined along the top.
        parts.append(add_tube("CageFront", (sx * 0.58, 0.45, 0.4), (sx * 0.5, 0.1, 1.28), 0.04, cage))
        parts.append(add_tube("CageRear", (sx * 0.6, -0.95, 0.44), (sx * 0.52, -0.75, 1.32), 0.04, cage))
        parts.append(add_tube("CageTop", (sx * 0.5, 0.1, 1.28), (sx * 0.52, -0.75, 1.32), 0.04, cage))
        parts.append(add_tube("CageBrace", (sx * 0.6, -0.95, 0.44), (sx * 0.4, -1.55, 0.35), 0.035, cage))
        parts.append(add_tube("Nerf", (sx * 0.64, 0.75, 0.05), (sx * 0.64, -0.8, 0.05), 0.04, cage))
        parts.append(add_box("Seat", (sx * 0.26, -0.45, 0.42), (0.38, 0.4, 0.12), m["trim"], bevel=0.03))
        parts.append(add_box("SeatBack", (sx * 0.26, -0.68, 0.7), (0.38, 0.08, 0.5), m["trim"], bevel=0.03))
        parts.append(add_box("Headlight", (sx * 0.38, 1.6, 0.34), (0.2, 0.08, 0.12), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.5, -1.64, 0.3), (0.16, 0.04, 0.1), m["tail"]))
        parts.append(add_box("ReverseLight", (sx * 0.3, -1.64, 0.3), (0.1, 0.04, 0.08), m["reverse"]))
        parts.append(add_tube("Exhaust", (sx * 0.22, -1.3, 0.55), (sx * 0.26, -1.75, 0.62), 0.05, m["chrome"]))
    parts.append(add_tube("CageTopFront", (-0.5, 0.1, 1.28), (0.5, 0.1, 1.28), 0.04, cage))
    parts.append(add_tube("CageTopRear", (-0.52, -0.75, 1.32), (0.52, -0.75, 1.32), 0.04, cage))
    parts.append(add_box("Engine", (0, -1.2, 0.55), (0.75, 0.6, 0.35), m["trim"], bevel=0.04))
    parts.append(add_box("Wing", (0, -1.55, 1.1), (1.3, 0.35, 0.04), m["paint"], bevel=0.01))
    parts.append(add_tube("WingPostL", (-0.4, -1.45, 0.62), (-0.4, -1.55, 1.08), 0.03, cage))
    parts.append(add_tube("WingPostR", (0.4, -1.45, 0.62), (0.4, -1.55, 1.08), 0.03, cage))
    parts.append(add_box("SteeringWheel", (-0.26, 0.05, 0.78), (0.3, 0.04, 0.3), m["trim"]))
    parts.append(add_box("Bumper", (0, 1.82, 0.1), (1.1, 0.1, 0.12), cage, bevel=0.02))
    buggy = join(parts, "BuggyBody")
    smooth_by_angle(buggy, math.radians(35))
    export([buggy], "buggy_body.glb")


def build_monster():
    """Wheels: radius 0.95, x +-1.32, axles y +-1.65. Body sits high above them."""
    reset_scene()
    m = standard_materials((0.45, 0.25, 0.85))
    flame = make_material("Stripe", srgb((1.0, 0.72, 0.1)), rough=0.35)
    frame = make_material("Frame", srgb((0.12, 0.12, 0.14)), rough=0.5, metal=0.4)
    parts = []
    lift = 0.62
    body = extrude_profile("Body", [
        (-2.25, lift), (2.2, lift), (2.32, lift + 0.18), (2.32, lift + 0.5), (2.2, lift + 0.66),
        (0.9, lift + 0.74), (-0.6, lift + 0.74), (-0.6, lift + 0.78), (-2.25, lift + 0.78),
    ], 2.0)
    body.data.materials.append(m["paint"])
    cut_box(body, (0, -1.45, lift + 0.7), (1.8, 1.5, 0.5))
    bevel(body, 0.07, 3)
    parts.append(body)
    cab = extrude_profile("Cab", [(0.9, lift + 0.72), (0.35, lift + 1.38), (-0.48, lift + 1.4), (-0.58, lift + 1.34),
        (-0.58, lift + 0.72)], 1.86, taper_top=0.1, top_z=lift + 1.38)
    cab.data.materials.append(m["glass"])
    bevel(cab, 0.04, 2)
    parts.append(cab)
    parts.append(add_box("Roof", (0, -0.06, lift + 1.41), (1.62, 0.84, 0.05), m["paint"], bevel=0.02))
    for sx in (-1, 1):
        parts.append(slope_box("APillar", (0.9, lift + 0.72), (0.38, lift + 1.35), 0.08, 0.08, m["paint"], x=sx * 0.88, outward=0.0))
        parts.append(add_box("Flame1", (sx * 1.005, 1.1, lift + 0.42), (0.02, 1.6, 0.14), flame))
        parts.append(add_box("Flame2", (sx * 1.005, 0.6, lift + 0.24), (0.02, 1.2, 0.1), flame))
        parts.append(add_box("Headlight", (sx * 0.68, 2.33, lift + 0.42), (0.36, 0.05, 0.16), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.9, -2.27, lift + 0.5), (0.14, 0.05, 0.3), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.9, -2.27, lift + 0.25), (0.14, 0.05, 0.1), m["reverse"]))
        parts.append(add_tube("Stack", (sx * 0.95, -0.5, lift + 0.7), (sx * 0.95, -0.5, lift + 1.75), 0.07, m["chrome"]))
        # Suspension links from the frame down to the axles.
        for y in (1.65, -1.65):
            parts.append(add_tube("LinkUpper", (sx * 0.4, y - 0.5 * math.copysign(1, y), lift - 0.05), (sx * 0.85, y, 0.25), 0.06, frame))
            parts.append(add_tube("LinkLower", (sx * 0.4, y - 0.7 * math.copysign(1, y), lift - 0.3), (sx * 0.85, y, -0.1), 0.06, frame))
            parts.append(add_tube("Shock", (sx * 0.62, y + 0.25 * math.copysign(1, y), lift), (sx * 0.86, y + 0.1 * math.copysign(1, y), 0.0), 0.08, m["chrome"]))
    for y in (1.65, -1.65):
        parts.append(add_tube("Axle", (-0.95, y, 0.0), (0.95, y, 0.0), 0.11, frame))
        parts.append(add_box("Diff", (0, y, 0.0), (0.4, 0.32, 0.32), frame, bevel=0.04))
    parts.append(add_box("Frame", (0, 0, lift - 0.15), (0.9, 4.2, 0.3), frame))
    parts.append(add_box("Grille", (0, 2.33, lift + 0.3), (1.1, 0.05, 0.32), m["chrome"]))
    parts.append(add_box("Bumper", (0, 2.4, lift + 0.02), (2.1, 0.2, 0.22), m["chrome"], bevel=0.03))
    parts.append(add_box("RearBumper", (0, -2.33, lift + 0.05), (2.1, 0.16, 0.18), m["chrome"], bevel=0.03))
    parts.append(add_box("LightBar", (0, 0.1, lift + 1.5), (1.4, 0.16, 0.12), m["trim"]))
    for k in range(4):
        parts.append(add_box("Spot", (-0.53 + k * 0.35, 0.19, lift + 1.5), (0.22, 0.03, 0.08), m["head"]))
    truck = join(parts, "MonsterBody")
    smooth_by_angle(truck, math.radians(35))
    export([truck], "monster_body.glb")


def build_offroad_wheel():
    """Base size radius 0.37, width 0.30 (scale it in Godot), knobbly tread."""
    reset_scene()
    tire_m = make_material("Tire", srgb((0.09, 0.09, 0.1)), rough=0.95)
    rim_m = make_material("Rim", srgb((0.25, 0.26, 0.28)), rough=0.4, metal=0.6)
    hub_m = make_material("Hub", srgb((0.85, 0.86, 0.88)), rough=0.2, metal=0.9)
    parts = []
    tire = add_cylinder("Tire", (0, 0, 0), 0.34, 0.3, tire_m, verts=28)
    bevel(tire, 0.05, 2, 30)
    parts.append(tire)
    for k in range(18):
        a = k * 2 * math.pi / 18
        off = 0.07 if k % 2 == 0 else -0.07
        parts.append(add_box("Knob", (off, math.cos(a) * 0.345, math.sin(a) * 0.345), (0.13, 0.11, 0.06), tire_m, rot=(a, 0, 0)))
    parts.append(add_cylinder("Rim", (0.06, 0, 0), 0.21, 0.2, rim_m, verts=20))
    parts.append(add_cylinder("Beadlock", (0.162, 0, 0), 0.215, 0.02, hub_m, verts=20))
    parts.append(add_cylinder("Hub", (0.17, 0, 0), 0.08, 0.04, hub_m, verts=12))
    for k in range(10):
        a = k * 2 * math.pi / 10
        parts.append(add_cylinder("Bolt", (0.175, math.cos(a) * 0.19, math.sin(a) * 0.19), 0.012, 0.02, rim_m, verts=6))
    wheel = join(parts, "OffroadWheel")
    smooth_by_angle(wheel, math.radians(40))
    export([wheel], "wheel_offroad.glb")


os.makedirs(os.path.abspath(OUT_DIR), exist_ok=True)
build_pickup()
build_buggy()
build_monster()
build_offroad_wheel()
