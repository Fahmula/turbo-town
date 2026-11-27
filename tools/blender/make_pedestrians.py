"""Generates the town's pedestrians (assets/models/character/pedestrians.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_pedestrians.py
    blender -b -P tools/blender/make_pedestrians.py -- --out /tmp/peds.glb --only dress_f --preview /tmp/shots

Same source and pipeline as the player (make_character.py, whose helpers this
imports): the Quaternius Universal Animation Library (CC0) rig and clips, a
signed-distance sculpt of a body, garments and hair, meshed, decimated, cut
along every region border and skinned. Where the player is one casually
dressed man, this builds several different people (LOOKS below): men and women,
slim and heavier builds, short, long, tied-up and covered hair, T-shirts, long
sleeves, a jacket, a tank top, a dress, a skirt, shorts and trousers
(ART_BIBLE.md §34, "Pedestrians").

Differences from the player, all for a crowd on the Steam Deck:
  * Fewer triangles (TARGET_TRIS below, ~8k each with the region cuts).
  * One surface per person: every region (skin, hair, top, bottom, shoes,
    accent...) is a cell of one 16x16 palette texture (Ped_Palette, 4x4-texel
    cells, PED_CELLS order) and the game's pedestrian shader recolours the
    cells per person (instance uniforms), so a whole crowd shares one material.
  * Skirts and dresses hang from the hips and follow the thighs halfway, so the
    hem sways without splitting between the legs.

Output contract (scripts/traffic/pedestrian_look.gd relies on these):
  * glTF: the armature "Rig" (53 bones, as the player's) with one skinned mesh
    per look, named "Ped_<look name>", sharing one skin; 1 unit = 1 m, origin
    between the feet on the ground, Y up, facing +Z.
  * One material, "Ped_Body", with the palette; UVs on cell centres in
    PED_CELLS order (cell i at column i % 4, row i // 4 from the bottom).
  * Clips (UAL names, in place, 24 fps; Godot drops "_Loop" and loops those):
    KEEP_CLIPS below.
  * Budgets: <= 10k triangles per person, <= 4 influences, 1 surface, one
    16x16 texture.
Deterministic: the same source gives the same file.
"""
import math
import os
import sys
import time

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_character as mc  # noqa: E402  (its main() only runs as a script)
from make_character import (  # noqa: E402
    SKIN, HAIR, SHIRT, JEANS, SHOE, SOLE, LIPS, BROW, MOUTH, LACES, HEELTAB,
    smin, smax, sstep, sd_ellipsoid, sd_capsule, sub, blur, VOX, GRID_O,
)

ROOT = mc.ROOT
OUT_DEFAULT = os.path.join(ROOT, "assets", "models", "character", "pedestrians.glb")

KEEP_CLIPS = [
    "Idle_Loop", "Walk_Loop", "Walk_Formal_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Idle_Talking_Loop",
    "Jump_Start", "Jump_Loop", "Jump_Land", "Hit_Chest", "Roll", "Dance_Loop",
]
# Not kept: Death01 (ART_BIBLE kid-safety: nobody is shown hurt), weapons, spells, driving and sitting.
TARGET_TRIS = 5600         # before the region cuts (they add ~2k) and the eyes
FACE_PASS = 2.2            # the face keeps the density of a TARGET_TRIS * FACE_PASS decimation

ACCENT = 11                # a cap, a jacket's zip: a second colour per person
LABEL_NAMES = mc.LABEL_NAMES + ["accent"]
LABEL_ORDER = [LIPS, MOUTH, HAIR, BROW, SHIRT, JEANS, SHOE, SOLE, LACES, HEELTAB, ACCENT]   # later wins

# Palette cells, in order (sRGB, ART_BIBLE.md §5: within 0.11-0.94). The game
# recolours skin (lips and mouth follow it), hair (and brows), top, bottom,
# shoe (laces and heel tab follow it) and accent per person; these are the
# defaults it starts from. Eyes and soles keep these colours.
PED_CELLS = ["skin", "lips", "sclera", "iris", "pupil", "hair", "top", "bottom", "shoe", "sole", "mouth",
             "laces", "heeltab", "accent"]
PED_PALETTE = {
    "skin": (0.76, 0.56, 0.44), "lips": (0.66, 0.43, 0.37), "sclera": (0.86, 0.84, 0.80),
    "iris": (0.27, 0.17, 0.11), "pupil": (0.11, 0.10, 0.10), "hair": (0.21, 0.14, 0.10),
    "top": (0.45, 0.55, 0.45), "bottom": (0.25, 0.28, 0.36), "shoe": (0.88, 0.87, 0.84),
    "sole": (0.31, 0.30, 0.29), "mouth": (0.45, 0.27, 0.24), "laces": (0.68, 0.68, 0.66),
    "heeltab": (0.36, 0.35, 0.34), "accent": (0.70, 0.55, 0.20),
}
LAB_CELL = {SKIN: "skin", LIPS: "lips", MOUTH: "mouth", HAIR: "hair", BROW: "hair", SHIRT: "top",
            JEANS: "bottom", SHOE: "shoe", SOLE: "sole", LACES: "laces", HEELTAB: "heeltab", ACCENT: "accent"}

# Builds: per bone, scale about its axis (see make_character.slim). "m" is the
# player's, "f" narrower in the shoulders, arms and ribs, "heavy" fuller.
BUILDS = {
    "m": dict(mc.SLIM),
    "f": {
        "DEF-upper_arm": (0.70, 0.72), "DEF-forearm": (0.78, 0.78, 0.70), "DEF-shoulder": (0.74, 0.80),
        "DEF-spine.003": (0.82, 0.88), "DEF-spine.002": (0.84, 0.90), "DEF-spine.001": (0.94, 0.95),
        "DEF-thigh": (0.96, 0.96), "DEF-shin": (0.90, 0.92), "DEF-neck": (0.84, 0.86),
        "DEF-hand": (0.90, 0.90), "DEF-foot": (0.92, 0.92),
    },
    "heavy": {
        "DEF-upper_arm": (0.88, 0.88), "DEF-forearm": (0.90, 0.90, 0.84), "DEF-shoulder": (0.92, 0.92),
        "DEF-spine.003": (0.98, 1.00), "DEF-spine.002": (1.02, 1.06), "DEF-spine.001": (1.04, 1.06),
        "DEF-thigh": (1.02, 1.02), "DEF-shin": (0.98, 0.98), "DEF-neck": (1.0, 1.0),
    },
}

# The people. body: build ("m", "f", "heavy"); hair: short, buzz, receding, ponytail, bun, long, bob, cap;
# top: tee, long, tank, jacket, dress; bottom: jeans, shorts, skirt (none under a dress).
LOOKS = [
    {"name": "tee_jeans_m", "body": "m", "hair": "short", "top": "tee", "bottom": "jeans"},
    {"name": "long_chinos_m", "body": "m", "hair": "buzz", "top": "long", "bottom": "jeans"},
    {"name": "tee_shorts_heavy", "body": "heavy", "hair": "cap", "top": "tee", "bottom": "shorts"},
    {"name": "jacket_m", "body": "m", "hair": "receding", "top": "jacket", "bottom": "jeans"},
    {"name": "tee_jeans_f", "body": "f", "hair": "ponytail", "top": "tee", "bottom": "jeans"},
    {"name": "dress_f", "body": "f", "hair": "long", "top": "dress", "bottom": "none"},
    {"name": "long_skirt_f", "body": "f", "hair": "bun", "top": "long", "bottom": "skirt"},
    {"name": "tank_shorts_f", "body": "f", "hair": "bob", "top": "tank", "bottom": "shorts"},
]

T0 = time.time()


def log(*a):
    print("[make_pedestrians %5.1fs]" % (time.time() - T0), *a, flush=True)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": OUT_DEFAULT, "only": None, "preview": None}
    for k in ("out", "only", "preview"):
        if "--" + k in argv:
            opts[k] = argv[argv.index("--" + k) + 1]
    if opts["out"]:
        opts["out"] = os.path.abspath(opts["out"])
    return opts


# ============================================================================= head and hair
def build_head(X, Y, Z, fem):
    """head and neck (no hair) as an SDF; also the cranium (hair is an offset of it).
    The player's head (make_character.build_head), a little finer for women."""
    AX = np.abs(X)
    front = np.clip((0.006 - Y) / 0.097, 0, 1) ** 1.5
    cran = sd_ellipsoid(X / (1 - 0.08 * front), Y, Z, (0, 0.006, 1.712), (0.0775, 0.097, 0.094))
    nar = 1 - 0.09 * np.clip((1.665 - Z) / 0.08, 0, 1)
    face = sd_ellipsoid(X / nar, Y, Z, (0, -0.028, 1.650), (0.069, 0.072, 0.070))
    muzzle = sd_ellipsoid(X, Y, Z, (0, -0.058, 1.609), (0.045, 0.044, 0.034))
    if fem:
        chin = sd_ellipsoid(X, Y, Z, (0, -0.081, 1.586), (0.017, 0.0140, 0.0140))
        jaw = sd_capsule(AX, Y, Z, (0.044, -0.014, 1.614), (0.016, -0.076, 1.584), 0.0100)
        ramus = sd_capsule(AX, Y, Z, (0.044, -0.014, 1.613), (0.051, -0.002, 1.655), 0.0100)
        brow = sd_capsule(AX, Y, Z, (0.0, -0.0885, 1.705), (0.044, -0.077, 1.703), 0.0055)
        ns = 0.88
    else:
        chin = sd_ellipsoid(X, Y, Z, (0, -0.083, 1.583), (0.020, 0.0160, 0.0160))
        jaw = sd_capsule(AX, Y, Z, (0.047, -0.014, 1.610), (0.017, -0.078, 1.580), 0.0115)
        ramus = sd_capsule(AX, Y, Z, (0.047, -0.014, 1.609), (0.054, -0.002, 1.655), 0.0115)
        brow = sd_capsule(AX, Y, Z, (0.0, -0.0895, 1.705), (0.046, -0.078, 1.703), 0.0068)
        ns = 1.0
    cheek = sd_ellipsoid(AX, Y, Z, (0.045, -0.066, 1.662), (0.022, 0.018, 0.018))
    H = smin(cran, face, 0.03)
    H = smin(H, muzzle, 0.025)
    H = smin(H, jaw, 0.03)
    H = smin(H, ramus, 0.03)
    H = smin(H, chin, 0.02)
    H = smin(H, cheek, 0.022)
    H = smin(H, brow, 0.014)
    H = blur(H.astype(np.float32), 1, 2)
    eyecut = sd_ellipsoid(AX, Y, Z, (mc.EYE_C[0], -0.0840, mc.EYE_C[2] - 0.0004), (0.0140, 0.0110, 0.0068))
    H = smax(H, -eyecut, 0.0035)
    nb = sd_capsule(X, Y, Z, (0, -0.0915, 1.690), (0, -0.0915 - 0.0205 * ns, 1.652), 0.0055 * ns, 0.0083 * ns)
    nt = sd_ellipsoid(X, Y, Z, (0, -0.0915 - 0.0207 * ns, 1.647), (0.0094 * ns, 0.0094 * ns, 0.0090 * ns))
    na = sd_ellipsoid(AX, Y, Z, (0.0117 * ns, -0.1015 + 0.003 * (1 - ns), 1.641), (0.0074 * ns, 0.0075, 0.0070 * ns))
    nc = sd_capsule(X, Y, Z, (0, -0.0915 - 0.021 * ns, 1.643), (0, -0.104, 1.635), 0.0055 * ns)
    H = smin(H, smin(smin(smin(nb, nt, 0.008), na, 0.006), nc, 0.005), 0.009)
    lf = 1.15 if fem else 1.0
    lu = sd_ellipsoid(X, Y - 0.011 * (X / 0.0235) ** 2, Z, (0, -0.1000, 1.6152), (0.0235, 0.0060 * lf, 0.0040 * lf))
    ll = sd_ellipsoid(X, Y - 0.010 * (X / 0.0205) ** 2, Z, (0, -0.0990, 1.6022), (0.0205, 0.0065 * lf, 0.0050 * lf))
    H = smin(H, smin(lu, ll, 0.002), 0.0025)
    H = smin(H, mc.ear_sdf(AX, Y, Z), 0.0045)
    if fem:
        neck = sd_capsule(X / 1.04, Y, Z, (0, 0.022, 1.46), (0, 0.008, 1.62), 0.056, 0.050)
    else:
        neck = sd_capsule(X / 1.06, Y, Z, (0, 0.022, 1.46), (0, 0.008, 1.62), 0.064, 0.057)
    return smin(H, neck, 0.02), cran


def hair_cap(X, Y, Z, cran, style):
    """hair close to the head above a hairline (an offset of the cranium) -> sdf"""
    AX = np.abs(X)
    th = np.degrees(np.arctan2(AX, -(Y - 0.004)))           # 0 front, 90 side, 180 back
    HL_T = [0, 25, 40, 50, 60, 72, 82, 100, 118, 140, 180]
    HL_Z = [1.763, 1.759, 1.752, 1.728, 1.678, 1.672, 1.716, 1.719, 1.672, 1.630, 1.612]
    hz = np.interp(th, HL_T, HL_Z)
    if style == "receding":     # higher at the temples and the front
        hz = hz + 0.022 * np.clip(1 - np.abs(th - 38) / 26, 0, 1) + 0.008 * np.clip(1 - th / 30, 0, 1)
    if style in ("ponytail", "bun", "long", "bob"):     # pulled back: a rounder, lower front hairline
        hz = hz - 0.006 * np.clip(1 - th / 50, 0, 1)
    reg = Z - hz                                             # > 0 above the hairline
    el = np.clip((Z - 1.70) / 0.10, 0, 1)
    side = np.clip(1 - np.abs(th - 95) / 45, 0, 1)
    if style == "buzz":
        thick = 0.0035 + 0.0015 * el
    elif style == "receding":
        thick = 0.005 + 0.007 * el - 0.0015 * side
    elif style in ("ponytail", "bun"):
        thick = 0.0055 + 0.0045 * el                        # sleek, pulled back
    elif style in ("long", "bob"):
        thick = 0.008 + 0.010 * el
    elif style == "cap":
        thick = 0.005 + 0.003 * el                           # mostly under the cap
    else:                                                    # short, a side part
        thick = 0.006 + 0.012 * el - 0.002 * side
        thick = thick + 0.004 * np.clip(1 - np.abs(X + 0.03) / 0.05, 0, 1) * sstep(1.74, 1.79, Z) * (Y < 0.04)
    thick = thick * (0.45 + 0.55 * sstep(0.0, 0.022, reg))  # thins out toward the hairline
    if style == "buzz":
        groove = 0.0
    else:
        gl = np.where(th < 60, X, Z)
        if style in ("ponytail", "bun", "long", "bob"):     # strands drawn back from the face
            gl = np.where(th < 120, Y + 0.3 * Z, Z)
        groove = (0.0007 * np.sin(2 * math.pi * gl / 0.019 + 1.3 * np.sin(Y * 40))
                  + 0.0004 * np.sin(2 * math.pi * gl / 0.0083 + 2.0 * np.sin(Y * 70 + 1))) * sstep(0.004, 0.02, reg)
    hair = cran - thick + groove
    hair = smax(hair, -reg, 0.002)
    return smax(hair, -(Z - 1.60), 0.002)


def hair_extra(X, Y, Z, style):
    """hair beyond the cap (a ponytail, a bun, long hair, a bob) -> sdf or None"""
    AX = np.abs(X)
    if style == "ponytail":
        tie = sd_ellipsoid(X, Y, Z, (0, 0.092, 1.738), (0.026, 0.020, 0.024))
        tail = sd_capsule(X, Y, Z, (0, 0.104, 1.735), (0, 0.142, 1.560), 0.024, 0.012)
        tail = smin(tail, sd_ellipsoid(X, Y, Z, (0, 0.125, 1.66), (0.030, 0.026, 0.06)), 0.02)
        return smin(tie, tail, 0.015)
    if style == "bun":
        return sd_ellipsoid(X, Y, Z, (0, 0.088, 1.775), (0.042, 0.036, 0.038))
    if style in ("long", "bob"):
        bob = style == "bob"
        bottom = (1.600 if bob else 1.455) + (0.9 if bob else 0.6) * X * X    # longer in the middle
        below = sstep(1.64, 1.50, Z)                       # 0 around the head .. 1 on the back
        yc = 0.010 + 0.040 * below
        xw = (0.101 if bob else 0.099) - (0.014 if bob else 0.030) * below
        yr = 0.104 - 0.050 * below
        e = np.sqrt((X / xw) ** 2 + ((Y - yc) / yr) ** 2)
        shell = (e - 1.0) * np.minimum(xw, yr)
        ang = np.arctan2(X, Y - yc)
        shell = shell + 0.0010 * np.sin(ang * 34.0) * sstep(1.70, 1.60, Z)      # strands
        shell = smax(shell, bottom - Z, 0.034 if bob else 0.022)                # rounded ends
        shell = smax(shell, Z - 1.765, 0.03)                                    # the cap covers the top
        front = -(Y - 0.004) / np.maximum(np.sqrt(X * X + (Y - 0.004) ** 2), 1e-6)   # 1 = straight ahead
        shell = smax(shell, (front - 0.40) * 0.08, 0.008)                       # the face stays clear
        shell = smax(shell, np.where(Z < 1.60, -0.006 - Y, -1.0), 0.008)         # behind the neck below the jaw
        return shell
    return None


def cap_sdf(X, Y, Z, cran):
    """a baseball cap: a crown over the cranium and a brim to the front"""
    crown = smax(cran - 0.014, 1.735 - Z - 0.02 * np.clip(-Y / 0.1, 0, 1), 0.006)
    brim = sd_ellipsoid(X, Y, Z, (0, -0.118, 1.742), (0.072, 0.068, 0.0045))
    brim = smax(brim, Y + 0.075, 0.004)
    btn = sd_ellipsoid(X, Y, Z, (0, 0.004, 1.816), (0.008, 0.008, 0.005))
    return smin(smin(crown, brim, 0.006), btn, 0.003)


# ============================================================================= body and clothes
def sculpt(body, look):
    """make_character.sculpt with a look: build, hair, top and bottom"""
    S = mc.Sculpt(body)
    A = S.A
    fem = look["body"] == "f"
    # smooth the mannequin's facets (not the fingers), the arms a bit more
    sl, X, Y, Z = sub((-0.74, -0.33, -0.03), (0.74, 0.25, 1.87))
    m = (1 - sstep(0.66, 0.73, np.abs(X))).astype(np.float32)
    A[sl] = A[sl] * (1 - m) + blur(A[sl], 2, 2) * m
    sl, X, Y, Z = sub((-0.70, -0.05, 1.30), (0.70, 0.20, 1.56))
    m = (sstep(0.20, 0.26, np.abs(X)) * (1 - sstep(0.62, 0.70, np.abs(X)))).astype(np.float32)
    A[sl] = A[sl] * (1 - m) + blur(A[sl], 2, 3) * m

    # head and neck, with the hair cap
    hsl, X, Y, Z = sub((-0.13, -0.17, 1.42), (0.13, 0.16, 1.86))
    HN, cran = build_head(X, Y, Z, fem)
    A[hsl] = smin(smax(A[hsl], Z - 1.535, 0.02), HN, 0.035)
    S.add_phi(LIPS, mc.lips_phi)
    S.add_phi(MOUTH, mc.mouth_phi)
    S.cut_extra[MOUTH] = [mc.mouth_centre]
    AX = np.abs(X)
    bi = sd_capsule(AX, Y, Z, (0.012, -0.0950, 1.7015), (0.031, -0.0930, 1.7055), 0.0036, 0.0030)
    bo = sd_capsule(AX, Y, Z, (0.031, -0.0930, 1.7055), (0.050, -0.0830, 1.7025), 0.0030, 0.0019)
    if fem:     # thinner, a little higher and more arched
        bi = sd_capsule(AX, Y, Z, (0.012, -0.0950, 1.7035), (0.031, -0.0930, 1.7085), 0.0029, 0.0025)
        bo = sd_capsule(AX, Y, Z, (0.031, -0.0930, 1.7085), (0.050, -0.0830, 1.7035), 0.0025, 0.0015)
    S.union(hsl, np.minimum(bi, bo) - 0.0002, BROW)
    del HN, cran

    # the mannequin's sculpted chest, abs and pelvis ledges go (all under the clothes)
    sl, X, Y, Z = sub((-0.26, -0.21, 0.85), (0.26, 0.23, 1.50))
    w = (sstep(0.88, 0.95, Z) * (1 - sstep(1.40, 1.48, Z)) * (1 - sstep(0.17, 0.24, np.abs(X)))).astype(np.float32)
    A[sl] = A[sl] * (1 - w) + blur(A[sl], 5, 2) * w
    if fem:     # bust and hips
        sl, X, Y, Z = sub((-0.20, -0.22, 1.15), (0.20, 0.10, 1.42))
        AX = np.abs(X)
        bust = sd_ellipsoid(AX, Y, Z, (0.058, -0.075, 1.285), (0.062, 0.056, 0.058))
        A[sl] = smin(A[sl], bust, 0.03)
        sl, X, Y, Z = sub((-0.26, -0.18, 0.78), (0.26, 0.20, 1.10))
        hips = sd_ellipsoid(X, Y, Z, (0, 0.012, 0.935), (0.170, 0.115, 0.120))
        A[sl] = smin(A[sl], hips, 0.04)
    elif look["body"] == "heavy":   # a belly and a fuller seat
        sl, X, Y, Z = sub((-0.26, -0.26, 0.90), (0.26, 0.20, 1.40))
        belly = sd_ellipsoid(X, Y, Z, (0, -0.055, 1.115), (0.150, 0.135, 0.175))
        A[sl] = smin(A[sl], belly, 0.06)
    body_sdf = A.copy()        # garments are offsets of the body without the other garments
    log("body and head")

    top(S, body_sdf, look)
    if look["bottom"] in ("jeans", "shorts"):
        trousers(S, body_sdf, look["bottom"] == "shorts")
    if look["bottom"] == "skirt" or look["top"] == "dress":
        skirt(S, body_sdf, JEANS if look["top"] != "dress" else SHIRT)
    mc_shoes(S, body_sdf)
    del body_sdf

    # hair (and a cap) last, so it lies over the clothes
    hsl, X, Y, Z = sub((-0.13, -0.17, 1.42), (0.13, 0.16, 1.86))
    _, cran = build_head(X, Y, Z, fem)
    S.union(hsl, hair_cap(X, Y, Z, cran, look["hair"]), HAIR)
    if look["hair"] == "cap":
        S.union(hsl, cap_sdf(X, Y, Z, cran), ACCENT)
    del cran
    esl, X, Y, Z = sub((-0.16, -0.17, 1.40), (0.16, 0.22, 1.86))
    extra = hair_extra(X, Y, Z, look["hair"])
    if extra is not None:
        S.union(esl, extra, HAIR)
    log("clothes and hair")
    return S


def top(S, body_sdf, look):
    """T-shirt, long sleeves, tank top, jacket or a dress's bodice (offsets of the body)"""
    kind = look["top"]
    fem = look["body"] == "f"
    reach = 0.75 if kind in ("long", "jacket") else 0.42
    sl, X, Y, Z = sub((-reach, -0.24, 0.80), (reach, 0.23, 1.62))
    AX = np.abs(X)
    a = body_sdf[sl]
    sh = blur(a, 6, 2)
    hang = sh.copy()                    # fabric hangs from the chest and shoulder blades
    for s in range(1, 34):
        shifted = np.empty_like(sh)
        shifted[:, :, :-s] = sh[:, :, s:]
        shifted[:, :, -s:] = sh[:, :, -1:]
        hang = np.minimum(hang, shifted + 0.30 * s * VOX)
    sh = blur(np.where(AX < 0.19, hang, sh), 1, 2)
    del hang, shifted
    loose = {"tee": 0.012, "long": 0.011, "tank": 0.010, "jacket": 0.020, "dress": 0.009}[kind]
    # looser toward the hem (clear of the trousers' waist) and the sleeve ends
    off = loose + 0.006 * sstep(1.06, 0.96, Z) + 0.003 * sstep(0.24, 0.345, AX) * (AX > 0.19)
    if kind in ("long", "jacket"):      # sleeves follow the arm to the wrist, a little looser at the cuff
        off = off - 0.002 * sstep(0.45, 0.70, AX) + 0.003 * sstep(0.62, 0.71, AX)
    sh = np.minimum(sh - off, a - 0.006)
    # neckline
    ycn = 0.020 - 0.10 * (Z - 1.46)                         # neck axis, leaning forward
    rxy = np.sqrt((X / 1.06) ** 2 + (Y - ycn) ** 2)
    fr = np.clip(-(Y - ycn) / np.maximum(rxy, 1e-6), 0, 1)
    if kind in ("tank", "dress") or (fem and kind == "tee"):
        R = (0.104 + 0.032 * fr ** 2) if kind != "tee" else (0.090 + 0.020 * fr ** 2)   # a scoop neck
        nz = 1.415 if kind != "tee" else 1.425
    elif kind == "jacket":
        R = 0.082 + 0.006 * fr ** 2
        nz = 1.44
    else:
        R = 0.086 + 0.014 * fr ** 2                         # crew neck, lower in front
        nz = 1.43
    sh = smax(sh, np.minimum(R - rxy, Z - nz), 0.003)
    if kind in ("tee", "long"):
        sh = sh - 0.0018 * sstep(R + 0.016, R + 0.004, rxy)  # collar rib
    sh = smax(sh, Z - 1.545, 0.003)
    # hem
    hem = {"tee": 0.955, "long": 0.950, "tank": 0.965, "jacket": 0.880, "dress": 1.02}[kind]
    if fem and kind in ("tee", "long", "tank"):
        hem += 0.025
    if look["bottom"] == "skirt":
        hem = 0.99                                          # tucked into the skirt
    sh = smax(sh, hem - Z, 0.004)
    # sleeves
    if kind == "tee":
        sh = smax(sh, AX - (0.33 if fem else 0.345), 0.004)  # above the elbow
    elif kind in ("long", "jacket"):
        sh = smax(sh, AX - 0.722, 0.004)                     # at the wrist
    else:                                                    # sleeveless: armholes from the armpit up
        sh = smax(sh, AX - (0.150 + 0.9 * np.clip(1.36 - Z, 0, 1)), 0.006)
        if kind == "tank":                                   # narrow straps over the shoulders
            strap = np.abs(AX - 0.115) - 0.024
            sh = smax(sh, np.where(Z > 1.40, strap, -1.0), 0.004)
    S.union(sl, sh, SHIRT)
    if kind == "jacket":
        # a stand-up collar and a zip (accent) down the front
        ycn = 0.020 - 0.10 * (Z - 1.46)
        rxy = np.sqrt((X / 1.06) ** 2 + (Y - ycn) ** 2)
        collar = smax(np.abs(rxy - 0.086) - 0.008, np.abs(Z - 1.475) - 0.032, 0.004)
        S.union(sl, collar, SHIRT)
        zip_ = np.maximum(np.maximum(np.abs(X) - 0.006, Z - 1.45), np.maximum(0.885 - Z, Y + 0.02))
        S.add_phi(ACCENT, (sl, np.broadcast_to(zip_, S.A[sl].shape).astype(np.float32)))
    del sh


def trousers(S, body_sdf, shorts):
    """make_character's jeans; shorts end above the knee"""
    sl, X, Y, Z = sub((-0.26, -0.20, -0.01), (0.26, 0.24, 1.12))
    AX = np.abs(X)
    a = body_sdf[sl]
    jn = np.minimum(blur(a, 3, 2) - 0.0065, a - 0.004)
    fly = smax(sd_ellipsoid(X, Y, Z, (0, -0.035, 0.905), (0.100, 0.050, 0.075)), 0.855 - Z, 0.01)
    jn = smin(jn, fly - 0.0065, 0.02)                       # a smooth front over the mannequin's pouch
    if shorts:
        tube = sd_capsule(AX, Y, Z, (0.093, 0.004, 0.80), (0.096, 0.008, 0.56), 0.080, 0.074)
        jn = np.where(Z < 0.80, smin(jn, tube, 0.04), jn)
        jn = smax(jn, 0.585 - Z + 0.02 * np.clip((AX - 0.09) / 0.08, -1, 1), 0.004)   # hem, a little higher outside
    else:
        tube = sd_capsule(AX, Y, Z, (0.093, 0.004, 0.52), (0.093, 0.022, 0.06), 0.063, 0.060)
        jn = np.where(Z < 0.62, smin(jn, tube, 0.05), jn)    # straight legs from the knee down
        jn = smax(jn, 0.074 - 0.14 * (Y - 0.03) - Z, 0.004)  # hem, lower at the heel
    jn = smax(jn, Z - 1.08, 0.004)                           # waist (under the shirt)
    S.union(sl, jn, JEANS)


SKIRT_TOP = 1.06            # the waistband's top
SKIRT_HIP = 0.99            # where the A-line starts to flare
SKIRT_HEM = 0.47


def skirt_shape(X, Y, Z):
    """an A-line skirt round both legs, from the hips to just below the knee"""
    t = np.clip((SKIRT_HIP - Z) / (SKIRT_HIP - SKIRT_HEM), 0, 1)
    rx = 0.150 + 0.112 * t ** 0.85
    ry = 0.118 + 0.068 * t ** 0.85
    yc = 0.014 + 0.012 * t
    d = (np.sqrt((X / rx) ** 2 + ((Y - yc) / ry) ** 2) - 1.0) * np.minimum(rx, ry)
    d = d + 0.0018 * np.sin(np.arctan2(Y - yc, X) * 9.0) * t      # soft folds toward the hem
    d = smax(d, Z - SKIRT_HIP, 0.03)
    return smax(d, SKIRT_HEM - Z, 0.006)


def skirt(S, body_sdf, label):
    """the A-line, joined to a waistband that hugs the body over the top's tucked-in hem"""
    sl, X, Y, Z = sub((-0.32, -0.26, SKIRT_HEM - 0.02), (0.32, 0.26, SKIRT_TOP + 0.04))
    a = body_sdf[sl]
    band = smax(a - 0.022, Z - SKIRT_TOP, 0.004)
    band = smax(band, SKIRT_HEM - Z, 0.004)
    S.union(sl, smin(skirt_shape(X, Y, Z), band, 0.025), label)


def mc_shoes(S, body_sdf):
    """the player's sneakers (make_character.sculpt), on every pedestrian"""
    sl, X, Y, Z = sub((-0.21, -0.26, -0.01), (0.21, 0.14, 0.17))
    AX = np.abs(X)
    fx = AX - 0.096
    a = body_sdf[sl]
    k0 = int(round((0.004 - GRID_O[2]) / VOX)) - sl[2].start
    k1 = int(round((0.075 - GRID_O[2]) / VOX)) - sl[2].start
    outline = a[:, :, k0:k1].min(axis=2, keepdims=True)
    outline = blur(np.repeat(outline, 3, axis=2), 2, 2)[:, :, 1:2] - 0.005
    zz = Z - 0.014 * np.clip((-Y - 0.12) / 0.09, 0, 1) ** 2
    hs = 0.030 - 0.007 * np.clip((0.05 - Y) / 0.2, 0, 1)
    sole = smax(outline, np.abs(zz - hs / 2) - hs / 2, 0.005)
    toebox = sd_ellipsoid(fx, Y, zz, (-0.002, -0.130, 0.030), (0.047, 0.080, 0.034))
    vamp = sd_capsule(fx, Y, Z, (-0.002, -0.090, 0.048), (0.0, 0.000, 0.080), 0.039)
    heel = sd_capsule(fx / 0.86, Y, Z, (0.0, 0.050, 0.035), (0.0, 0.042, 0.095), 0.041, 0.036)
    upper = smin(smin(toebox, vamp, 0.03), heel, 0.03)
    upper = smax(upper, outline + 0.0015, 0.005)
    foot = smax(smax(a - 0.004, Z - 0.10, 0.004), hs + 0.006 - Z, 0.003)
    upper = smin(upper, foot, 0.008)
    upper = smax(upper, hs + 0.001 - Z, 0.002)
    upper = smin(upper, sd_capsule(fx, Y, Z, (0.0, -0.045, 0.070), (0.0, 0.0, 0.112), 0.030), 0.012)
    upper = smax(upper, Z - (0.106 + 0.012 * sstep(0.03, -0.03, Y)), 0.004)
    S.union(sl, np.minimum(upper, sole), SHOE)
    S.add_phi(SOLE, (sl, (sole - upper).astype(np.float32)))

    def on_upper(p, d):
        return np.maximum(d, np.maximum(S.phi_at(SHOE, p), -S.phi_at(SOLE, p)))

    def laces(p):
        fx = np.abs(p[:, 0]) - 0.096
        d = np.maximum(np.maximum(np.abs(fx + 0.002) - 0.015, -0.112 - p[:, 1]), np.maximum(p[:, 1] + 0.02, 0.055 - p[:, 2]))
        return on_upper(p, d)

    def heel_tab(p):
        fx = np.abs(p[:, 0]) - 0.096
        d = np.maximum(np.maximum(np.abs(fx) - 0.016, 0.07 - p[:, 1]), np.maximum(0.034 - p[:, 2], p[:, 2] - 0.105))
        return on_upper(p, d)
    S.add_phi(LACES, laces)
    S.add_phi(HEELTAB, heel_tab)


# ============================================================================= mesh, material, weights
def surface(S, name):
    """make_character.surface with this file's budget and regions"""
    pts, quads = mc.sdf_to_mesh(S.A, S.bg)
    S.A = None
    me = mc.build_mesh(name, pts, quads)
    mc.keep_largest_component(me)
    o = mc.link(name, me)
    mc.decimate(o, TARGET_TRIS * FACE_PASS)
    co = mc.mesh_co(o.data)
    face = (co[:, 2] > 1.555) & (co[:, 2] < 1.73) & (co[:, 1] < -0.02) & (np.abs(co[:, 0]) < 0.078)
    mc.decimate(o, TARGET_TRIS, face.astype(float))
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for L in LABEL_ORDER:
        for extra in S.cut_extra.get(L, []):
            mc.iso_cut(bm, extra)
        mc.iso_cut(bm, lambda p, L=L: S.phi_at(L, p))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    bm.to_mesh(me)
    bm.free()
    vco = mc.mesh_co(me)
    fv = [list(p.vertices) for p in me.polygons]
    flab = np.full(len(fv), SKIN, np.int32)
    for L in LABEL_ORDER:
        ph = S.phi_at(L, vco)
        ph = np.where(np.isfinite(ph), ph, 1.0)
        flab[np.array([ph[v].mean() for v in fv]) < 0] = L
    counts = np.bincount(flab, minlength=len(LABEL_NAMES)).tolist()
    log(name, "regions", {n: c for n, c in zip(LABEL_NAMES, counts) if c})
    return o, flab


def palette():
    size, cell = 16, 4
    n = size // cell
    img = bpy.data.images.new("Ped_Palette", size, size, alpha=False)
    px = np.ones((size, size, 4), np.float32)
    for i, nm in enumerate(PED_CELLS):
        cx, cy = i % n, i // n
        px[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell, :3] = PED_PALETTE[nm]
    img.pixels = px.ravel()
    img.pack()

    def uv(nm):
        i = PED_CELLS.index(nm)
        return ((i % n + 0.5) / n, (i // n + 0.5) / n)
    return img, uv


def make_material(img):
    m = bpy.data.materials.new("Ped_Body")
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    tx.interpolation = 'Closest'
    nt.links.new(tx.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.75
    b.inputs["Metallic"].default_value = 0.0
    m.use_backface_culling = True
    return m


def shade(o, flab, mat, cell_uv):
    me = o.data
    me.materials.append(mat)
    uvl = me.uv_layers.new(name="UVMap")
    luv = np.zeros((len(me.loops), 2), np.float32)
    for p, l in zip(me.polygons, flab):
        luv[p.loop_start:p.loop_start + p.loop_total] = cell_uv(LAB_CELL[l])
    uvl.data.foreach_set("uv", luv.ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    bm = bmesh.new()
    bm.from_mesh(me)
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        a = e.calc_face_angle(0.0)
        f0, f1 = e.link_faces
        if (flab[f0.index] != flab[f1.index] and a > math.radians(32)) or a > math.radians(75):
            e.smooth = False
    bm.to_mesh(me)
    bm.free()


def skin(rig, o, flab, fused, eyes, look):
    """make_character.skin, then two fixes: skirts hang from the hips and follow each thigh
    halfway (so the hem sways without splitting between the legs), and hair follows only the
    head (long hair blends into the neck toward its ends, instead of the shoulders it lies on)"""
    co0 = mc.mesh_co(o.data)
    n_body = len(o.data.vertices)
    skirt_v = np.zeros(n_body, bool)
    hair_v = np.zeros(n_body, bool)
    lab_skirt = SHIRT if look["top"] == "dress" else (JEANS if look["bottom"] == "skirt" else -1)
    for p, l in zip(o.data.polygons, flab):
        if l == lab_skirt:
            skirt_v[list(p.vertices)] = True
        elif l == HAIR:
            hair_v[list(p.vertices)] = True
    skirt_v &= co0[:, 2] < SKIRT_TOP + 0.02
    mc.skin(rig, o, flab, fused, eyes)
    me = o.data
    W = mc.vertex_weights(o, rig.names)
    co = mc.mesh_co(me)
    sv = np.zeros(len(W), bool)
    sv[:n_body] = skirt_v
    hv = np.zeros(len(W), bool)
    hv[:n_body] = hair_v
    if sv.any():
        t = np.clip((SKIRT_HIP - co[:, 2]) / (SKIRT_HIP - SKIRT_HEM), 0, 1)
        follow = 0.5 * sstep(0.0, 1.0, t)                 # how much of the leg's swing the hem follows
        sx = sstep(-0.07, 0.07, co[:, 0])                 # left leg (+X) .. right leg
        Ws = np.zeros_like(W)
        Ws[:, rig.index["DEF-hips"]] = 1 - follow
        Ws[:, rig.index["DEF-thigh.L"]] = follow * sx
        Ws[:, rig.index["DEF-thigh.R"]] = follow * (1 - sx)
        blend = sstep(SKIRT_TOP + 0.02, SKIRT_TOP - 0.08, co[:, 2])[:, None]   # from the waist down
        W[sv] = (W * (1 - blend) + Ws * blend)[sv]
    if hv.any():
        wh = sstep(1.47, 1.60, co[:, 2])
        Wh = np.zeros_like(W)
        Wh[:, rig.index["DEF-head"]] = wh
        Wh[:, rig.index["DEF-neck"]] = (1 - wh) * 0.7
        Wh[:, rig.index["DEF-spine.003"]] = (1 - wh) * 0.3
        W[hv] = Wh[hv]
    if not (sv.any() or hv.any()):
        return
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    for bi, bn in enumerate(rig.names):
        idx = np.where(W[:, bi] > 0.005)[0]
        if not len(idx):
            continue
        g = o.vertex_groups.new(name=bn)
        q = np.round(W[idx, bi] * 1000).astype(int)
        for qv in np.unique(q):
            g.add(idx[q == qv].tolist(), qv / 1000.0, 'REPLACE')


# ============================================================================= preview
def render_preview(arm, objs, out_dir):
    """front and three-quarter Workbench shots of each look, palette colours"""
    os.makedirs(out_dir, exist_ok=True)
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.render.resolution_x, scn.render.resolution_y = 600, 900
    scn.render.film_transparent = False
    scn.world = scn.world or bpy.data.worlds.new("W")
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.05
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scn.collection.objects.link(cam)
    scn.camera = cam
    idle = bpy.data.actions.get("Idle_Loop")
    if idle:
        arm.animation_data_create()
        arm.animation_data.action = idle
        if hasattr(arm.animation_data, "action_slot") and idle.slots:
            arm.animation_data.action_slot = idle.slots[0]
        scn.frame_set(8)
    for o in objs:
        o.hide_render = True
    for o in objs:
        o.hide_render = False
        for tag, yaw in (("front", 0.0), ("three_quarter", 35.0), ("back", 180.0)):
            a = math.radians(yaw)
            cam.location = (4.0 * math.sin(a), -4.0 * math.cos(a), 0.93)
            cam.rotation_euler = (math.radians(90), 0, a)
            scn.render.filepath = os.path.join(out_dir, "%s_%s.png" % (o.name, tag))
            bpy.ops.render.render(write_still=True)
        o.hide_render = True
    bpy.data.objects.remove(cam, do_unlink=True)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()


# ============================================================================= main
def main():
    opts = parse_args()
    looks = [lk for lk in LOOKS if opts["only"] is None or lk["name"] in opts["only"].split(",")]
    if not looks:
        mc.fail("no look named %s" % opts["only"])
    src_glb = mc.ensure_source()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src_glb)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    src = bpy.data.objects["Mannequin"]
    rig = mc.Rig(arm)
    prepared = mc.prepare_source(rig, src)
    img, cell_uv = palette()
    mat = make_material(img)

    fused_by_build = {}
    made = []
    for look in looks:
        b = look["body"]
        if b not in fused_by_build:
            mc.SLIM.clear()
            mc.SLIM.update(BUILDS[b])
            fused_by_build[b] = mc.fuse(rig, prepared)
            fused_by_build[b].name = "Fused_" + b
        fused = fused_by_build[b]
        S = sculpt(fused, look)
        name = "Ped_" + look["name"]
        o, flab = surface(S, name)
        del S
        shade(o, flab, mat, cell_uv)
        eyes = mc.make_eyes(mat, cell_uv)
        skin(rig, o, flab, fused, eyes, look)
        o.name = name
        o.data.name = name
        made.append(o)
    mc.SLIM.clear()
    mc.SLIM.update(BUILDS["m"])
    for ob in [src, prepared] + list(fused_by_build.values()):
        bpy.data.objects.remove(ob, do_unlink=True)

    for ac in list(bpy.data.actions):
        if ac.name not in KEEP_CLIPS:
            bpy.data.actions.remove(ac)
    missing = [c for c in KEEP_CLIPS if c not in bpy.data.actions]
    if missing:
        mc.fail("clips missing from the source: %s" % missing)
    for ac in bpy.data.actions:
        ac.use_fake_user = True
    arm.name = "Rig"
    for o in made:
        o.parent = arm
        o.modifiers.new("Armature", 'ARMATURE').object = arm
    arm.animation_data_create()
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.scene.render.fps = 24

    total = 0
    for o in made:
        me = o.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total += tris
        co = mc.mesh_co(me)
        log("%-24s %5d tris, %5d verts, height %.3f m" % (o.name, tris, len(me.vertices), co[:, 2].max()))
        if tris > 10000:
            mc.fail("%s has %d triangles (budget 10k)" % (o.name, tris))
    if opts["preview"]:
        render_preview(arm, made, opts["preview"])
    out = opts["out"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True,
                              export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True,
                              export_yup=True, export_apply=False, export_materials='EXPORT',
                              export_image_format='AUTO', export_extras=False)
    log("wrote", out, "(%d KB, %d looks, %d tris)" % (os.path.getsize(out) // 1024, len(made), total))


if __name__ == "__main__":
    main()
