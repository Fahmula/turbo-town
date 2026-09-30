"""Generates the stylized sports car body and wheel as .glb files.

Run headless from the project root:
    blender -b -P tools/blender/make_car.py

Conventions (Blender is Z-up; glTF export converts to Godot's Y-up):
  * Car front points to Blender +Y  -> Godot -Z (forward).
  * Origin is at wheel-centre height, centred between the axles, matching
    scenes/vehicles/sports_car.tscn (wheels at x=+-0.83, y=+-1.35, radius 0.37).
Material names matter: Godot looks up "Paint" (recolourable) and
"TailLight" (brake lights) by name.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vehicle_kit import *  # noqa: E402,F401,F403

WHEEL_R = 0.37
WHEEL_X = 0.83
AXLE_Y = 1.35


def build_car():
    reset_scene()
    paint = make_material("Paint", srgb((0.93, 0.22, 0.14)), rough=0.3, metal=0.15)
    stripe = make_material("Stripe", srgb((0.97, 0.97, 0.95)), rough=0.35)
    glass = make_material("Glass", srgb((0.12, 0.17, 0.26)), rough=0.08, metal=0.5)
    trim = make_material("Trim", srgb((0.13, 0.13, 0.15)), rough=0.6)
    chrome = make_material("Chrome", srgb((0.85, 0.86, 0.88)), rough=0.15, metal=0.9)
    head = make_material("Headlight", srgb((1.0, 0.97, 0.85)), rough=0.1, emission=(1.0, 0.95, 0.8), strength=2.0)
    tail = make_material("TailLight", srgb((0.9, 0.08, 0.06)), rough=0.2, emission=(1.0, 0.05, 0.02), strength=1.0)
    reverse = make_material("ReverseLight", srgb((0.95, 0.95, 0.95)), rough=0.2)

    parts = []

    # Lower body: side profile (y forward, z up), extruded across x.
    body_profile = [
        (-2.12, -0.14), (2.02, -0.14), (2.20, 0.02), (2.20, 0.24), (2.08, 0.40),
        (0.80, 0.52), (-1.70, 0.55), (-2.12, 0.50), (-2.20, 0.30), (-2.18, 0.02),
    ]
    body = extrude_profile("Body", body_profile, 1.94)
    body.data.materials.append(paint)
    # Wheel arches.
    for y in (AXLE_Y, -AXLE_Y):
        cut = add_cylinder("arch", (0, y, 0.0), WHEEL_R + 0.08, 2.4, trim, verts=32)
        boolean_cut(body, cut)
    m = body.modifiers.new("bevel", "BEVEL")
    m.width = 0.06
    m.segments = 3
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    apply_modifiers(body)
    parts.append(body)

    # Greenhouse (cabin) as glass, tapered, with a painted roof slab.
    cabin_profile = [(0.80, 0.50), (0.05, 0.98), (-1.05, 0.99), (-1.72, 0.54)]
    cabin = extrude_profile("Cabin", cabin_profile, 1.62, taper_top=0.14, top_z=0.98)
    cabin.data.materials.append(glass)
    m = cabin.modifiers.new("bevel", "BEVEL")
    m.width = 0.04
    m.segments = 2
    m.limit_method = "ANGLE"
    apply_modifiers(cabin)
    parts.append(cabin)
    roof = add_box("Roof", (0, -0.5, 1.0), (1.36, 1.12, 0.05), paint, bevel=0.02)
    parts.append(roof)
    # Pillars (A and C) in body colour so the glass reads as windows.
    for sx in (-1, 1):
        a = add_box("APillar", (sx * 0.745, 0.425, 0.74), (0.08, 0.08, 0.9), paint, rot=(math.radians(57.4), 0, 0))
        c = add_box("CPillar", (sx * 0.745, -1.385, 0.765), (0.08, 0.14, 0.82), paint, rot=(math.radians(-56.0), 0, 0))
        b = add_box("BPillar", (sx * 0.75, -0.42, 0.76), (0.06, 0.12, 0.46), paint)
        parts += [a, c, b]

    # Racing stripes over hood, roof and trunk.
    for sx in (-0.2, 0.2):
        hood = add_box("HoodStripe", (sx, 1.44, 0.47), (0.2, 1.32, 0.02), stripe, rot=(math.radians(-5.4), 0, 0))
        roof_s = add_box("RoofStripe", (sx, -0.5, 1.03), (0.2, 1.1, 0.02), stripe)
        trunk = add_box("TrunkStripe", (sx, -1.9, 0.56), (0.2, 0.42, 0.02), stripe)
        parts += [hood, roof_s, trunk]

    # Lights, grille, bumpers.
    for sx in (-1, 1):
        parts.append(add_box("Headlight", (sx * 0.64, 2.18, 0.22), (0.38, 0.06, 0.14), head, bevel=0.02))
        parts.append(add_box("TailLight", (sx * 0.62, -2.19, 0.33), (0.46, 0.05, 0.12), tail, bevel=0.015))
        parts.append(add_box("ReverseLight", (sx * 0.28, -2.19, 0.33), (0.12, 0.05, 0.1), reverse))
        parts.append(add_box("Mirror", (sx * 1.0, 0.62, 0.62), (0.14, 0.1, 0.09), paint, bevel=0.02))
        parts.append(add_cylinder("Exhaust", (sx * 0.5, -2.2, -0.08), 0.055, 0.2, chrome, verts=12, axis="Y"))
    parts.append(add_box("Grille", (0, 2.19, 0.12), (0.72, 0.05, 0.14), trim))
    parts.append(add_box("FrontBumper", (0, 2.12, -0.08), (1.9, 0.18, 0.14), trim, bevel=0.03))
    parts.append(add_box("RearBumper", (0, -2.12, -0.06), (1.9, 0.18, 0.14), trim, bevel=0.03))
    parts.append(add_box("SideSkirts", (0, 0.0, -0.13), (1.98, 1.5, 0.1), trim))

    # Rear spoiler.
    parts.append(add_box("Wing", (0, -1.98, 0.8), (1.7, 0.3, 0.04), paint, rot=(math.radians(-6), 0, 0), bevel=0.01))
    for sx in (-0.6, 0.6):
        parts.append(add_box("WingPost", (sx, -1.96, 0.66), (0.06, 0.12, 0.24), trim))

    car = join(parts, "CarBody")
    smooth_by_angle(car, math.radians(35))
    export([car], "car_body.glb")


def build_wheel():
    reset_scene()
    tire_m = make_material("Tire", srgb((0.1, 0.1, 0.11)), rough=0.9)
    rim_m = make_material("Rim", srgb((0.86, 0.86, 0.88)), rough=0.25, metal=0.8)
    hub_m = make_material("Hub", srgb((0.25, 0.25, 0.28)), rough=0.4, metal=0.5)
    parts = []
    tire = add_cylinder("Tire", (0, 0, 0), WHEEL_R, 0.28, tire_m, verts=28)
    m = tire.modifiers.new("bevel", "BEVEL")
    m.width = 0.06
    m.segments = 3
    m.limit_method = "ANGLE"
    apply_modifiers(tire)
    parts.append(tire)
    # Rim disc sits slightly proud on the +X (outer) face.
    parts.append(add_cylinder("RimDisc", (0.1, 0, 0), 0.25, 0.1, hub_m, verts=24))
    # Rim lip as a ring of small segments.
    for k in range(16):
        a = k * 2 * math.pi / 16
        parts.append(add_box("Lip", (0.15, math.cos(a) * 0.235, math.sin(a) * 0.235), (0.03, 0.1, 0.035), rim_m, rot=(a, 0, 0)))
    for k in range(5):
        a = k * 2 * math.pi / 5
        spoke = add_box("Spoke", (0.16, math.cos(a) * 0.12, math.sin(a) * 0.12), (0.035, 0.07, 0.22), rim_m, rot=(a + math.pi / 2, 0, 0))
        parts.append(spoke)
    parts.append(add_cylinder("HubCap", (0.17, 0, 0), 0.065, 0.04, rim_m, verts=12))
    wheel = join(parts, "Wheel")
    smooth_by_angle(wheel, math.radians(40))
    export([wheel], "wheel.glb")


os.makedirs(os.path.abspath(OUT_DIR), exist_ok=True)
build_car()
build_wheel()
