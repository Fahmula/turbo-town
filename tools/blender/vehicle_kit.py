"""Shared helpers for the Blender vehicle generators (make_car.py,
make_traffic_vehicles.py). Not meant to be run directly.

Conventions (Blender is Z-up; glTF export converts to Godot's Y-up):
  * Vehicle front points to Blender +Y  -> Godot -Z (forward).
  * Origin is at wheel-centre height, midway between the axles.
Material names matter to the game: "Paint" is recoloured, "TailLight" and
"ReverseLight" light up, the rest are fixed colours.
"""
import math
import os
import bpy
import bmesh

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, rough=0.5, metal=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    if not mat.node_tree:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[key].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = (*color, 1.0)
    return mat


def srgb(c):
    """Blender colour inputs are linear; convert from sRGB-ish picks."""
    return tuple(pow(x, 2.2) for x in c)


def new_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def activate(obj):
    for o in bpy.data.objects:
        if o is not None and o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def apply_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def extrude_profile(name, profile_yz, width, taper_top=0.0, top_z=None):
    """Extrudes a side-view polygon (y, z) across X. Optionally narrows vertices
    above top_z by taper_top on each side (for a tapered greenhouse)."""
    bm = bmesh.new()
    left = [bm.verts.new((-width / 2, y, z)) for (y, z) in profile_yz]
    right = [bm.verts.new((width / 2, y, z)) for (y, z) in profile_yz]
    n = len(profile_yz)
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([left[i], left[j], right[j], right[i]])
    if taper_top and top_z is not None:
        for v in bm.verts:
            if v.co.z >= top_z - 1e-4:
                v.co.x -= math.copysign(taper_top, v.co.x)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return new_object(name, mesh)


def add_box(name, center, size, mat, rot=(0, 0, 0), bevel=0.0):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    bm.to_mesh(mesh)
    bm.free()
    obj = new_object(name, mesh)
    obj.location = center
    obj.rotation_euler = rot
    obj.data.materials.append(mat)
    if bevel > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        apply_modifiers(obj)
    return obj


def add_cylinder(name, center, radius, depth, mat, verts=24, axis="X", bevel=0.0):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=radius, radius2=radius, depth=depth)
    bm.to_mesh(mesh)
    bm.free()
    obj = new_object(name, mesh)
    obj.location = center
    if axis == "X":
        obj.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "Y":
        obj.rotation_euler = (math.pi / 2, 0, 0)
    obj.data.materials.append(mat)
    if bevel > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
        m.limit_method = "ANGLE"
        apply_modifiers(obj)
    return obj


def boolean_cut(target, cutter):
    m = target.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    try:
        m.solver = "EXACT"
    except Exception:
        pass
    apply_modifiers(target)
    bpy.data.objects.remove(cutter, do_unlink=True)


def join(objs, name):
    activate(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    # Bake object transforms into the mesh.
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def smooth_by_angle(obj, angle=0.7):
    activate(obj)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=angle)
    except Exception:
        try:
            bpy.ops.object.shade_auto_smooth(angle=angle)
        except Exception:
            pass


def export(objs, filename):
    for o in bpy.data.objects:
        if o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    path = os.path.abspath(os.path.join(OUT_DIR, filename))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print("exported", path)




def bevel(obj, width, segments=2, angle_deg=35.0):
    m = obj.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle_deg)
    apply_modifiers(obj)


def cut_wheel_arches(body, axle_ys, radius, width=4.0):
    for y in axle_ys:
        cutter = add_cylinder("arch", (0, y, 0.0), radius, width, body.data.materials[0], verts=32)
        boolean_cut(body, cutter)


def slope_box(name, p0, p1, width, thickness, mat, x=0.0, outward=0.02):
    """A thin panel lying along the side-view line p0 -> p1 (y, z), e.g. a
    windshield. `outward` pushes it off the surface along the line normal."""
    dy, dz = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dy, dz)
    theta = math.atan2(-dy, dz)
    ny, nz = dz / length, -dy / length  # normal pointing forward/up
    cy = (p0[0] + p1[0]) / 2 + ny * outward
    cz = (p0[1] + p1[1]) / 2 + nz * outward
    return add_box(name, (x, cy, cz), (width, thickness, length), mat, rot=(theta, 0, 0))


def standard_materials(paint_rgb):
    return {
        "paint": make_material("Paint", srgb(paint_rgb), rough=0.35, metal=0.1),
        "stripe": make_material("Stripe", srgb((0.97, 0.97, 0.95)), rough=0.35),
        "glass": make_material("Glass", srgb((0.12, 0.17, 0.26)), rough=0.08, metal=0.5),
        "trim": make_material("Trim", srgb((0.13, 0.13, 0.15)), rough=0.6),
        "chrome": make_material("Chrome", srgb((0.85, 0.86, 0.88)), rough=0.15, metal=0.9),
        "head": make_material("Headlight", srgb((1.0, 0.97, 0.85)), rough=0.1, emission=(1.0, 0.95, 0.8), strength=2.0),
        "tail": make_material("TailLight", srgb((0.9, 0.08, 0.06)), rough=0.2, emission=(1.0, 0.05, 0.02), strength=1.0),
        "reverse": make_material("ReverseLight", srgb((0.95, 0.95, 0.95)), rough=0.2),
    }
