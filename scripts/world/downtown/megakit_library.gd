class_name MegaKitLibrary
extends Resource
## The Downtown City MegaKit modules the game uses, converted by
## tools/megakit/build_megakit_modules.gd (never edit the .res by hand).
##
## Every module is one ArrayMesh surface in the megakit vertex format
## (see MegaKit / megakit.gdshader): VERTEX, NORMAL, TEX_UV (the kit's UV0,
## tiling texture), TEX_UV2 (the kit's UV1: fake-bevel corner normal), COLOR
## (the kit's wear mask, G = clean 1 / grimy 0), CUSTOM0 RGBA8 = (texture
## layer, tint slot, kind, room variant) / 255. Glass, interior walls and
## floors are dropped; glass is drawn by the interior shader.

## Module name -> ArrayMesh (one surface).
@export var meshes: Dictionary = {}
## Module name -> ArrayMesh: the module's road / sidewalk markings
## (megakit_decal.gdshader), only for modules that have any.
@export var decals: Dictionary = {}
## Module name -> AABB of the converted mesh.
@export var bounds: Dictionary = {}
## Module name -> far-LOD proxy (same format): window modules become a
## backing quad plus their interior-mapped window quads, other heavy pieces a
## box; null = drop the module far away (window AC units, doors). Modules
## missing here are cheap enough to use as they are.
@export var far: Dictionary = {}
