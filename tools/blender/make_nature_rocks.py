"""Splits the Poly Haven rock sets (CC0) into single boulders and exports
game-ready .glb files to assets/models/nature/.

Run from the project root, after tools/textures/fetch_terrain.py downloaded
the models into build/texture_sources/models/ (fetch_terrain.py runs this
script itself):

    blender -b -P tools/blender/make_nature_rocks.py

Per source set (rock_moss_set_01 -> rocks_a.glb, rock_moss_set_02 -> rocks_b.glb):
  * every loose rock becomes one mesh "rock_00", "rock_01"... with its origin
    at the centre of its base, so a rock stands on the ground at (0, 0, 0)
    and is sunk a little (10% of its height) into it;
  * decimated (collapse, UVs kept) to about TARGET_TRIS triangles, so the
    scan's own normal map still carries the fine detail;
  * no materials (the game puts its own, see NatureBuilder._add_rocks);
    UVs are the original atlas, shared by all rocks of a set.
Size stays real: metres, Y up in the glb.
"""
import bpy
import glob
import math
import os
from mathutils import Vector

ROOT = os.path.abspath(os.getcwd())
SRC = os.path.join(ROOT, "build", "texture_sources", "models")
OUT = os.path.join(ROOT, "assets", "models", "nature")
TARGET_TRIS = 700
SETS = {"rock_moss_set_01": "rocks_a", "rock_moss_set_02": "rocks_b"}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(o):
    me = o.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def process(set_name, out_name):
    clear()
    gltf = glob.glob(os.path.join(SRC, set_name + "_1k", "*.gltf"))[0]
    bpy.ops.import_scene.gltf(filepath=gltf)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Bake every object's transform into its mesh, so each one can be moved freely.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Biggest first, stable order.
    meshes.sort(key=lambda o: -max(o.dimensions))
    keep = []
    for i, o in enumerate(meshes):
        # Skip tiny debris (smaller than 25 cm).
        if max(o.dimensions) < 0.25:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        n = tri_count(o)
        if n > TARGET_TRIS:
            mod = o.modifiers.new("dec", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = TARGET_TRIS / n
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier="dec")
        # Origin to the centre of the base (Z is up in Blender), sunk 10%.
        corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        mx = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        height = mx.z - mn.z
        base = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z + height * 0.1))
        for v in o.data.vertices:
            v.co -= base
        o.location = (0, 0, 0)
        o.name = "rock_%02d" % len(keep)
        o.data.name = o.name
        # Smooth shading + recalculated normals so the scan's normal map reads cleanly.
        for p in o.data.polygons:
            p.use_smooth = True
        keep.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, out_name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_materials="NONE", export_yup=True, export_texcoords=True, export_normals=True)
    print("ROCKS %s: %d rocks, %s" % (out_name, len(keep),
          ", ".join("%s %dtris %.1fx%.1fx%.1fm" % (o.name, tri_count(o), *o.dimensions) for o in keep)))


for src, dst in SETS.items():
    process(src, dst)
