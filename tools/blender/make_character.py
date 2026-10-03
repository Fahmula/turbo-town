"""Generates the player character (assets/models/character/player.glb).

Run headless from the project root:
    blender -b -P tools/blender/make_character.py
    blender -b -P tools/blender/make_character.py -- --out /tmp/player.glb   (anywhere else)

Source: Quaternius "Universal Animation Library" (Standard), CC0 1.0,
https://opengameart.org/node/174563. The zip is cached in
build/character_sources/quaternius_ual1/ (gitignored); if it's missing this
script downloads it and checks its SHA-256 before using it. From it we keep the
53-bone rig and its in-place clips exactly (bone names, hierarchy, rest pose,
clip names), and replace the segmented, faceless mannequin with a casually
dressed adult (stylized realism, ART_BIBLE.md §0, §4-§6): one continuous skin,
a slimmer build, a modelled face, hair, T-shirt, jeans and sneakers.

How it works (all in the rig's T-pose rest space; Blender Z-up, the character
faces -Y, i.e. glTF +Z):
 1. Prepare the mannequin: slim the chunky hands and fingers and spread the
    fingers a little so they stay separate, close the ~100 open segment shells.
 2. Fuse: the shells become one signed-distance volume (OpenVDB, 3.5 mm voxels)
    and one continuous surface. Its skin weights come from the mannequin (Data
    Transfer, nearest face interpolated).
 3. Slim the bodybuilder: shrink each vertex toward its bones' axes, blended by
    its weights (narrower deltoids, arms, chest and lats; less V-taper).
 4. Sculpt in SDF space (numpy arrays): smooth the mannequin's facets; replace
    its egg head with a modelled head and neck (cranium, face, jaw, nose, brow,
    lips, eye sockets, ears; build_head); hair is an offset of the cranium above
    a shaped hairline with a quiff and soft strand grooves; brows are small
    solids. Garments are offset solids unioned onto the body: a loose crew-neck
    T-shirt (hangs from chest and shoulder blades, collar rib, rounded hems,
    sleeves above the elbow), straight-leg jeans (smooth fly, tubes from the
    knee down, a hem resting on the shoe) and sneakers (sole slab from the foot
    outline, toe box, vamp, tongue, heel counter). Each part keeps a field
    phi (< 0 where it is the outer surface) for its material region.
 5. Mesh the volume, decimate (mirror-symmetric quadric collapse; the face is
    frozen at a higher density), then cut the surface exactly along every
    region boundary (phi = 0) so hems, hairline, lips and sole are clean lines.
    Hard edges where regions fold.
 6. Materials: 5 surfaces (Char_Skin, Char_Hair, Char_Shirt, Char_Trousers,
    Char_Shoes) sharing one 16x16 palette texture (Char_Palette, 4x4-texel
    cells, every face's UVs on one cell centre): skin/lips/mouth/eyes, hair and
    brows, shirt, jeans, shoe upper/sole. Eyes are small spheres (skin material).
 7. Weights onto the final mesh, the shirt rides on the hips (no thigh weight,
    a little smoothing), at most 4 influences, normalised; then the fingers go
    back to their rest angle. Export with the kept clips.

Output contract (the game relies on these; scenes/player/player_character.tscn
turns the model 180 degrees so it faces -Z):
  * glTF: skinned mesh "Character" under the armature "Rig" (53 bones, DEF-*
    names from the source, root bone "root"); 1 unit = 1 m, origin between the
    feet on the ground, Y up, the character faces +Z.
  * Clips (UAL names, in place, 24 fps; Godot drops "_Loop" and loops those):
    KEEP_CLIPS below.
  * Budgets: about 17k triangles, <= 4 influences, 5 surfaces, one 16x16
    texture, GLB under 2 MB.
Deterministic: the same source gives the same file.
"""
import hashlib
import math
import os
import sys
import time
import urllib.request
import zipfile

import bmesh
import bpy
import numpy as np
import openvdb as vdb
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_DIR = os.path.join(ROOT, "build", "character_sources", "quaternius_ual1")
SRC_ZIP = os.path.join(SRC_DIR, "universal_animation_librarystandard.zip")
SRC_URL = "https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip"
SRC_SHA256 = "18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2"
SRC_MEMBER = "Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb"
OUT_DEFAULT = os.path.join(ROOT, "assets", "models", "character", "player.glb")

KEEP_CLIPS = [
    "Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Jump_Start", "Jump_Loop", "Jump_Land",
    "Sitting_Enter", "Sitting_Idle_Loop", "Sitting_Exit", "Driving_Loop", "Interact", "Push_Loop",
    "Crouch_Idle_Loop", "Crouch_Fwd_Loop", "Idle_Talking_Loop", "Walk_Formal_Loop",
    "Hit_Chest",      # short stagger: a bump from a car or a prop
]
# Not kept: Death01 (a fall onto the back; ART_BIBLE kid-safety, nobody is shown hurt), Hit_Head,
# Roll, and the combat / pistol / sword / spell / swim / dance clips.
TARGET_TRIS = 13500        # before the region cuts (they add ~3k) and the eyes
FACE_PASS = 3.0            # the face keeps the density of a TARGET_TRIS * FACE_PASS decimation

T0 = time.time()


def log(*a):
    print("[make_character %5.1fs]" % (time.time() - T0), *a, flush=True)


def fail(msg):
    print("\nERROR (make_character): " + msg + "\n", flush=True)
    sys.exit(1)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = OUT_DEFAULT
    if "--out" in argv:
        out = os.path.abspath(argv[argv.index("--out") + 1])
    return out


# ============================================================================= source
def ensure_source():
    """the UAL Godot GLB, downloaded and checked if needed"""
    glb = os.path.join(SRC_DIR, *SRC_MEMBER.split("/"))
    os.makedirs(SRC_DIR, exist_ok=True)
    if not os.path.exists(SRC_ZIP):
        log("downloading", SRC_URL)
        try:
            req = urllib.request.Request(SRC_URL, headers={"User-Agent": "turbo-town-asset-build"})
            with urllib.request.urlopen(req, timeout=120) as r, open(SRC_ZIP + ".part", "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(SRC_ZIP + ".part", SRC_ZIP)
        except Exception as e:  # noqa: BLE001
            fail("could not download the Universal Animation Library (%s).\n"
                 "Download it by hand from %s\nand put it at %s" % (e, SRC_URL, SRC_ZIP))
    h = hashlib.sha256()
    with open(SRC_ZIP, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != SRC_SHA256:
        fail("%s has SHA-256 %s, expected %s.\nDelete it and run again to re-download."
             % (SRC_ZIP, h.hexdigest(), SRC_SHA256))
    if not os.path.exists(glb):
        with zipfile.ZipFile(SRC_ZIP) as z:
            z.extract(SRC_MEMBER, SRC_DIR)
    return glb


# ============================================================================= mesh helpers
def mesh_co(me):
    a = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3).astype(np.float64)


def set_co(me, co):
    me.vertices.foreach_set("co", np.asarray(co, np.float32).ravel())
    me.update()


def mesh_tris(me):
    me.calc_loop_triangles()
    t = np.empty(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("vertices", t)
    return t.reshape(-1, 3)


def mesh_edges(me):
    e = np.empty(len(me.edges) * 2, np.int32)
    me.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def build_mesh(name, verts, quads):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", np.asarray(verts, np.float32).ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.ravel().astype(np.int32))
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", (np.arange(len(quads)) * 4).astype(np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    return me


def link(name, me):
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def components(n, edges):
    """connected component label per vertex"""
    lab = np.arange(n)
    e0, e1 = edges[:, 0], edges[:, 1]
    while True:
        m = np.minimum(lab[e0], lab[e1])
        new = lab.copy()
        np.minimum.at(new, e0, m)
        np.minimum.at(new, e1, m)
        new = new[new]
        if np.array_equal(new, lab):
            return lab
        lab = new


def keep_largest_component(me):
    lab = components(len(me.vertices), mesh_edges(me))
    big = np.argmax(np.bincount(lab))
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if lab[v.index] != big], context='VERTS')
    bm.to_mesh(me)
    bm.free()


def vertex_weights(obj, names):
    gi = {g.index: names.index(g.name) for g in obj.vertex_groups if g.name in names}
    W = np.zeros((len(obj.data.vertices), len(names)), np.float64)
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in gi:
                W[v.index, gi[g.group]] = g.weight
    return W


def transfer_groups(src_obj, dst_obj):
    """skin weights by nearest face, interpolated"""
    for g in src_obj.vertex_groups:
        if g.name not in dst_obj.vertex_groups:
            dst_obj.vertex_groups.new(name=g.name)
    m = dst_obj.modifiers.new("DT", 'DATA_TRANSFER')
    m.object = src_obj
    m.use_vert_data = True
    m.data_types_verts = {'VGROUP_WEIGHTS'}
    m.vert_mapping = 'POLYINTERP_NEAREST'
    m.layers_vgroup_select_src = 'ALL'
    m.layers_vgroup_select_dst = 'NAME'
    with bpy.context.temp_override(object=dst_obj, active_object=dst_obj):
        bpy.ops.object.modifier_apply(modifier=m.name)


def squash_to_axis(co, idx, p0, d, s1, s2=None, up=(0, 0, 1)):
    """scale vertices toward the line p0 + t*d (s2: a second factor along `up`)"""
    d = np.asarray(d, float)
    d = d / np.linalg.norm(d)
    r = co[idx] - p0
    t = r @ d
    perp = r - np.outer(t, d)
    if s2 is None:
        co[idx] = p0 + np.outer(t, d) + perp * s1
    else:
        u = np.asarray(up, float)
        u = u - (u @ d) * d
        u /= np.linalg.norm(u)
        pu = perp @ u
        co[idx] = p0 + np.outer(t, d) + (perp - np.outer(pu, u)) * s1 + np.outer(pu, u) * s2


def rot_z(co, idx, pivot, ang, w=None):
    """rotate about a vertical axis through pivot; w scales the angle per vertex"""
    r = co[idx] - pivot
    a = ang * (np.ones(len(idx)) if w is None else w)
    c, s = np.cos(a), np.sin(a)
    co[idx] = pivot + np.stack([c * r[:, 0] - s * r[:, 1], s * r[:, 0] + c * r[:, 1], r[:, 2]], 1)


# ============================================================================= SDF grid (OpenVDB <-> numpy)
VOX = 0.0035
GRID_O = np.array([-1.0, -0.33, -0.03])       # world position of voxel (0, 0, 0); the T-pose fits
GRID_N = (int(2.0 / VOX) + 1, int(0.58 / VOX) + 1, int(1.90 / VOX) + 1)
BAND = 10.0                                    # narrow band, voxels each side


def xform():
    V, O = VOX, GRID_O
    return vdb.createLinearTransform([[V, 0, 0, 0], [0, V, 0, 0], [0, 0, V, 0], [O[0], O[1], O[2], 1]])


def mesh_to_sdf(co, tris):
    g = vdb.FloatGrid.createLevelSetFromPolygons(np.asarray(co, np.float32), triangles=np.asarray(tris, np.uint32),
                                                 transform=xform(), exBandWidth=BAND, inBandWidth=BAND)
    a = np.empty(GRID_N, np.float32)
    g.copyToArray(a, ijk=(0, 0, 0))
    return a, float(g.background)


def sdf_to_mesh(a, bg):
    g = vdb.FloatGrid(bg)
    g.transform = xform()
    g.copyFromArray(np.ascontiguousarray(a, np.float32), ijk=(0, 0, 0), tolerance=0.0)
    pts, quads = g.convertToQuads(0.0)
    return pts.astype(np.float64), quads.astype(np.int64)


def sub(lo, hi):
    """index slices + broadcastable world coordinates (X, Y, Z) of a world-space box"""
    i0 = np.maximum(np.floor((np.array(lo) - GRID_O) / VOX).astype(int), 0)
    i1 = np.minimum(np.ceil((np.array(hi) - GRID_O) / VOX).astype(int) + 1, GRID_N)
    sl = tuple(slice(int(a), int(b)) for a, b in zip(i0, i1))
    X = (GRID_O[0] + VOX * np.arange(i0[0], i1[0]))[:, None, None]
    Y = (GRID_O[1] + VOX * np.arange(i0[1], i1[1]))[None, :, None]
    Z = (GRID_O[2] + VOX * np.arange(i0[2], i1[2]))[None, None, :]
    return sl, X, Y, Z


def sample_box(arr, sl, pts):
    """trilinear sample of a box array at world points (inf outside the box)"""
    i0 = np.array([s.start for s in sl])
    shp = np.array(arr.shape)
    f = (pts - GRID_O) / VOX - i0
    ok = np.all((f >= 0) & (f <= shp - 1), axis=1)
    fi = np.clip(np.floor(f).astype(int), 0, shp - 2)
    t = np.clip(f - fi, 0, 1)
    out = np.zeros(len(pts))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = ((t[:, 0] if dx else 1 - t[:, 0]) * (t[:, 1] if dy else 1 - t[:, 1])
                     * (t[:, 2] if dz else 1 - t[:, 2]))
                out += w * arr[fi[:, 0] + dx, fi[:, 1] + dy, fi[:, 2] + dz]
    out[~ok] = np.inf
    return out


def blur_axis(a, r, axis):
    """box blur of radius r voxels along one axis (edges clamped)"""
    pad = [(0, 0)] * 3
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, r, passes=2):
    for _ in range(passes):
        for ax in range(3):
            a = blur_axis(a, r, ax)
    return a


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def sd_ellipsoid(X, Y, Z, c, r):
    px, py, pz = (X - c[0]) / r[0], (Y - c[1]) / r[1], (Z - c[2]) / r[2]
    k0 = np.sqrt(px * px + py * py + pz * pz)
    k1 = np.sqrt((px / r[0]) ** 2 + (py / r[1]) ** 2 + (pz / r[2]) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_capsule(X, Y, Z, a, b, r1, r2=None):
    """capsule a-b, radius r1 (tapering to r2)"""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    h = np.clip((px * ba[0] + py * ba[1] + pz * ba[2]) / (ba @ ba), 0, 1)
    d = np.sqrt((px - ba[0] * h) ** 2 + (py - ba[1] * h) ** 2 + (pz - ba[2] * h) ** 2)
    return d - (r1 if r2 is None else r1 + (r2 - r1) * h)


# ============================================================================= regions
SKIN, HAIR, SHIRT, JEANS, SHOE, SOLE, LIPS, BROW, MOUTH, LACES, HEELTAB = range(11)
LABEL_NAMES = ["skin", "hair", "shirt", "jeans", "shoe", "sole", "lips", "brow", "mouth", "laces", "heeltab"]
LABEL_ORDER = [LIPS, MOUTH, HAIR, BROW, SHIRT, JEANS, SHOE, SOLE, LACES, HEELTAB]     # where they overlap, later wins

# palette (sRGB, ART_BIBLE.md §5: within 0.11-0.94). The shirt is a warm red-orange: the
# world is greens, greys, sand and sea blue, so the player reads at a glance without
# borrowing a UI or marker colour.
PALETTE = {
    "skin": (0.76, 0.56, 0.44), "lips": (0.66, 0.43, 0.37), "sclera": (0.86, 0.84, 0.80),
    "iris": (0.27, 0.17, 0.11), "pupil": (0.11, 0.10, 0.10), "hair": (0.21, 0.14, 0.10),
    "shirt": (0.77, 0.30, 0.20), "jeans": (0.21, 0.30, 0.46), "shoe": (0.88, 0.87, 0.84),
    "sole": (0.31, 0.30, 0.29), "mouth": (0.45, 0.27, 0.24), "laces": (0.68, 0.68, 0.66),
    "heeltab": (0.36, 0.35, 0.34),
}
MATERIALS = [("Char_Skin", 0.55), ("Char_Hair", 0.6), ("Char_Shirt", 0.85), ("Char_Trousers", 0.8),
             ("Char_Shoes", 0.6)]     # (name, roughness); metallic 0
LAB_MAT = {SKIN: 0, LIPS: 0, MOUTH: 0, HAIR: 1, BROW: 1, SHIRT: 2, JEANS: 3, SHOE: 4, SOLE: 4, LACES: 4, HEELTAB: 4}
LAB_CELL = {SKIN: "skin", LIPS: "lips", MOUTH: "mouth", HAIR: "hair", BROW: "hair", SHIRT: "shirt",
            JEANS: "jeans", SHOE: "shoe", SOLE: "sole", LACES: "laces", HEELTAB: "heeltab"}


# ============================================================================= head
EYE_C = (0.0315, -0.0718, 1.684)      # eyeball centre (x mirrored), the face looks toward -Y
EYE_R = 0.0120


def ear_sdf(AX, Y, Z):
    E = np.array([0.0745, 0.010, 1.675])
    w = np.array([math.cos(math.radians(30)), -math.sin(math.radians(30)), 0.0])    # outward, 30 deg forward
    u = np.array([0.0, math.sin(math.radians(15)), math.cos(math.radians(15))])       # up, tilted back
    u -= (u @ w) * w
    u /= np.linalg.norm(u)
    v = np.cross(u, w)
    px, py, pz = AX - E[0], Y - E[1], Z - E[2]
    pu = px * u[0] + py * u[1] + pz * u[2]
    pv = px * v[0] + py * v[1] + pz * v[2]
    pw = px * w[0] + py * w[1] + pz * w[2]
    aur = sd_ellipsoid(pv, pu, pw, (0.0015, 0.002, -0.001), (0.0175, 0.0305, 0.0045))
    lobe = sd_ellipsoid(pv, pu, pw, (0.001, -0.023, -0.0005), (0.0095, 0.0105, 0.0042))
    e = np.sqrt((pv / 0.0150) ** 2 + ((pu - 0.002) / 0.0280) ** 2)
    rim = np.sqrt(((e - 1.0) * 0.019) ** 2 + (pw - 0.0015) ** 2) - 0.0034            # the helix
    rim = np.where(pu > -0.012, rim, rim + 0.01 * np.clip((-0.012 - pu) / 0.006, 0, 1))
    conch = sd_ellipsoid(pv, pu, pw, (-0.0025, -0.004, 0.0045), (0.0085, 0.0115, 0.0042))
    root = sd_capsule(pv, pu, pw, (-0.010, 0.012, -0.004), (-0.010, -0.016, -0.004), 0.0055)
    root = smin(root, sd_ellipsoid(pv, pu, pw, (-0.006, -0.002, -0.009), (0.011, 0.020, 0.006)), 0.004)
    d = smin(smin(aur, lobe, 0.006), rim, 0.003)
    d = smax(d, -conch, 0.003)
    return smin(d, root, 0.004)


def mouth_line(p):
    """centre line of the mouth (thinner than the grid, so evaluated exactly at the vertices)"""
    zm = 1.6094 + 0.0006 * (p[:, 0] / 0.024) ** 2
    inside = (np.abs(p[:, 0]) < 0.0235) & (p[:, 1] < -0.088) & (np.abs(p[:, 2] - 1.609) < 0.02)
    return zm, inside


def mouth_centre(p):
    zm, inside = mouth_line(p)
    return np.where(inside, p[:, 2] - zm, 1.0)


def mouth_phi(p):
    zm, inside = mouth_line(p)
    return np.where(inside, np.maximum(np.abs(p[:, 2] - zm) - 0.0011, np.abs(p[:, 0]) - 0.0235), 1.0)


def lips_phi(p):
    """lip colour: an almond around the mouth line, a little taller below it"""
    zm, inside = mouth_line(p)
    hz = np.where(p[:, 2] > zm, 0.0056, 0.0068)
    e = np.sqrt((p[:, 0] / 0.0250) ** 2 + ((p[:, 2] - zm) / hz) ** 2)
    return np.where(inside, (e - 1.0) * 0.006, 1.0)


def build_head(X, Y, Z):
    """head, neck, hair and brows as an SDF on broadcast coordinates -> (sdf, {label: phi})"""
    AX = np.abs(X)
    phis = {}
    front = np.clip((0.006 - Y) / 0.097, 0, 1) ** 1.5
    cran = sd_ellipsoid(X / (1 - 0.08 * front), Y, Z, (0, 0.006, 1.712), (0.0775, 0.097, 0.094))
    nar = 1 - 0.09 * np.clip((1.665 - Z) / 0.08, 0, 1)
    face = sd_ellipsoid(X / nar, Y, Z, (0, -0.028, 1.650), (0.069, 0.072, 0.070))
    muzzle = sd_ellipsoid(X, Y, Z, (0, -0.058, 1.609), (0.045, 0.044, 0.034))
    chin = sd_ellipsoid(X, Y, Z, (0, -0.083, 1.583), (0.020, 0.0160, 0.0160))
    jaw = sd_capsule(AX, Y, Z, (0.047, -0.014, 1.610), (0.017, -0.078, 1.580), 0.0115)
    ramus = sd_capsule(AX, Y, Z, (0.047, -0.014, 1.609), (0.054, -0.002, 1.655), 0.0115)
    cheek = sd_ellipsoid(AX, Y, Z, (0.045, -0.066, 1.662), (0.022, 0.018, 0.018))
    brow = sd_capsule(AX, Y, Z, (0.0, -0.0895, 1.705), (0.046, -0.078, 1.703), 0.0068)
    H = smin(cran, face, 0.03)
    H = smin(H, muzzle, 0.025)
    H = smin(H, jaw, 0.03)
    H = smin(H, ramus, 0.03)
    H = smin(H, chin, 0.02)
    H = smin(H, cheek, 0.022)
    H = smin(H, brow, 0.014)
    H = blur(H.astype(np.float32), 1, 2)
    eyecut = sd_ellipsoid(AX, Y, Z, (EYE_C[0], -0.0840, EYE_C[2] - 0.0004), (0.0140, 0.0110, 0.0068))
    H = smax(H, -eyecut, 0.0035)
    nb = sd_capsule(X, Y, Z, (0, -0.0915, 1.690), (0, -0.1120, 1.652), 0.0055, 0.0083)
    nt = sd_ellipsoid(X, Y, Z, (0, -0.1122, 1.647), (0.0094, 0.0094, 0.0090))
    na = sd_ellipsoid(AX, Y, Z, (0.0117, -0.1015, 1.641), (0.0074, 0.0075, 0.0070))
    nc = sd_capsule(X, Y, Z, (0, -0.1125, 1.643), (0, -0.104, 1.635), 0.0055)
    H = smin(H, smin(smin(smin(nb, nt, 0.008), na, 0.006), nc, 0.005), 0.009)
    lu = sd_ellipsoid(X, Y - 0.011 * (X / 0.0235) ** 2, Z, (0, -0.1000, 1.6152), (0.0235, 0.0060, 0.0040))
    ll = sd_ellipsoid(X, Y - 0.010 * (X / 0.0205) ** 2, Z, (0, -0.0990, 1.6022), (0.0205, 0.0065, 0.0050))
    H = smin(H, smin(lu, ll, 0.002), 0.0025)
    H = smin(H, ear_sdf(AX, Y, Z), 0.0045)
    neck = sd_capsule(X / 1.06, Y, Z, (0, 0.022, 1.46), (0, 0.008, 1.62), 0.064, 0.057)
    HN = smin(H, neck, 0.02)
    # hair: an offset of the cranium above a hairline given by angle around the head
    th = np.degrees(np.arctan2(AX, -(Y - 0.004)))           # 0 front, 90 side, 180 back
    HL_T = [0, 25, 40, 50, 60, 72, 82, 100, 118, 140, 180]
    HL_Z = [1.763, 1.759, 1.752, 1.728, 1.678, 1.672, 1.716, 1.719, 1.672, 1.630, 1.612]
    reg = Z - np.interp(th, HL_T, HL_Z)                     # > 0 above the hairline
    el = np.clip((Z - 1.70) / 0.10, 0, 1)
    side = np.clip(1 - np.abs(th - 95) / 45, 0, 1)
    thick = 0.006 + 0.014 * el ** 0.8 - 0.002 * side        # short sides, fuller top
    thick = thick + 0.009 * np.clip(1 - th / 55, 0, 1) * sstep(1.74, 1.80, Z)    # front quiff
    thick = thick * (0.45 + 0.55 * sstep(0.0, 0.022, reg))  # thins out toward the hairline
    gl = np.where(th < 60, X, Z)
    groove = (0.0007 * np.sin(2 * math.pi * gl / 0.019 + 1.3 * np.sin(Y * 40))
              + 0.0004 * np.sin(2 * math.pi * gl / 0.0083 + 2.0 * np.sin(Y * 70 + 1))) * sstep(0.004, 0.02, reg)
    hair = cran - thick + groove
    hair = smax(hair, -reg, 0.002)
    hair = smax(hair, -(Z - 1.60), 0.002)
    phis[HAIR] = hair - HN
    HN = np.minimum(HN, hair)
    bi = sd_capsule(AX, Y, Z, (0.012, -0.0950, 1.7015), (0.031, -0.0930, 1.7055), 0.0036, 0.0030)
    bo = sd_capsule(AX, Y, Z, (0.031, -0.0930, 1.7055), (0.050, -0.0830, 1.7025), 0.0030, 0.0019)
    browh = np.minimum(bi, bo) - 0.0002
    phis[BROW] = browh - HN
    HN = np.minimum(HN, browh)
    return HN, phis


# ============================================================================= pipeline
class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.names = [b.name for b in arm.data.bones if b.name != "root"]
        self.index = {n: i for i, n in enumerate(self.names)}

    def head(self, n):
        return np.array(self.arm.data.bones[n].head_local)

    def tail(self, n):
        return np.array(self.arm.data.bones[n].tail_local)


FINGERS = ("index", "middle", "ring", "pinky")
SPREAD = {"index": -9.0, "middle": -2.0, "ring": 5.0, "pinky": 12.0}   # degrees, sign for the left hand


def finger_bones(f, side):
    return ["DEF-f_%s.0%d.%s" % (f, i, side) for i in (1, 2, 3)]


def prepare_source(rig, src):
    """mannequin copy with slimmer hands, spread fingers and closed segment shells"""
    me = src.data.copy()
    co = mesh_co(me)
    W = vertex_weights(src, rig.names)
    lab = components(len(co), mesh_edges(me))
    dom = {k: rig.names[int(np.argmax(W[lab == k].sum(0)))] for k in np.unique(lab)}

    def island_verts(bones):
        return np.where(np.isin(lab, [k for k, b in dom.items() if b in bones]))[0]

    for side, sg in (("L", 1), ("R", -1)):
        hand = "DEF-hand." + side
        squash_to_axis(co, island_verts([hand]), rig.head(hand), (sg, 0, 0), 0.86, 0.74)
        for f in FINGERS:
            names = finger_bones(f, side)
            idx = island_verts(names)
            p0 = rig.head(names[0])
            squash_to_axis(co, idx, p0, rig.tail(names[0]) - p0, 0.84)
            rot_z(co, idx, p0, math.radians(SPREAD[f]) * sg)
        for i in (1, 2, 3):
            n = "DEF-thumb.0%d.%s" % (i, side)
            idx = island_verts([n])
            if len(idx):
                squash_to_axis(co, idx, rig.head(n), rig.tail(n) - rig.head(n), 0.85)
    set_co(me, co)
    bm = bmesh.new()
    bm.from_mesh(me)
    res = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.triangulate(bm, faces=res["faces"])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link("SourcePrepared", me)
    for g in src.vertex_groups:
        if g.name not in o.vertex_groups:
            o.vertex_groups.new(name=g.name)
    return o


# per bone: perpendicular scale (x, y) about the bone axis; a third value = scale at the bone's head
SLIM = {
    "DEF-upper_arm": (0.80, 0.80), "DEF-forearm": (0.86, 0.86, 0.80), "DEF-shoulder": (0.86, 0.86),
    "DEF-spine.003": (0.90, 0.93), "DEF-spine.002": (0.92, 0.95), "DEF-spine.001": (0.96, 0.97),
    "DEF-thigh": (0.95, 0.95), "DEF-shin": (0.95, 0.95), "DEF-neck": (0.92, 0.92),
}


def slim(rig, co, W):
    out = np.zeros_like(co)
    for bi, bn in enumerate(rig.names):
        idx = np.where(W[:, bi] > 0)[0]
        if not len(idx):
            continue
        key = bn.rsplit(".", 1)[0] if bn.endswith((".L", ".R")) else bn
        s = SLIM.get(key, (1.0, 1.0))
        p0 = rig.head(bn)
        d = rig.tail(bn) - p0
        L = np.linalg.norm(d)
        d /= L
        t = np.clip((co[idx] - p0) @ d, 0, L)
        c = p0 + np.outer(t, d)
        q = co[idx] - c
        if len(s) > 2:
            q *= (s[2] + (s[0] - s[2]) * (t / L))[:, None]
        elif s[0] == s[1]:
            q *= s[0]
        else:
            ay = np.array([0, 1.0, 0]) - d[1] * d
            ay /= np.linalg.norm(ay)
            qy = q @ ay
            q = (q - np.outer(qy, ay)) * s[0] + np.outer(qy, ay) * s[1]
        out[idx] += W[idx, bi, None] * (c + q)
    return out


def fuse(rig, prepared):
    """one continuous, slimmed body with the mannequin's weights"""
    A, bg = mesh_to_sdf(mesh_co(prepared.data), mesh_tris(prepared.data))
    pts, quads = sdf_to_mesh(A, bg)
    me = build_mesh("Fused", pts, quads)
    keep_largest_component(me)
    o = link("Fused", me)
    transfer_groups(prepared, o)
    W = vertex_weights(o, rig.names)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
    set_co(me, slim(rig, mesh_co(me), W))
    log("fused body", len(me.vertices), "verts")
    return o


class Sculpt:
    """the character as one SDF grid, plus a phi field per material region"""

    def __init__(self, body):
        self.A, self.bg = mesh_to_sdf(mesh_co(body.data), mesh_tris(body.data))
        self.phi = {}
        self.cut_extra = {}

    def add_phi(self, label, entry):
        self.phi.setdefault(label, []).append(entry)

    def union(self, sl, d, label):
        a = self.A[sl]
        self.add_phi(label, (sl, (d - a).astype(np.float32)))
        self.A[sl] = np.minimum(a, d)

    def phi_at(self, label, pts):
        v = np.full(len(pts), np.inf)
        for ent in self.phi.get(label, []):
            v = np.minimum(v, ent(pts) if callable(ent) else sample_box(ent[1], ent[0], pts))
        return v


def sculpt(body):
    S = Sculpt(body)
    A = S.A
    # smooth the mannequin's facets (not the fingers), the arms a bit more
    sl, X, Y, Z = sub((-0.74, -0.33, -0.03), (0.74, 0.25, 1.87))
    m = (1 - sstep(0.66, 0.73, np.abs(X))).astype(np.float32)
    A[sl] = A[sl] * (1 - m) + blur(A[sl], 2, 2) * m
    sl, X, Y, Z = sub((-0.70, -0.05, 1.30), (0.70, 0.20, 1.56))
    m = (sstep(0.20, 0.26, np.abs(X)) * (1 - sstep(0.62, 0.70, np.abs(X)))).astype(np.float32)
    A[sl] = A[sl] * (1 - m) + blur(A[sl], 2, 3) * m

    # the new head and neck replace the mannequin's egg
    hsl, X, Y, Z = sub((-0.13, -0.17, 1.42), (0.13, 0.16, 1.86))
    HN, hphis = build_head(X, Y, Z)
    for L, ph in hphis.items():
        S.add_phi(L, (hsl, ph.astype(np.float32)))
    S.add_phi(LIPS, lips_phi)
    S.add_phi(MOUTH, mouth_phi)
    S.cut_extra[MOUTH] = [mouth_centre]
    A[hsl] = smin(smax(A[hsl], Z - 1.535, 0.02), HN, 0.035)
    del HN

    # the mannequin's sculpted chest, abs and pelvis ledges go (all under the shirt)
    sl, X, Y, Z = sub((-0.26, -0.21, 0.85), (0.26, 0.23, 1.50))
    w = (sstep(0.88, 0.95, Z) * (1 - sstep(1.40, 1.48, Z)) * (1 - sstep(0.17, 0.24, np.abs(X)))).astype(np.float32)
    A[sl] = A[sl] * (1 - w) + blur(A[sl], 5, 2) * w
    body_sdf = A.copy()        # garments are offsets of the body without the other garments
    log("body and head")

    # ---- T-shirt
    sl, X, Y, Z = sub((-0.42, -0.21, 0.88), (0.42, 0.23, 1.62))
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
    off = 0.012 + 0.003 * sstep(1.05, 0.96, Z) + 0.003 * sstep(0.24, 0.345, AX) * (AX > 0.19)
    sh = np.minimum(sh - off, a - 0.004)
    ycn = 0.020 - 0.10 * (Z - 1.46)                         # neck axis, leaning forward
    rxy = np.sqrt((X / 1.06) ** 2 + (Y - ycn) ** 2)
    fr = np.clip(-(Y - ycn) / np.maximum(rxy, 1e-6), 0, 1)
    R = 0.086 + 0.014 * fr ** 2                             # crew neck, lower in front
    sh = smax(sh, np.minimum(R - rxy, Z - 1.43), 0.003)
    sh = sh - 0.0018 * sstep(R + 0.016, R + 0.004, rxy)      # collar rib
    sh = smax(sh, Z - 1.545, 0.003)
    sh = smax(sh, 0.955 - Z, 0.004)                          # hem
    sh = smax(sh, AX - 0.345, 0.004)                         # sleeves end above the elbow
    S.union(sl, sh, SHIRT)
    del sh, hang, shifted
    log("shirt")

    # ---- jeans
    sl, X, Y, Z = sub((-0.26, -0.18, -0.01), (0.26, 0.23, 1.12))
    AX = np.abs(X)
    a = body_sdf[sl]
    jn = np.minimum(blur(a, 3, 2) - 0.0065, a - 0.004)
    fly = smax(sd_ellipsoid(X, Y, Z, (0, -0.035, 0.905), (0.100, 0.050, 0.075)), 0.855 - Z, 0.01)
    jn = smin(jn, fly - 0.0065, 0.02)                       # a smooth front over the mannequin's pouch
    tube = sd_capsule(AX, Y, Z, (0.093, 0.004, 0.52), (0.093, 0.022, 0.06), 0.063, 0.060)
    jn = np.where(Z < 0.62, smin(jn, tube, 0.05), jn)        # straight legs from the knee down
    jn = smax(jn, 0.074 - 0.14 * (Y - 0.03) - Z, 0.004)      # hem, lower at the heel
    jn = smax(jn, Z - 1.08, 0.004)                           # waist (under the shirt)
    S.union(sl, jn, JEANS)
    del jn
    log("jeans")

    # ---- sneakers
    sl, X, Y, Z = sub((-0.21, -0.26, -0.01), (0.21, 0.14, 0.17))
    AX = np.abs(X)
    fx = AX - 0.096
    a = body_sdf[sl]
    k0 = int(round((0.004 - GRID_O[2]) / VOX)) - sl[2].start
    k1 = int(round((0.075 - GRID_O[2]) / VOX)) - sl[2].start
    outline = a[:, :, k0:k1].min(axis=2, keepdims=True)     # the foot seen from above
    outline = blur(np.repeat(outline, 3, axis=2), 2, 2)[:, :, 1:2] - 0.005
    zz = Z - 0.014 * np.clip((-Y - 0.12) / 0.09, 0, 1) ** 2  # toe spring
    hs = 0.030 - 0.007 * np.clip((0.05 - Y) / 0.2, 0, 1)    # sole height
    sole = smax(outline, np.abs(zz - hs / 2) - hs / 2, 0.005)
    toebox = sd_ellipsoid(fx, Y, zz, (-0.002, -0.130, 0.030), (0.047, 0.080, 0.034))
    vamp = sd_capsule(fx, Y, Z, (-0.002, -0.090, 0.048), (0.0, 0.000, 0.080), 0.039)
    heel = sd_capsule(fx / 0.86, Y, Z, (0.0, 0.050, 0.035), (0.0, 0.042, 0.095), 0.041, 0.036)
    upper = smin(smin(toebox, vamp, 0.03), heel, 0.03)
    upper = smax(upper, outline + 0.0015, 0.005)
    foot = smax(smax(a - 0.004, Z - 0.10, 0.004), hs + 0.006 - Z, 0.003)
    upper = smin(upper, foot, 0.008)
    upper = smax(upper, hs + 0.001 - Z, 0.002)              # the upper sits on the sole
    upper = smin(upper, sd_capsule(fx, Y, Z, (0.0, -0.045, 0.070), (0.0, 0.0, 0.112), 0.030), 0.012)  # tongue
    upper = smax(upper, Z - (0.106 + 0.012 * sstep(0.03, -0.03, Y)), 0.004)
    S.union(sl, np.minimum(upper, sole), SHOE)
    S.add_phi(SOLE, (sl, (sole - upper).astype(np.float32)))

    def on_upper(p, d):          # region d (< 0 inside) limited to the visible shoe upper
        return np.maximum(d, np.maximum(S.phi_at(SHOE, p), -S.phi_at(SOLE, p)))

    def laces(p):                # lace panel down the top of the foot
        fx = np.abs(p[:, 0]) - 0.096
        d = np.maximum(np.maximum(np.abs(fx + 0.002) - 0.015, -0.112 - p[:, 1]), np.maximum(p[:, 1] + 0.02, 0.055 - p[:, 2]))
        return on_upper(p, d)

    def heel_tab(p):             # a darker tab up the back of the heel
        fx = np.abs(p[:, 0]) - 0.096
        d = np.maximum(np.maximum(np.abs(fx) - 0.016, 0.07 - p[:, 1]), np.maximum(0.034 - p[:, 2], p[:, 2] - 0.105))
        return on_upper(p, d)
    S.add_phi(LACES, laces)
    S.add_phi(HEELTAB, heel_tab)
    log("shoes")
    del body_sdf
    return S


def decimate(obj, tris, keep=None):
    """mirror-symmetric quadric collapse to about `tris` triangles; vertices with keep=1 stay"""
    dec = obj.modifiers.new("Decimate", 'DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = min(1.0, tris / sum(len(p.vertices) - 2 for p in obj.data.polygons))
    dec.use_symmetry = True
    dec.symmetry_axis = 'X'
    dec.use_collapse_triangulate = True
    if keep is not None:
        vg = obj.vertex_groups.new(name="dec_keep")
        vg.add(np.where(keep > 0.5)[0].tolist(), 1.0, 'REPLACE')
        dec.vertex_group = vg.name
        dec.invert_vertex_group = True
        dec.vertex_group_factor = 1.0
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=dec.name)
    if keep is not None:
        obj.vertex_groups.remove(obj.vertex_groups["dec_keep"])


def iso_cut(bm, phi):
    """split the mesh along phi = 0 (phi linear along each edge)"""
    bm.verts.ensure_lookup_table()
    ph = phi(np.array([v.co[:] for v in bm.verts]))
    ph = np.where(np.isfinite(ph), ph, 1.0)
    ph = np.where(np.abs(ph) < 1e-6, 1e-6, ph)
    val = dict(zip(bm.verts, ph))
    on = set()
    for e in [e for e in bm.edges if (val[e.verts[0]] < 0) != (val[e.verts[1]] < 0)]:
        v0, v1 = e.verts
        _, nv = bmesh.utils.edge_split(e, v0, val[v0] / (val[v0] - val[v1]))
        val[nv] = 0.0
        on.add(nv)
    for f in list(bm.faces):
        vs = [v for v in f.verts if v in on]
        if len(vs) == 2 and not bm.edges.get(vs):
            try:
                bmesh.utils.face_split(f, vs[0], vs[1])
            except ValueError:
                pass


def surface(S):
    """volume -> decimated, region-cut mesh; returns (object, face labels)"""
    pts, quads = sdf_to_mesh(S.A, S.bg)
    S.A = None
    me = build_mesh("Character", pts, quads)
    keep_largest_component(me)
    o = link("Character", me)
    log("surface", len(me.polygons), "quads")
    decimate(o, TARGET_TRIS * FACE_PASS)
    co = mesh_co(o.data)
    face = (co[:, 2] > 1.555) & (co[:, 2] < 1.73) & (co[:, 1] < -0.02) & (np.abs(co[:, 0]) < 0.078)
    decimate(o, TARGET_TRIS, face.astype(float))
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for L in LABEL_ORDER:
        for extra in S.cut_extra.get(L, []):
            iso_cut(bm, extra)
        iso_cut(bm, lambda p, L=L: S.phi_at(L, p))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    bm.to_mesh(me)
    bm.free()
    # each face takes the region of the mean phi of its corners (consistent with the cuts)
    vco = mesh_co(me)
    fv = [list(p.vertices) for p in me.polygons]
    flab = np.full(len(fv), SKIN, np.int32)
    for L in LABEL_ORDER:
        ph = S.phi_at(L, vco)
        ph = np.where(np.isfinite(ph), ph, 1.0)
        flab[np.array([ph[v].mean() for v in fv]) < 0] = L
    log("regions", dict(zip(LABEL_NAMES, np.bincount(flab, minlength=len(LABEL_NAMES)).tolist())))
    return o, flab


def palette():
    cells = list(PALETTE)
    size, cell = 16, 4
    n = size // cell
    img = bpy.data.images.new("Char_Palette", size, size, alpha=False)
    px = np.ones((size, size, 4), np.float32)
    for i, nm in enumerate(cells):
        cx, cy = i % n, i // n
        px[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell, :3] = PALETTE[nm]
    img.pixels = px.ravel()
    img.pack()

    def uv(nm):
        i = cells.index(nm)
        return ((i % n + 0.5) / n, (i // n + 0.5) / n)
    return img, uv


def make_materials(img):
    mats = []
    for name, rough in MATERIALS:
        m = bpy.data.materials.new(name)
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        tx.interpolation = 'Closest'
        nt.links.new(tx.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = 0.0
        # A closed surface: single-sided (glTF doubleSided false), so the
        # game draws no back faces.
        m.use_backface_culling = True
        mats.append(m)
    return mats


def shade(o, flab, mats, cell_uv):
    me = o.data
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", np.array([LAB_MAT[l] for l in flab], np.int32))
    uvl = me.uv_layers.new(name="UVMap")
    luv = np.zeros((len(me.loops), 2), np.float32)
    for p, l in zip(me.polygons, flab):
        luv[p.loop_start:p.loop_start + p.loop_total] = cell_uv(LAB_CELL[l])
    uvl.data.foreach_set("uv", luv.ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    # hard edges where regions fold (hems, collar, hairline, sole) and on any very sharp fold
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


def make_eyes(mat, cell_uv):
    """both eyeballs as one mesh: sclera / iris / pupil cells of the skin material, all on the head bone.
    Built from explicit lists (bmesh's sphere primitive isn't ordered the same way twice)."""
    SEG, RINGS = 16, 10
    verts, tris, cells = [], [], []
    for sx in (1, -1):
        c = np.array([sx * EYE_C[0], EYE_C[1], EYE_C[2]])
        base = len(verts)
        # the pole axis points forward (-Y): ring i at angle th from the front
        verts.append(c + (0, -EYE_R, 0))
        for i in range(1, RINGS):
            th = math.pi * i / RINGS
            for j in range(SEG):
                ph = 2 * math.pi * j / SEG
                verts.append(c + EYE_R * np.array([math.sin(th) * math.cos(ph), -math.cos(th), math.sin(th) * math.sin(ph)]))
        verts.append(c + (0, EYE_R, 0))
        ring = lambda i, j: base + 1 + (i - 1) * SEG + j % SEG
        for i in range(1, RINGS + 1):
            for j in range(SEG):
                if i == 1:
                    t = [(base, ring(1, j + 1), ring(1, j))]
                elif i == RINGS:
                    t = [(ring(RINGS - 1, j), ring(RINGS - 1, j + 1), base + 1 + (RINGS - 1) * SEG)]
                else:
                    a, b, cc, d = ring(i - 1, j), ring(i - 1, j + 1), ring(i, j + 1), ring(i, j)
                    t = [(a, b, cc), (a, cc, d)]
                ang = 180.0 * (i - 0.5) / RINGS
                nm = "pupil" if ang < 15 else ("iris" if ang < 40 else "sclera")
                for tri in t:
                    tris.append(tri[::-1])          # counter-clockwise seen from outside
                    cells.append(nm)
    me = bpy.data.meshes.new("Eyes")
    me.from_pydata([tuple(v) for v in verts], [], tris)
    me.materials.append(mat)
    uv = me.uv_layers.new(name="UVMap")
    for p, nm in zip(me.polygons, cells):
        for li in p.loop_indices:
            uv.data[li].uv = cell_uv(nm)
        p.use_smooth = True
    o = link("Eyes", me)
    o.vertex_groups.new(name="DEF-head").add(range(len(me.vertices)), 1.0, 'REPLACE')
    return o


def skin(rig, o, flab, fused, eyes):
    """final weights: transferred, shirt rules, <= 4 influences; then the fingers un-spread"""
    shirt_v = np.zeros(len(o.data.vertices), bool)
    for p, l in zip(o.data.polygons, flab):
        if l == SHIRT:
            shirt_v[list(p.vertices)] = True
    transfer_groups(fused, o)
    n_body = len(o.data.vertices)
    with bpy.context.temp_override(object=o, active_object=o, selected_editable_objects=[o, eyes]):
        bpy.ops.object.join()
    me = o.data
    W = vertex_weights(o, rig.names)
    vs = np.zeros(len(W), bool)
    vs[:n_body] = shirt_v
    for side in ("L", "R"):              # the shirt rides on the hips (no hem spikes over a lifted knee)
        W[vs, rig.index["DEF-thigh." + side]] = 0.0
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    ed = mesh_edges(me)
    deg = np.maximum(np.bincount(ed[:, 0], minlength=len(W)) + np.bincount(ed[:, 1], minlength=len(W)), 1)
    mask = vs.astype(float)[:, None]
    for _ in range(4):                   # soften the shirt's weights a little
        S = np.zeros_like(W)
        np.add.at(S, ed[:, 0], W[ed[:, 1]])
        np.add.at(S, ed[:, 1], W[ed[:, 0]])
        W = W * (1 - 0.5 * mask) + 0.5 * mask * S / deg[:, None]
    order = np.argsort(-W, axis=1, kind="stable")
    Wl = np.zeros_like(W)
    rows = np.arange(len(W))[:, None]
    Wl[rows, order[:, :4]] = W[rows, order[:, :4]]
    Wl[Wl < 0.01] = 0
    Wl /= np.maximum(Wl.sum(1, keepdims=True), 1e-9)
    co = mesh_co(me)
    for side, sg in (("L", 1), ("R", -1)):
        for f in FINGERS:
            names = finger_bones(f, side)
            wf = Wl[:, [rig.index[n] for n in names]].sum(1)
            idx = np.where(wf > 0)[0]
            rot_z(co, idx, rig.head(names[0]), -math.radians(SPREAD[f]) * sg, wf[idx])
    set_co(me, co)
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    for bi, bn in enumerate(rig.names):
        idx = np.where(Wl[:, bi] > 0)[0]
        if not len(idx):
            continue
        g = o.vertex_groups.new(name=bn)
        q = np.round(Wl[idx, bi] * 1000).astype(int)
        for qv in np.unique(q):
            g.add(idx[q == qv].tolist(), qv / 1000.0, 'REPLACE')


def main():
    out = parse_args()
    src_glb = ensure_source()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src_glb)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name.startswith("Icosphere"):     # importer's bone-shape helper
            bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    src = bpy.data.objects["Mannequin"]
    rig = Rig(arm)

    prepared = prepare_source(rig, src)
    fused = fuse(rig, prepared)
    S = sculpt(fused)
    o, flab = surface(S)
    del S
    img, cell_uv = palette()
    mats = make_materials(img)
    shade(o, flab, mats, cell_uv)
    eyes = make_eyes(mats[0], cell_uv)
    skin(rig, o, flab, fused, eyes)
    for ob in (src, prepared, fused):
        bpy.data.objects.remove(ob, do_unlink=True)

    for ac in list(bpy.data.actions):
        if ac.name not in KEEP_CLIPS:
            bpy.data.actions.remove(ac)
    missing = [c for c in KEEP_CLIPS if c not in bpy.data.actions]
    if missing:
        fail("clips missing from the source: %s" % missing)
    for ac in bpy.data.actions:
        ac.use_fake_user = True
    o.parent = arm
    o.modifiers.new("Armature", 'ARMATURE').object = arm
    arm.animation_data_create()
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.scene.render.fps = 24

    me = o.data
    co = mesh_co(me)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    log("mesh: %d tris, %d verts, height %.3f m, %d bones, %d clips"
        % (tris, len(me.vertices), co[:, 2].max(), len(arm.data.bones), len(bpy.data.actions)))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True,
                              export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True,
                              export_yup=True, export_apply=False, export_materials='EXPORT',
                              export_image_format='AUTO', export_extras=False)
    log("wrote", out, "(%d KB)" % (os.path.getsize(out) // 1024))


main()
