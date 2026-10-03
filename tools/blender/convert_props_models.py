"""Turns a downloaded CC0 Poly Haven glTF into a light game asset:

    blender -b -P tools/blender/convert_props_models.py -- <in.gltf> <out.glb> <max_tris> <texture_size> [keep] [drop]

Joins every mesh of the file into one (optionally only the objects whose name
contains `keep` and not `drop`: Poly Haven's hydrant, for one, ships a clean and
an aged variant side by side, plus a chain), collapses it to about `max_tris` triangles
(Decimate, UVs kept), shrinks the textures to `texture_size` and exports a GLB
that Godot imports natively. Called by tools/textures/fetch_props.py.
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, max_tris, tex_size = argv[0], argv[1], int(argv[2]), int(argv[3])
keep = argv[4] if len(argv) > 4 else ""
drop = argv[5] if len(argv) > 5 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if keep or drop:
    for o in meshes:
        if (keep and keep not in o.name) or (drop and drop in o.name):
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
if tris > max_tris:
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = max_tris / tris
    bpy.ops.object.modifier_apply(modifier=mod.name)
for img in bpy.data.images:
    if img.size[0] > tex_size:
        img.scale(tex_size, tex_size)
tris2 = sum(len(p.vertices) - 2 for p in obj.data.polygons)
print("CONVERT %s: %d -> %d tris" % (src, tris, tris2))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_selection=False, export_apply=True)
