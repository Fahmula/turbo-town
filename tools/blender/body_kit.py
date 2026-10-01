"""Smooth, dent-friendly vehicle bodies (ART_BIBLE.md §12-14 and §24).

A body is a loft: cross-sections at stations along the vehicle, front to
back. Each section is a list of right-half points (x, z) from the bottom
centre, round the side, to the top centre; the left half is the mirror. The
result is all quads with evenly spaced vertices, so the game's dents
(VehicleDamage) bend panels smoothly. Materials are picked per face from the
station and the section segment, so windows, pillars, panel gaps and the
bumpers are just regions of the same grid. Lights, grilles and handles are
small patches projected onto the finished shell.

Blender is Z-up; glTF converts to Godot's Y-up. Front = Blender +Y
(Godot -Z), right = +X. Not meant to be run directly; see make_car.py.
"""
import math
import os

import bmesh
import bpy
import mathutils
from mathutils.bvhtree import BVHTree

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models")


# --------------------------------------------------------------- curves ---

def curve(points):
    """Smooth function through (t, value) points, monotone between them
    (no overshoot), flat beyond the ends. Fritsch-Carlson cubic."""
    pts = sorted(points)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    n = len(pts)
    if n == 1:
        return lambda t: ys[0]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0.0:
            m[i] = 0.0
        else:
            w1 = 2 * (xs[i + 1] - xs[i]) + (xs[i] - xs[i - 1])
            w2 = (xs[i + 1] - xs[i]) + 2 * (xs[i] - xs[i - 1])
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def f(t):
        if t <= xs[0]:
            return ys[0]
        if t >= xs[-1]:
            return ys[-1]
        i = 0
        while t > xs[i + 1]:
            i += 1
        h = xs[i + 1] - xs[i]
        s = (t - xs[i]) / h
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1
        h10 = s ** 3 - 2 * s ** 2 + s
        h01 = -2 * s ** 3 + 3 * s ** 2
        h11 = s ** 3 - s ** 2
        return h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]
    return f


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def stations(y_front, y_back, step, keep=(), refine=()):
    """Station positions from front to back: about `step` apart, plus every
    value in `keep` (exact feature lines) and extra density inside `refine`
    ranges given as (y0, y1, step)."""
    ys = set()
    n = max(2, int(round((y_front - y_back) / step)) + 1)
    for i in range(n):
        ys.add(round(lerp(y_front, y_back, i / (n - 1)), 5))
    for (a, b, s) in refine:
        lo, hi = min(a, b), max(a, b)
        k = max(2, int(round((hi - lo) / s)) + 1)
        for i in range(k):
            ys.add(round(lerp(lo, hi, i / (k - 1)), 5))
    for y in keep:
        ys.add(round(y, 5))
    kept = {round(y, 5) for y in keep}
    clean = []
    for y in sorted(ys, reverse=True):
        if clean and abs(clean[-1] - y) < 0.004:
            if y in kept and clean[-1] not in kept:
                clean[-1] = y          # a kept feature line wins
            elif not (y in kept and clean[-1] in kept):
                continue
        clean.append(y)
    return clean


# ------------------------------------------------------------ materials ---

def srgb(c):
    """Colour picks are sRGB; Blender colour inputs are linear."""
    return tuple(pow(x, 2.2) for x in c)


def material(name, color, rough=0.5, metal=0.0, emission=None, strength=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    if not mat.node_tree:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[key].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
        else:
            mat.blend_method = "BLEND"
    mat.diffuse_color = (*srgb(color), alpha)
    return mat


def vehicle_materials(paint=(0.784, 0.137, 0.106)):
    """The material set every new-style body uses. Names are the game's
    contract (ART_BIBLE.md §13): Paint, Glass, Headlight, TailLight and
    ReverseLight are looked up by code."""
    return {
        "Paint": material("Paint", paint, rough=0.32),
        "Glass": material("Glass", (0.118, 0.157, 0.2), rough=0.05, alpha=0.72),
        "Trim": material("Trim", (0.133, 0.137, 0.149), rough=0.6),
        "Chrome": material("Chrome", (0.85, 0.86, 0.87), rough=0.12, metal=1.0),
        "Headlight": material("Headlight", (1.0, 0.96, 0.88), rough=0.1, emission=(1.0, 0.95, 0.85), strength=2.0),
        "TailLight": material("TailLight", (0.7, 0.05, 0.04), rough=0.15, emission=(1.0, 0.05, 0.02), strength=1.0),
        "ReverseLight": material("ReverseLight", (0.95, 0.95, 0.95), rough=0.15),
        "Interior": material("Interior", (0.17, 0.17, 0.18), rough=0.85),
    }


# ----------------------------------------------------------------- mesh ---

class Part:
    """A bmesh being built, with a material slot list."""

    def __init__(self, name, mats):
        self.name = name
        self.bm = bmesh.new()
        self.mats = mats          # list of bpy materials (slot order)

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def to_object(self, smooth_angle=None):
        bm = self.bm
        # Winding is authored (outward, interior faces inward on purpose),
        # so normals are not recalculated here.
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        for f in bm.faces:
            f.smooth = True
        if smooth_angle is not None:
            for e in bm.edges:
                if e.is_manifold and e.calc_face_angle(0.0) > smooth_angle:
                    e.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def loft(part, ys, section_fn, material_fn):
    """Builds the mirrored loft into `part`. `section_fn(i, y)` returns the
    right-half points; `material_fn(i, j, y0, y1)` the material of the face
    between stations i, i+1 and points j, j+1 (None = no face)."""
    bm = part.bm
    rings = []
    for i, y in enumerate(ys):
        pts = section_fn(i, y)
        right = [bm.verts.new((x, y, z)) for (x, z) in pts]
        left = [right[0]] + [bm.verts.new((-x, y, z)) for (x, z) in pts[1:-1]] + [right[-1]]
        rings.append((right, left))
    count = len(rings[0][0])
    for i in range(len(ys) - 1):
        r0, l0 = rings[i]
        r1, l1 = rings[i + 1]
        for j in range(count - 1):
            mat = material_fn(i, j, ys[i], ys[i + 1])
            if mat is None:
                continue
            idx = part.slot(mat)
            # Stations run front to back and points bottom to top, so this
            # order faces outward on the right; the mirror flips it.
            for (a0, a1, b0, b1, right) in ((r0[j], r0[j + 1], r1[j], r1[j + 1], True),
                                           (l0[j], l0[j + 1], l1[j], l1[j + 1], False)):
                quad = [a0, a1, b1, b0] if right else [a0, b0, b1, a1]
                if len(set(quad)) < 3:
                    continue
                try:
                    f = bm.faces.new(list(dict.fromkeys(quad)))
                except ValueError:
                    continue
                f.material_index = idx
    return rings


def split_part(src, name, pick):
    """Moves the faces where `pick(face_centre)` is true into a new Part
    (same material slots)."""
    dst = Part(name, list(src.mats))
    bm = src.bm
    bm.verts.ensure_lookup_table()
    faces = [f for f in bm.faces if pick(f.calc_center_median())]
    vmap = {}
    for f in faces:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = dst.bm.verts.new(v.co)
            vs.append(vmap[v])
        nf = dst.bm.faces.new(vs)
        nf.material_index = f.material_index
    bmesh.ops.delete(bm, geom=faces, context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    return dst


def thicken(part, depth):
    """Gives an open shell some thickness inward so it's closed (detached
    parts tumble and show their back)."""
    bmesh.ops.solidify(part.bm, geom=part.bm.faces[:], thickness=depth)


def box(part, mat, center, size, bevel=0.0, rot=None, segments=2):
    """Axis-aligned (or rotated) box, optionally with rounded edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = mathutils.Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    m = mathutils.Matrix.Translation(center)
    if rot is not None:
        m = m @ mathutils.Euler(rot).to_matrix().to_4x4()
    bm.transform(m)
    _append(part, bm, mat)


def tube(part, mat, p0, p1, radius, segments=10):
    a = mathutils.Vector(p0)
    b = mathutils.Vector(p1)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=d.length)
    rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bm.transform(mathutils.Matrix.Translation((a + b) / 2) @ rot)
    _append(part, bm, mat)


def spoke(part, mat, end0, end1, depth):
    """A flat bar on a wheel face from end0 to end1, each (x, r, angle,
    half_width): width runs round the wheel, `depth` along the axle."""
    bm = bmesh.new()
    vs = []
    for (x, r, a, hw) in (end0, end1):
        radial = mathutils.Vector((0, math.cos(a), math.sin(a)))
        tangent = mathutils.Vector((0, -math.sin(a), math.cos(a)))
        c = mathutils.Vector((x, 0, 0)) + radial * r
        for dx in (0.0, -depth):
            for sgn in (-1, 1):
                vs.append(bm.verts.new(c + tangent * hw * sgn + mathutils.Vector((dx, 0, 0))))
    # vs: end0 [front-, front+, back-, back+], end1 same.
    q = [(0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5), (0, 2, 3, 1), (4, 5, 7, 6)]
    for f in q:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _append(part, bm, mat)


def lathe(part, mat, profile, segments, x0=0.0, loop=False):
    """Revolves a profile of (x, r) points around the X axis (wheels). Go
    round the profile counter-clockwise in (x, r) (inner side up, across the
    top, down the outer side) so faces point outward. `loop` joins the last
    point back to the first (a solid ring)."""
    bm = bmesh.new()
    rings = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((x0 + x, r * ca, r * sa)) for (x, r) in profile])
    for k in range(segments):
        r0 = rings[k]
        r1 = rings[(k + 1) % segments]
        n = len(profile) if loop else len(profile) - 1
        for j in range(n):
            j1 = (j + 1) % len(profile)
            quad = [r0[j], r1[j], r1[j1], r0[j1]]
            if len({v.co.to_tuple(6) for v in quad}) >= 3:
                bm.faces.new(quad)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    _append(part, bm, mat)


def _append(part, bm, mat):
    idx = part.slot(mat)
    vmap = {}
    for v in bm.verts:
        vmap[v] = part.bm.verts.new(v.co)
    for f in bm.faces:
        nf = part.bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = idx
        nf.smooth = f.smooth
    bm.free()


# ---------------------------------------------------------- projection ---

class Surface:
    """Ray-casts against a finished shell to place conforming patches."""

    def __init__(self, parts):
        bm = bmesh.new()
        for p in parts:
            tmp = p.bm.copy()
            vmap = {v: bm.verts.new(v.co) for v in tmp.verts}
            for f in tmp.faces:
                bm.faces.new([vmap[v] for v in f.verts])
            tmp.free()
        bm.normal_update()
        self.bm = bm
        self.tree = BVHTree.FromBMesh(bm)

    def hit(self, origin, direction):
        loc, nrm, _i, _d = self.tree.ray_cast(mathutils.Vector(origin), mathutils.Vector(direction).normalized())
        return loc, nrm


def patch(surface, part, mat, outline, center, direction, up, lift=0.004, grid=4):
    """Projects a flat shape onto the shell along `direction`. `outline(u, v)`
    maps the unit square to local (s, t) metres in the projection plane
    through `center` (s along `up` x `direction`, t along `up`). Patches that
    miss the shell are skipped."""
    d = mathutils.Vector(direction).normalized()
    upv = mathutils.Vector(up)
    upv = (upv - d * upv.dot(d)).normalized()
    side = upv.cross(d).normalized()
    c = mathutils.Vector(center)
    bm = bmesh.new()
    rows = []
    for a in range(grid + 1):
        row = []
        for b in range(grid + 1):
            s, t = outline(a / grid, b / grid)
            p = c + side * s + upv * t
            loc, nrm = surface.hit(p - d * 2.0, d)
            if loc is None:
                bm.free()
                return False
            row.append(bm.verts.new(loc + nrm * lift))
        rows.append(row)
    for a in range(grid):
        for b in range(grid):
            bm.faces.new([rows[a][b], rows[a + 1][b], rows[a + 1][b + 1], rows[a][b + 1]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Face the patch outward like the surface under it.
    centre_loc, centre_n = surface.hit(c - d * 2.0, d)
    if centre_n is not None and bm.faces and bm.faces[0].normal.dot(centre_n) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    _append(part, bm, mat)
    return True


def rect(w, h, round_frac=0.0):
    """Outline helper: a w x h rectangle (optionally with a rounded-ish
    taper at the ends), centred on the patch centre."""
    def f(u, v):
        s = (u - 0.5) * w
        t = (v - 0.5) * h
        if round_frac > 0:
            e = abs(u - 0.5) * 2
            t *= 1.0 - round_frac * e ** 4
        return s, t
    return f


def ellipse(w, h):
    def f(u, v):
        a = (u - 0.5) * 2
        b = (v - 0.5) * 2
        k = max(abs(a), abs(b))
        if k < 1e-6:
            return 0.0, 0.0
        ang = math.atan2(b, a)
        return math.cos(ang) * k * w * 0.5, math.sin(ang) * k * h * 0.5
    return f


# --------------------------------------------------------------- export ---

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def weighted_normals(obj):
    m = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
    m.keep_sharp = True
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=m.name)
    obj.select_set(False)


def export(objs, filename):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    path = os.path.abspath(os.path.join(OUT_DIR, filename))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    total = sum(len(o.data.vertices) for o in objs)
    print("exported", path, "objects", [o.name for o in objs], "blender verts", total)
