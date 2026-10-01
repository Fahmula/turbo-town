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


def vehicle_materials(paint=(0.784, 0.137, 0.106), glass_alpha=0.72):
    """The material set every new-style body uses. Names are the game's
    contract (ART_BIBLE.md §13): Paint, Glass, Headlight, TailLight and
    ReverseLight are looked up by code. `glass_alpha` 1.0 = opaque glass for
    vehicles with no interior (it still cracks: it's still "Glass")."""
    return {
        "Paint": material("Paint", paint, rough=0.32),
        "Glass": material("Glass", (0.118, 0.157, 0.2) if glass_alpha < 1.0 else (0.09, 0.115, 0.14),
                          rough=0.05, alpha=glass_alpha),
        "Trim": material("Trim", (0.133, 0.137, 0.149), rough=0.6),
        "Chrome": material("Chrome", (0.85, 0.86, 0.87), rough=0.12, metal=1.0),
        "Headlight": material("Headlight", (1.0, 0.96, 0.88), rough=0.1, emission=(1.0, 0.95, 0.85), strength=2.0),
        "TailLight": material("TailLight", (0.7, 0.05, 0.04), rough=0.15, emission=(1.0, 0.05, 0.02), strength=1.0),
        "ReverseLight": material("ReverseLight", (0.95, 0.95, 0.95), rough=0.15),
        "Interior": material("Interior", (0.17, 0.17, 0.18), rough=0.85),
        # Opaque dark glass for windows painted onto the body (rear doors,
        # no interior behind them). Not "Glass", so it never cracks.
        "GlassDark": material("GlassDark", (0.09, 0.115, 0.14), rough=0.06),
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
    through `center` (s along `up` x `direction`, t along `up`). `grid` is
    the subdivision (an int, or (across, along) for long thin strips).
    Patches that miss the shell are skipped."""
    gu, gv = (grid, grid) if isinstance(grid, int) else grid
    d = mathutils.Vector(direction).normalized()
    upv = mathutils.Vector(up)
    upv = (upv - d * upv.dot(d)).normalized()
    side = upv.cross(d).normalized()
    c = mathutils.Vector(center)
    bm = bmesh.new()
    rows = []
    for a in range(gu + 1):
        row = []
        for b in range(gv + 1):
            s, t = outline(a / gu, b / gv)
            p = c + side * s + upv * t
            loc, nrm = surface.hit(p - d * 2.0, d)
            if loc is None:
                bm.free()
                return False
            if nrm.dot(d) > 0.0:
                nrm = -nrm          # hit a back face (e.g. a bumper's inner skin)
            row.append(bm.verts.new(loc + nrm * lift))
        rows.append(row)
    for a in range(gu):
        for b in range(gv):
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


# ------------------------------------------------------------- loft body ---

class BodySpec:
    """Everything that makes one vehicle's loft body. Set attributes, then
    build with LoftBody. Defaults are the sports car's. All positions are
    Blender metres (front = +Y, z = 0 at wheel-centre height)."""

    def __init__(self, **kw):
        self.y_nose, self.y_tail = 2.20, -2.20
        self.nose0, self.tail0 = 2.02, -2.06      # plan-view rounding starts
        self.nose_p, self.tail_p = 2.4, 3.0       # rounding shape (higher = squarer)
        self.floor = -0.24                        # underbody height
        self.axles = []                           # [(y, arch radius)]
        self.width = None                         # curve: half width at door middle
        self.shoulder = None                      # curve: belt / fender line
        self.crown = lambda y: 0.0                # curve: top centre above the edges
        self.roof_w = lambda y: 0.6               # curve: roof half width
        self.roof_edge = None                     # curve: cabin roof edge (side view)
        self.ws_base, self.roof_front, self.roof_rear, self.rw_base = 0.62, -0.02, -0.72, -1.58
        self.glass_top = 0.85                     # roof edge height where the cabin is "full"
        self.windows = []                         # [(y_front, y_back)] side glass
        self.pillar_mat = "Trim"                  # between windows
        self.door_lines = []                      # [(y0, y1)] thin dark gaps on the sides
        self.top_lines = []                       # [(y0, y1)] gaps across the top
        self.bumper_split = (1.80, -1.80)         # rows below `bumper_row` ahead/behind -> bumpers
        self.bumper_row = 4                       # section point at the bumper's top edge
        self.shoulder_inset = 0.04
        self.hood_edge_inset = 0.11
        self.bulge = 0.012
        self.rocker_mat = "Trim"
        self.frit = True                          # dark band round windscreen / rear window
        self.belt_molding = True
        self.station_step = 0.14
        self.arch_step = 0.09
        self.keep = []                            # extra station positions
        self.nose_samples = (0.3, 0.55, 0.72, 0.85, 0.93, 0.98, 1.0)
        self.tail_samples = (0.35, 0.6, 0.8, 0.92, 0.98, 1.0)
        self.side_mat = "Paint"
        self.section_override = None              # fn(body, y) -> points, for odd shapes
        self.material_override = None            # fn(body, j, y) -> key or "" (= default)
        for k, v in kw.items():
            setattr(self, k, v)


class LoftBody:
    """Builds a BodySpec into a shell with the standard 19-point section
    (see section()) and the material rules of ART_BIBLE.md §12-13."""

    def __init__(self, spec):
        self.s = spec

    # Plan-view rounding at the ends: 1 inside, falling to 0 at the tips.
    def wrap(self, y):
        s = self.s
        if y > s.nose0:
            t = (y - s.nose0) / (s.y_nose - s.nose0)
            return max(0.0, 1.0 - t ** s.nose_p) ** (1 / s.nose_p)
        if y < s.tail0:
            t = (s.tail0 - y) / (s.tail0 - s.y_tail)
            return max(0.0, 1.0 - t ** s.tail_p) ** (1 / s.tail_p)
        return 1.0

    def arch(self, y):
        for ay, r in self.s.axles:
            dy = y - ay
            if abs(dy) <= r + 1e-6:
                return math.sqrt(max(r * r - dy * dy, 0.0)), 1.0
        return self.s.floor, 0.0

    def has_cabin(self, y):
        return self.s.roof_edge is not None and self.s.rw_base < y < self.s.ws_base

    def region(self, y):
        s = self.s
        if s.roof_edge is None:
            return "hood"
        if y > s.ws_base:
            return "hood"
        if y > s.roof_front:
            return "ws"
        if y > s.roof_rear:
            return "roof"
        if y > s.rw_base:
            return "rw"
        return "deck"

    def section(self, _i, y):
        s = self.s
        if s.section_override:
            return s.section_override(self, y)
        yc = min(max(y, s.tail0), s.nose0)
        k = self.wrap(y)
        w = s.width(yc)
        z_sh = s.shoulder(y)
        z_re = z_sh + 0.004
        g = 0.0
        if self.has_cabin(y):
            z_re = max(z_re, s.roof_edge(y))
            g = smoothstep(0.0, 1.0, (z_re - z_sh) / (s.glass_top - z_sh))
        z_rc = z_re + s.crown(y)
        w_sh = w - s.shoulder_inset
        w_re = lerp(w_sh - s.hood_edge_inset, s.roof_w(y), g)
        band = lerp(0.008, 0.045, smoothstep(0.0, 0.12, g))
        zb, a = self.arch(y)
        off3 = lerp(0.035, 0.012, a)
        off4 = lerp(0.10, 0.03, a)
        p = [(0.0, zb), (w - 0.07, zb), (w - 0.012, zb + off3), (w - 0.002 + 0.006 * a, zb + off4)]
        z4 = zb + off4
        z7 = z_sh - 0.035
        p.append((w + s.bulge - 0.005, lerp(z4, z7, 0.33)))
        p.append((w + s.bulge, lerp(z4, z7, 0.70)))
        p.append((w_sh + 0.012, z7))
        p8 = (w_sh - 0.01, z_sh)
        p13 = (w_re, z_re)
        p.append(p8)
        lx, lz = p13[0] - p8[0], p13[1] - p8[1]
        ln = max(math.hypot(lx, lz), 1e-4)
        for f in (min(0.03 / ln, 0.2), 0.45, 0.75, 1.0 - min(band / ln, 0.4)):
            p.append((p8[0] + lx * f, p8[1] + lz * f))
        p.append(p13)
        u_band = min(band / max(w_re, 1e-3), 0.25)
        for u in (u_band, 0.3, 0.5, 0.7, 0.86, 1.0):
            x = w_re * (1.0 - u)
            z = z_re + (z_rc - z_re) * (1.0 - (1.0 - u) ** 2)
            p.append((x, z))
        return [(x * k, z) for (x, z) in p]

    def material_key(self, j, y):
        """Material name for the face at section segment j, station mid y."""
        s = self.s
        if s.material_override:
            key = s.material_override(self, j, y)
            if key:
                return key
        reg = self.region(y)
        cabin = reg in ("ws", "roof", "rw")
        in_window = any(within(y, w) for w in s.windows)
        glass_span = (s.windows[0][0], s.windows[-1][1]) if s.windows else None
        in_span = glass_span is not None and within(y, glass_span)
        if j == 0:
            return "Trim"                                   # underbody
        if j <= 2:
            return s.rocker_mat                             # sills / lower lips
        if j <= 6:
            if j >= 3 and any(within(y, d) for d in s.door_lines):
                return "Trim"
            return s.side_mat
        if j == 7:
            return "Trim" if (in_span and s.belt_molding) else s.side_mat
        if j <= 10:
            if in_window:
                return "Glass"
            return s.pillar_mat if in_span else s.side_mat
        if j <= 12:
            return "Paint" if cabin else "Trim"             # pillars / shut gaps
        if any(within(y, d) for d in s.top_lines):
            return "Trim"
        if reg in ("ws", "rw"):
            return "Trim" if (j == 13 and s.frit) else "Glass"
        return "Paint"

    def stations(self):
        s = self.s
        keep = [s.nose0, s.tail0, s.bumper_split[0], s.bumper_split[1]] + list(s.keep)
        if s.roof_edge is not None:
            keep += [s.ws_base, s.roof_front, s.roof_rear, s.rw_base]
        for w in s.windows:
            keep += list(w)
        for d in s.door_lines + s.top_lines:
            keep += list(d)
        refine = []
        for ay, r in s.axles:
            keep += [ay + r + 0.006, ay + r, ay - r, ay - r - 0.006]
            refine.append((ay + r, ay - r, s.arch_step))
        keep += [s.nose0 + t * (s.y_nose - s.nose0) for t in s.nose_samples]
        keep += [s.tail0 - t * (s.tail0 - s.y_tail) for t in s.tail_samples]
        keep = [y for y in keep if s.y_tail <= y <= s.y_nose]   # e.g. a roof that runs to the end
        return stations(s.y_nose, s.y_tail, s.station_step, keep=keep, refine=refine)

    def row_height(self, y, row=4):
        return self.section(0, y)[row][1]

    def build(self, m, name="Body", bumpers=True):
        """The shell plus (optionally) front and rear bumper parts, which are
        the rows below section point 4 beyond bumper_split, thickened."""
        ys = self.stations()
        shell = Part(name, [])
        loft(shell, ys, self.section, lambda _i, j, y0, y1: m[self.material_key(j, (y0 + y1) * 0.5)])
        front = rear = None
        if bumpers:
            fy, ry = self.s.bumper_split
            row = self.s.bumper_row
            front = split_part(shell, "FrontBumper", lambda c: c.y > fy and c.z < self.row_height(c.y, row) + 1e-4)
            rear = split_part(shell, "RearBumper", lambda c: c.y < ry and c.z < self.row_height(c.y, row) + 1e-4)
            front = front if front.bm.faces else None    # e.g. a cab with no rear bumper
            rear = rear if rear.bm.faces else None
            for part in (front, rear):
                if part:
                    thicken(part, 0.018)
        return shell, front, rear, ys

    def inner_cabin(self, shell, m, ys, y_front, y_back, every=2):
        """Dark inward-facing door cards, pillars and headliner, so the see-
        through glass doesn't show out through the far side."""
        inner = [y for y in ys if y_front > y > y_back][::every]

        def inner_section(i, y):
            pts = self.section(i, y)
            out = []
            for j, (x, z) in enumerate(pts):
                a = pts[max(j - 1, 0)]
                b = pts[min(j + 1, len(pts) - 1)]
                tx, tz = b[0] - a[0], b[1] - a[1]
                ln = max(math.hypot(tx, tz), 1e-5)
                nx, nz = tz / ln, -tx / ln
                out.append((max(x - nx * 0.018, 0.0), z - nz * 0.018))
            return out

        def inner_mat(_i, j, y0, y1):
            y = (y0 + y1) * 0.5
            if 3 <= j <= 6:
                return m["Interior"]
            if 11 <= j and self.region(y) == "roof":
                return m["Interior"]
            if j in (11, 12):
                return m["Interior"]
            return None
        tmp = Part("inner", list(shell.mats))
        loft(tmp, inner, inner_section, inner_mat)
        bmesh.ops.reverse_faces(tmp.bm, faces=tmp.bm.faces[:])
        merge(shell, tmp)


def within(y, rng):
    return min(rng) < y < max(rng)


def merge(dst, src):
    """Moves all of `src`'s geometry into `dst` (keeping materials)."""
    vmap = {v: dst.bm.verts.new(v.co) for v in src.bm.verts}
    for f in src.bm.faces:
        nf = dst.bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = dst.slot(src.mats[f.material_index])
        nf.smooth = f.smooth
    src.bm.free()


def torus(part, mat, center, ring_r, tube_r, seg=16, tseg=5, tilt=0.0, axis="X"):
    """A ring (steering wheels, tyres of toys...). Lies in the XZ plane,
    tilted about X by `tilt` radians."""
    bm = bmesh.new()
    rings = []
    for a in range(seg):
        ang = 2 * math.pi * a / seg
        ring = []
        for b in range(tseg):
            t = 2 * math.pi * b / tseg
            r = ring_r + tube_r * math.cos(t)
            ring.append(bm.verts.new((r * math.cos(ang), tube_r * math.sin(t), r * math.sin(ang))))
        rings.append(ring)
    for a in range(seg):
        r0, r1 = rings[a], rings[(a + 1) % seg]
        for b in range(tseg):
            bm.faces.new([r0[b], r1[b], r1[(b + 1) % tseg], r0[(b + 1) % tseg]])
    bm.transform(mathutils.Matrix.Translation(center) @ mathutils.Matrix.Rotation(tilt, 4, axis))
    _append(part, bm, mat)


def panel_box(part, mat, center, size, step=0.35, faces=("+x", "-x", "+y", "-y", "+z", "-z")):
    """A box whose faces are grids about `step` apart, so dents can bend its
    flat panels (a plain 8-vertex box can't dent). Faces point outward."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    bm = bmesh.new()

    def grid(origin, du, dv, nu, nv):
        rows = [[bm.verts.new(origin + du * (a / nu) + dv * (b / nv)) for b in range(nv + 1)] for a in range(nu + 1)]
        for a in range(nu):
            for b in range(nv):
                bm.faces.new([rows[a][b], rows[a + 1][b], rows[a + 1][b + 1], rows[a][b + 1]])

    V = mathutils.Vector
    n = lambda length: max(1, int(round(length / step)))  # noqa: E731
    specs = {
        "+x": (V((cx + hx, cy - hy, cz - hz)), V((0, 2 * hy, 0)), V((0, 0, 2 * hz))),
        "-x": (V((cx - hx, cy + hy, cz - hz)), V((0, -2 * hy, 0)), V((0, 0, 2 * hz))),
        "+y": (V((cx + hx, cy + hy, cz - hz)), V((-2 * hx, 0, 0)), V((0, 0, 2 * hz))),
        "-y": (V((cx - hx, cy - hy, cz - hz)), V((2 * hx, 0, 0)), V((0, 0, 2 * hz))),
        "+z": (V((cx - hx, cy - hy, cz + hz)), V((2 * hx, 0, 0)), V((0, 2 * hy, 0))),
        "-z": (V((cx - hx, cy + hy, cz - hz)), V((2 * hx, 0, 0)), V((0, -2 * hy, 0))),
    }
    for f in faces:
        o, du, dv = specs[f]
        grid(o, du, dv, n(du.length), n(dv.length))
    _append(part, bm, mat)
