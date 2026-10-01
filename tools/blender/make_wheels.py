"""Generates every vehicle wheel as .glb files in assets/models/.

Run headless from the project root:
    blender -b -P tools/blender/make_wheels.py

All wheels share one base size (outer radius 0.37 m); the vehicle scenes
scale them uniformly to their own radius. Axis is X, +X is the outer face.
Materials: Tire, Rim, Hub (fixed looks, ART_BIBLE.md §13).

  wheel.glb          sports car: 19" split five-spoke alloy, low-profile tyre
  wheel_sedan.glb    sedan: 16" six-spoke alloy, taller sidewall
  wheel_steel.glb    van / delivery truck / bus: painted steel, deep dish
  wheel_offroad.glb  pickup / buggy / monster truck: beadlock rim, knobbly tyre
"""
import math
import os
import sys

import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import body_kit as bk  # noqa: E402

R = 0.37


def tyre(part, mat, width, rim_r, tread="grooves", segments=32, bulge=0.004):
    """Lathed tyre: bead -> sidewall -> rounded shoulder -> tread -> back."""
    hw = width / 2
    side = R - rim_r
    half = [(-hw + 0.012, rim_r), (-hw - bulge * 0.5, rim_r + side * 0.3), (-hw - bulge, rim_r + side * 0.6),
            (-hw + 0.004, R - 0.016), (-hw + 0.022, R - 0.004), (-hw + 0.045, R)]
    if tread == "grooves":
        mid = [(-0.05, R), (-0.042, R - 0.006), (-0.034, R), (-0.006, R), (0.0, R - 0.006), (0.006, R),
               (0.034, R), (0.042, R - 0.006), (0.05, R)]
    elif tread == "commercial":
        mid = [(-0.04, R), (-0.034, R - 0.007), (-0.028, R), (0.028, R), (0.034, R - 0.007), (0.04, R)]
    else:
        mid = []
    prof = half + mid + [(-x, r) for (x, r) in reversed(half)]
    bk.lathe(part, mat, prof, segments)


def knobs(part, mat, width, count=20):
    """Two staggered rows of tread blocks plus shoulder lugs."""
    for k in range(count):
        a = 2 * math.pi * k / count
        for row, (x, wx) in enumerate(((-width * 0.22, width * 0.34), (width * 0.22, width * 0.34))):
            aa = a + (math.pi / count if row else 0.0)
            c = mathutils.Vector((x, math.cos(aa) * (R + 0.012), math.sin(aa) * (R + 0.012)))
            bk.box(part, mat, c, (wx, 0.07, 0.03), rot=(aa - math.pi / 2, 0, 0))
        # Shoulder lug wrapping onto the sidewall, alternating sides.
        sx = 1 if k % 2 else -1
        c = mathutils.Vector((sx * width * 0.5, math.cos(a) * (R - 0.012), math.sin(a) * (R - 0.012)))
        bk.box(part, mat, c, (0.03, 0.055, 0.045), rot=(a - math.pi / 2, 0, 0))


def lugs(part, mat, n, r, x, nut=0.009):
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        c = (x, math.cos(a) * r, math.sin(a) * r)
        bk.tube(part, mat, (c[0] - 0.012, c[1], c[2]), (c[0] + 0.005, c[1], c[2]), nut, 6)


def brake_disc(part, mat, r_out):
    bk.lathe(part, mat, [(-0.035, 0.07), (-0.035, r_out), (-0.012, r_out), (-0.012, 0.07)], 28, loop=True)


def build_sports():
    """19-inch five split-spoke alloy with a low-profile tyre (the approved
    sports car wheel)."""
    bk.reset_scene()
    tire_m = bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9)
    rim_m = bk.material("Rim", (0.72, 0.73, 0.75), rough=0.32, metal=1.0)
    hub_m = bk.material("Hub", (0.24, 0.24, 0.26), rough=0.5, metal=0.6)
    part = bk.Part("Wheel", [])
    tyre(part, tire_m, 0.254, 0.243, "grooves")
    bk.lathe(part, rim_m, [(0.112, 0.243), (0.122, 0.248), (0.126, 0.24), (0.118, 0.232), (0.102, 0.226),
                           (0.04, 0.222), (-0.06, 0.222), (-0.104, 0.232), (-0.112, 0.243)], 32)
    brake_disc(part, hub_m, 0.175)
    bk.lathe(part, rim_m, [(0.06, 0.0), (0.06, 0.07), (0.088, 0.078), (0.098, 0.06), (0.104, 0.03), (0.105, 0.0)], 20)
    for k in range(5):
        base = 2 * math.pi * k / 5
        for side in (-1, 1):
            bk.spoke(part, rim_m, (0.097, 0.068, base + side * 0.09, 0.016),
                     (0.116, 0.225, base + side * 0.2, 0.013), 0.024)
    lugs(part, hub_m, 5, 0.042, 0.104)
    bk.export([part.to_object(math.radians(42))], "wheel.glb")


def build_sedan():
    """16-inch six-spoke alloy, rounded spokes, taller sidewall: a sensible
    family-car wheel."""
    bk.reset_scene()
    tire_m = bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9)
    rim_m = bk.material("Rim", (0.70, 0.71, 0.73), rough=0.38, metal=1.0)
    hub_m = bk.material("Hub", (0.30, 0.30, 0.32), rough=0.5, metal=0.6)
    part = bk.Part("Wheel", [])
    rim_r = 0.222
    tyre(part, tire_m, 0.235, rim_r, "grooves", bulge=0.008)
    bk.lathe(part, rim_m, [(0.102, rim_r), (0.11, rim_r + 0.005), (0.114, rim_r - 0.004), (0.104, rim_r - 0.014),
                           (0.085, rim_r - 0.02), (-0.06, rim_r - 0.022), (-0.1, rim_r - 0.012), (-0.104, rim_r)], 28)
    brake_disc(part, hub_m, 0.155)
    bk.lathe(part, rim_m, [(0.05, 0.0), (0.05, 0.065), (0.08, 0.072), (0.09, 0.05), (0.096, 0.0)], 18)
    for k in range(6):
        a = 2 * math.pi * k / 6
        bk.spoke(part, rim_m, (0.088, 0.06, a, 0.026), (0.104, rim_r - 0.012, a, 0.02), 0.022)
    lugs(part, hub_m, 5, 0.038, 0.094)
    bk.export([part.to_object(math.radians(42))], "wheel_sedan.glb")


def build_steel():
    """Painted steel wheel with a deep dish, round vent holes and a hub dome:
    vans, trucks and buses."""
    bk.reset_scene()
    tire_m = bk.material("Tire", (0.11, 0.11, 0.115), rough=0.9)
    rim_m = bk.material("Rim", (0.78, 0.78, 0.76), rough=0.5, metal=0.0)
    hub_m = bk.material("Hub", (0.16, 0.16, 0.17), rough=0.6, metal=0.3)
    part = bk.Part("Wheel", [])
    rim_r = 0.205
    tyre(part, tire_m, 0.26, rim_r, "commercial", bulge=0.01)
    # Rim barrel and the dished face plate in one profile.
    bk.lathe(part, rim_m, [(0.115, rim_r), (0.124, rim_r + 0.004), (0.126, rim_r - 0.006), (0.112, rim_r - 0.014),
                           (0.07, rim_r - 0.03), (0.06, 0.15), (0.062, 0.1), (0.075, 0.075), (0.078, 0.0)], 24)
    bk.lathe(part, rim_m, [(0.07, rim_r - 0.03), (-0.1, rim_r - 0.03), (-0.115, rim_r)], 24)
    # Vent holes: dark discs set into the face.
    for k in range(8):
        a = 2 * math.pi * k / 8
        c = (0.0635, math.cos(a) * 0.128, math.sin(a) * 0.128)
        bk.tube(part, hub_m, (c[0] - 0.002, c[1], c[2]), (c[0] + 0.0015, c[1], c[2]), 0.024, 8)
    bk.lathe(part, hub_m, [(0.078, 0.0), (0.078, 0.045), (0.096, 0.04), (0.104, 0.02), (0.106, 0.0)], 14)
    lugs(part, rim_m, 8, 0.06, 0.084, nut=0.008)
    bk.export([part.to_object(math.radians(42))], "wheel_steel.glb")


def build_offroad():
    """Beadlock off-road wheel: dark rim, bolted ring, chunky knobbly tyre."""
    bk.reset_scene()
    tire_m = bk.material("Tire", (0.095, 0.095, 0.1), rough=0.95)
    rim_m = bk.material("Rim", (0.2, 0.21, 0.22), rough=0.45, metal=0.6)
    hub_m = bk.material("Hub", (0.72, 0.73, 0.75), rough=0.3, metal=1.0)
    part = bk.Part("Wheel", [])
    width, rim_r = 0.30, 0.21
    tyre(part, tire_m, width, rim_r, "plain", segments=28, bulge=0.012)
    knobs(part, tire_m, width, 18)
    bk.lathe(part, rim_m, [(0.128, rim_r), (0.12, rim_r - 0.01), (0.08, rim_r - 0.016), (0.07, 0.14),
                           (0.07, 0.09), (0.085, 0.06), (0.09, 0.0)], 24)
    bk.lathe(part, rim_m, [(0.08, rim_r - 0.016), (-0.12, rim_r - 0.016), (-0.13, rim_r)], 24)
    # Beadlock ring with its bolts.
    bk.lathe(part, hub_m, [(0.13, rim_r - 0.022), (0.142, rim_r - 0.018), (0.142, rim_r + 0.012), (0.13, rim_r + 0.016)], 28, loop=True)
    lugs(part, rim_m, 12, rim_r - 0.003, 0.146, nut=0.007)
    # Six round cut-outs in the face.
    for k in range(6):
        a = 2 * math.pi * k / 6
        c = (0.0705, math.cos(a) * 0.115, math.sin(a) * 0.115)
        bk.tube(part, tire_m, (c[0] - 0.002, c[1], c[2]), (c[0] + 0.0015, c[1], c[2]), 0.03, 8)
    lugs(part, hub_m, 6, 0.045, 0.094, nut=0.01)
    bk.export([part.to_object(math.radians(42))], "wheel_offroad.glb")


if __name__ == "__main__":
    os.makedirs(os.path.abspath(bk.OUT_DIR), exist_ok=True)
    build_sports()
    build_sedan()
    build_steel()
    build_offroad()
