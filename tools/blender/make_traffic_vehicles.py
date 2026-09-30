"""Generates the traffic vehicle bodies (sedan, van, box truck, bus) and a
steel wheel as .glb files in assets/models/.

Run headless from the project root:
    blender -b -P tools/blender/make_traffic_vehicles.py

Each body's origin is at wheel-centre height, midway between its axles.
Axle positions / wheel radii must match the vehicle scenes in
scenes/vehicles/ (listed in each builder's docstring).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vehicle_kit import *  # noqa: E402,F401,F403


def build_sedan():
    """Wheels: radius 0.34, x +-0.80, axles y +-1.40."""
    reset_scene()
    m = standard_materials((0.25, 0.5, 0.9))
    parts = []
    body = extrude_profile("Body", [
        (-2.28, -0.12), (2.12, -0.12), (2.30, 0.02), (2.30, 0.22), (2.18, 0.36),
        (0.95, 0.47), (-1.62, 0.50), (-2.22, 0.49), (-2.32, 0.30), (-2.30, 0.02),
    ], 1.86)
    body.data.materials.append(m["paint"])
    cut_wheel_arches(body, (1.4, -1.4), 0.41)
    bevel(body, 0.06, 3)
    parts.append(body)

    cabin = extrude_profile("Cabin", [(0.95, 0.45), (0.22, 0.97), (-0.92, 0.98), (-1.64, 0.48)], 1.56, taper_top=0.12, top_z=0.97)
    cabin.data.materials.append(m["glass"])
    bevel(cabin, 0.04, 2)
    parts.append(cabin)
    parts.append(add_box("Roof", (0, -0.35, 0.995), (1.30, 1.16, 0.05), m["paint"], bevel=0.02))
    for sx in (-1, 1):
        parts.append(slope_box("APillar", (0.95, 0.45), (0.27, 0.93), 0.08, 0.08, m["paint"], x=sx * 0.725, outward=0.0))
        parts.append(slope_box("CPillar", (-0.98, 0.93), (-1.64, 0.48), 0.08, 0.12, m["paint"], x=sx * 0.725, outward=0.0))
        parts.append(add_box("BPillar", (sx * 0.735, -0.35, 0.72), (0.06, 0.12, 0.48), m["paint"]))
        parts.append(add_box("SideStrip", (sx * 0.94, 0.0, 0.2), (0.02, 1.9, 0.05), m["chrome"]))
        parts.append(add_box("Headlight", (sx * 0.6, 2.28, 0.24), (0.42, 0.06, 0.13), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.62, -2.31, 0.33), (0.44, 0.05, 0.14), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.26, -2.31, 0.33), (0.14, 0.05, 0.1), m["reverse"]))
        parts.append(add_box("Mirror", (sx * 0.97, 0.75, 0.6), (0.14, 0.1, 0.09), m["paint"], bevel=0.02))
    parts.append(add_box("Grille", (0, 2.29, 0.12), (0.8, 0.05, 0.16), m["chrome"]))
    parts.append(add_box("FrontBumper", (0, 2.22, -0.06), (1.84, 0.18, 0.14), m["trim"], bevel=0.03))
    parts.append(add_box("RearBumper", (0, -2.24, -0.05), (1.84, 0.18, 0.14), m["trim"], bevel=0.03))
    car = join(parts, "SedanBody")
    smooth_by_angle(car, math.radians(35))
    export([car], "sedan_body.glb")


def build_van():
    """Wheels: radius 0.36, x +-0.86, axles y +-1.50."""
    reset_scene()
    m = standard_materials((0.95, 0.95, 0.93))
    parts = []
    body = extrude_profile("Body", [
        (-2.50, -0.16), (2.30, -0.16), (2.44, 0.02), (2.44, 0.32), (2.32, 0.55),
        (1.80, 0.68), (1.02, 1.56), (0.80, 1.62), (-2.44, 1.64), (-2.52, 1.54), (-2.52, 0.02),
    ], 1.96)
    body.data.materials.append(m["paint"])
    cut_wheel_arches(body, (1.5, -1.5), 0.44)
    bevel(body, 0.08, 3)
    parts.append(body)

    parts.append(slope_box("Windshield", (1.80, 0.68), (1.02, 1.56), 1.72, 0.03, m["glass"]))
    for sx in (-1, 1):
        parts.append(add_box("SideWindows", (sx * 0.985, -0.7, 1.22), (0.03, 3.1, 0.46), m["glass"]))
        parts.append(add_box("DoorWindow", (sx * 0.985, 1.12, 1.18), (0.03, 0.48, 0.4), m["glass"]))
        for y in (0.83, -0.4, -1.6):
            parts.append(add_box("Pillar", (sx * 0.995, y, 1.22), (0.03, 0.12, 0.5), m["paint"]))
        parts.append(add_box("Stripe", (sx * 0.99, -0.05, 0.55), (0.03, 4.8, 0.13), m["stripe"]))
        parts.append(add_box("Headlight", (sx * 0.66, 2.44, 0.4), (0.36, 0.06, 0.16), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.84, -2.54, 0.8), (0.18, 0.05, 0.46), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.84, -2.54, 0.44), (0.18, 0.05, 0.12), m["reverse"]))
        parts.append(add_box("Mirror", (sx * 1.07, 1.55, 1.08), (0.1, 0.12, 0.22), m["trim"], bevel=0.02))
    parts.append(add_box("RearWindow", (0, -2.535, 1.22), (1.5, 0.03, 0.46), m["glass"]))
    parts.append(add_box("Grille", (0, 2.45, 0.24), (0.9, 0.05, 0.22), m["trim"]))
    parts.append(add_box("FrontBumper", (0, 2.4, -0.06), (1.96, 0.2, 0.2), m["trim"], bevel=0.03))
    parts.append(add_box("RearBumper", (0, -2.5, -0.06), (1.96, 0.2, 0.2), m["trim"], bevel=0.03))
    parts.append(add_box("DoorLine", (0.992, 0.2, 0.7), (0.02, 0.02, 1.3), m["trim"]))
    van = join(parts, "VanBody")
    smooth_by_angle(van, math.radians(35))
    export([van], "van_body.glb")


def build_truck():
    """Wheels: radius 0.45, x +-0.95, axles y +-1.90 (cab over the front axle)."""
    reset_scene()
    m = standard_materials((0.2, 0.55, 0.9))
    box_mat = make_material("Box", srgb((0.96, 0.96, 0.94)), rough=0.6)
    parts = []
    cab = extrude_profile("Cab", [
        (1.05, -0.2), (2.95, -0.2), (3.05, 0.1), (3.05, 0.95), (2.78, 1.12),
        (2.48, 1.98), (2.30, 2.02), (1.05, 2.02),
    ], 2.1)
    cab.data.materials.append(m["paint"])
    cut_wheel_arches(cab, (1.9,), 0.53)
    bevel(cab, 0.07, 3)
    parts.append(cab)
    parts.append(slope_box("Windshield", (2.78, 1.12), (2.48, 1.98), 1.9, 0.03, m["glass"]))
    for sx in (-1, 1):
        parts.append(add_box("CabWindow", (sx * 1.055, 1.95, 1.52), (0.03, 0.8, 0.55), m["glass"]))
        parts.append(add_box("Headlight", (sx * 0.75, 3.06, 0.45), (0.36, 0.05, 0.18), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.95, -3.82, 0.3), (0.26, 0.05, 0.16), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.6, -3.82, 0.3), (0.14, 0.05, 0.12), m["reverse"]))
        parts.append(add_box("MirrorArm", (sx * 1.18, 2.62, 1.45), (0.08, 0.08, 0.5), m["trim"]))
        parts.append(add_box("Mirror", (sx * 1.25, 2.62, 1.55), (0.06, 0.16, 0.3), m["trim"]))
        parts.append(add_box("MudFlap", (sx * 0.95, -2.55, -0.05), (0.4, 0.03, 0.42), m["trim"]))
        parts.append(add_box("Step", (sx * 1.0, 1.3, -0.12), (0.2, 0.4, 0.06), m["chrome"]))
    parts.append(add_box("Grille", (0, 3.06, 0.62), (0.9, 0.05, 0.4), m["trim"]))
    parts.append(add_box("FrontBumper", (0, 3.02, -0.06), (2.1, 0.2, 0.25), m["trim"], bevel=0.03))
    parts.append(add_box("Chassis", (0, -0.5, -0.02), (1.1, 6.4, 0.25), m["trim"]))
    parts.append(add_box("RearBumper", (0, -3.75, 0.18), (2.2, 0.15, 0.15), m["trim"]))
    parts.append(add_box("CargoBox", (0, -1.425, 1.7), (2.3, 4.75, 2.3), box_mat, bevel=0.04))
    parts.append(add_box("DoorSeam", (0, -3.81, 1.7), (0.03, 0.02, 2.2), m["trim"]))
    for sx in (-0.35, 0.35):
        parts.append(add_box("Handle", (sx, -3.815, 1.45), (0.05, 0.03, 0.5), m["chrome"]))
    truck = join(parts, "TruckBody")
    smooth_by_angle(truck, math.radians(35))
    export([truck], "truck_body.glb")


def build_bus():
    """Wheels: radius 0.50, x +-1.00, axles y +-2.20."""
    reset_scene()
    m = standard_materials((1.0, 0.78, 0.1))
    parts = []
    body = extrude_profile("Body", [
        (-4.45, -0.2), (4.10, -0.2), (4.25, -0.05), (4.30, 0.95), (4.22, 2.2),
        (4.05, 2.55), (-4.30, 2.58), (-4.45, 2.40), (-4.47, 0.0),
    ], 2.5)
    body.data.materials.append(m["paint"])
    cut_wheel_arches(body, (2.2, -2.2), 0.58)
    bevel(body, 0.12, 3)
    parts.append(body)
    parts.append(slope_box("Windshield", (4.30, 0.98), (4.22, 2.18), 2.2, 0.03, m["glass"]))
    parts.append(slope_box("DestSign", (4.2, 2.24), (4.07, 2.5), 1.7, 0.03, m["trim"]))
    parts.append(add_box("RearWindow", (0, -4.49, 1.8), (2.0, 0.03, 0.8), m["glass"]))
    for sx in (-1, 1):
        parts.append(add_box("Windows", (sx * 1.255, -0.3, 1.72), (0.03, 7.2, 0.95), m["glass"]))
        for k in range(7):
            y = -3.9 + k * 1.2
            if sx > 0 and y > 3.0:
                continue  # front door on the right side
            parts.append(add_box("Pillar", (sx * 1.265, y, 1.72), (0.03, 0.13, 0.97), m["paint"]))
        parts.append(add_box("Stripe", (sx * 1.26, -0.1, 1.05), (0.03, 8.3, 0.14), m["trim"]))
        parts.append(add_box("Headlight", (sx * 0.9, 4.32, 0.45), (0.42, 0.05, 0.2), m["head"], bevel=0.02))
        parts.append(add_box("TailLight", (sx * 1.0, -4.5, 0.6), (0.3, 0.05, 0.36), m["tail"], bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.6, -4.5, 0.42), (0.18, 0.05, 0.12), m["reverse"]))
        parts.append(add_box("MirrorArm", (sx * 1.35, 4.05, 1.9), (0.08, 0.08, 0.45), m["trim"]))
        parts.append(add_box("Mirror", (sx * 1.42, 4.1, 1.8), (0.06, 0.16, 0.32), m["trim"]))
    parts.append(add_box("Door", (1.262, 3.45, 1.0), (0.03, 0.95, 2.1), m["glass"]))
    parts.append(add_box("DoorSeam", (1.275, 3.45, 1.0), (0.02, 0.03, 2.1), m["trim"]))
    parts.append(add_box("FrontBumper", (0, 4.26, -0.1), (2.5, 0.2, 0.3), m["trim"], bevel=0.04))
    parts.append(add_box("RearBumper", (0, -4.46, -0.1), (2.5, 0.2, 0.3), m["trim"], bevel=0.04))
    parts.append(add_box("RoofUnit", (0, -1.5, 2.7), (1.4, 1.6, 0.25), m["trim"], bevel=0.04))
    bus = join(parts, "BusBody")
    smooth_by_angle(bus, math.radians(35))
    export([bus], "bus_body.glb")


def build_steel_wheel():
    """Same base size as wheel.glb (radius 0.37, width 0.28); scale it in Godot."""
    reset_scene()
    tire_m = make_material("Tire", srgb((0.1, 0.1, 0.11)), rough=0.9)
    rim_m = make_material("Rim", srgb((0.92, 0.92, 0.9)), rough=0.45, metal=0.2)
    hub_m = make_material("Hub", srgb((0.35, 0.36, 0.4)), rough=0.4, metal=0.5)
    parts = []
    tire = add_cylinder("Tire", (0, 0, 0), 0.37, 0.28, tire_m, verts=28)
    bevel(tire, 0.06, 3, 30)
    parts.append(tire)
    parts.append(add_cylinder("RimDisc", (0.1, 0, 0), 0.24, 0.1, rim_m, verts=24))
    parts.append(add_cylinder("HubDome", (0.155, 0, 0), 0.11, 0.05, hub_m, verts=16))
    for k in range(8):
        a = k * 2 * math.pi / 8
        parts.append(add_cylinder("Lug", (0.17, math.cos(a) * 0.075, math.sin(a) * 0.075), 0.015, 0.03, hub_m, verts=6))
    for k in range(6):
        a = k * 2 * math.pi / 6
        parts.append(add_box("Vent", (0.155, math.cos(a) * 0.17, math.sin(a) * 0.17), (0.03, 0.06, 0.05), hub_m, rot=(a, 0, 0)))
    wheel = join(parts, "SteelWheel")
    smooth_by_angle(wheel, math.radians(40))
    export([wheel], "wheel_steel.glb")


os.makedirs(os.path.abspath(OUT_DIR), exist_ok=True)
build_sedan()
build_van()
build_truck()
build_bus()
build_steel_wheel()
