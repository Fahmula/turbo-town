@tool
class_name MeshBuilder
extends RefCounted
## Accumulates flat-shaded triangles (with vertex colours and UVs) and turns
## them into an ArrayMesh and/or trimesh collision.
##
## Winding convention for all helpers: give corners counter-clockwise as seen
## from the side the face should be visible from (normal = (b-a)x(c-a)).
## They are flipped internally to Godot's clockwise front-face order.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()


func is_empty() -> bool:
	return verts.is_empty()


func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	verts.append(a); verts.append(c); verts.append(b)
	normals.append(n); normals.append(n); normals.append(n)
	colors.append(col); colors.append(col); colors.append(col)
	uvs.append(uva); uvs.append(uvc); uvs.append(uvb)


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, uvd := Vector2.ZERO) -> void:
	add_tri(a, b, c, col, uva, uvb, uvc)
	add_tri(a, c, d, col, uva, uvc, uvd)


## Axis-aligned-in-local-space box, placed by `xform`. `uv_walls` gives wall
## faces UVs in metres (u along the wall, v up) for the building shader.
func add_box(xform: Transform3D, size: Vector3, col: Color, uv_walls := false, skip_bottom := true) -> void:
	var h := size * 0.5
	var p := [
		xform * Vector3(-h.x, -h.y, -h.z), xform * Vector3(h.x, -h.y, -h.z),
		xform * Vector3(h.x, -h.y, h.z), xform * Vector3(-h.x, -h.y, h.z),
		xform * Vector3(-h.x, h.y, -h.z), xform * Vector3(h.x, h.y, -h.z),
		xform * Vector3(h.x, h.y, h.z), xform * Vector3(-h.x, h.y, h.z),
	]
	var roof_col := col
	if uv_walls:
		roof_col.a = 0.0  # tells the building shader "no windows here"
	# top
	add_quad(p[7], p[6], p[5], p[4], roof_col)
	if not skip_bottom:
		add_quad(p[0], p[1], p[2], p[3], roof_col)
	var y0 := 0.0
	var y1 := size.y
	# +z (south)
	add_quad(p[3], p[2], p[6], p[7], col, Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0, y1))
	# -z (north)
	add_quad(p[1], p[0], p[4], p[5], col, Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0, y1))
	# +x (east)
	add_quad(p[2], p[1], p[5], p[6], col, Vector2(0, y0), Vector2(size.z, y0), Vector2(size.z, y1), Vector2(0, y1))
	# -x (west)
	add_quad(p[0], p[3], p[7], p[4], col, Vector2(0, y0), Vector2(size.z, y0), Vector2(size.z, y1), Vector2(0, y1))


## Vertical prism (e.g. tree trunk, pillar) with `sides` faces.
func add_prism(base: Vector3, radius_bottom: float, radius_top: float, height: float, sides: int, col: Color, cap := true) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + d0 * radius_bottom
		var b1 := base + d1 * radius_bottom
		var t0 := base + d0 * radius_top + Vector3.UP * height
		var t1 := base + d1 * radius_top + Vector3.UP * height
		add_quad(b1, b0, t0, t1, col)
		if cap and radius_top > 0.001:
			add_tri(base + Vector3.UP * height, t1, t0, col)


## Low-poly blob (icosahedron-ish via lat/long) for foliage and clouds.
func add_blob(center: Vector3, radius: Vector3, col: Color, rings := 3, segments := 6, jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	var pts: Array = []
	for r in rings + 1:
		var row: Array = []
		var phi := PI * r / rings
		for s in segments:
			var th := TAU * s / segments + (0.5 * TAU / segments if r % 2 == 1 else 0.0)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			if jitter > 0.0 and rng and r > 0 and r < rings:
				d *= 1.0 + rng.randf_range(-jitter, jitter)
			row.append(center + d * radius)
		pts.append(row)
	for r in rings:
		for s in segments:
			var s1 := (s + 1) % segments
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s1]
			var c: Vector3 = pts[r + 1][s1]
			var d: Vector3 = pts[r + 1][s]
			if r == 0:
				add_tri(a, c, d, col)
			elif r == rings - 1:
				add_tri(a, b, d, col)
			else:
				add_quad(a, b, c, d, col)


## Extrudes a 2D cross-section along a path. Profile points are (across, up)
## offsets in metres, ordered left-to-right over the top so faces point
## outward. The section stays upright (world up) regardless of path slope.
func add_extrusion(path: PackedVector3Array, profile: PackedVector2Array, col: Color, closed_path := false) -> void:
	var n := path.size()
	if n < 2:
		return
	var rights := _path_rights(path, closed_path)
	var seg_count := n if closed_path else n - 1
	for i in seg_count:
		var i1 := (i + 1) % n
		for k in profile.size() - 1:
			var pa := profile[k]
			var pb := profile[k + 1]
			var a := path[i] + rights[i] * pa.x + Vector3.UP * pa.y
			var b := path[i] + rights[i] * pb.x + Vector3.UP * pb.y
			var c := path[i1] + rights[i1] * pb.x + Vector3.UP * pb.y
			var d := path[i1] + rights[i1] * pa.x + Vector3.UP * pa.y
			add_quad(a, b, c, d, col)
	if not closed_path:
		# End caps (fan).
		for end in [0, n - 1]:
			var pts: Array[Vector3] = []
			for pv in profile:
				pts.append(path[end] + rights[end] * pv.x + Vector3.UP * pv.y)
			for k in range(1, pts.size() - 1):
				if end == 0:
					add_tri(pts[0], pts[k + 1], pts[k], col)
				else:
					add_tri(pts[0], pts[k], pts[k + 1], col)


static func _path_rights(path: PackedVector3Array, closed_path: bool) -> PackedVector3Array:
	var n := path.size()
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		var prev := path[(i - 1 + n) % n] if (closed_path or i > 0) else path[i]
		var next := path[(i + 1) % n] if (closed_path or i < n - 1) else path[i]
		var t := next - prev
		t.y = 0.0
		if t.length_squared() < 1e-8:
			t = Vector3.FORWARD
		out[i] = t.normalized().cross(Vector3.UP).normalized()
	return out


func build_mesh(material: Material, existing: ArrayMesh = null) -> ArrayMesh:
	var mesh := existing if existing else ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func build_collision_shape() -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	return shape


## Convenience: MeshInstance3D (+ optional StaticBody3D with trimesh collision).
func build_node(node_name: String, material: Material, with_collision := false, surface_grip := 1.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = build_mesh(material)
	if not with_collision:
		return mi
	var body := StaticBody3D.new()
	body.name = node_name
	mi.name = "Mesh"
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = build_collision_shape()
	body.add_child(cs)
	body.set_meta("surface_grip", surface_grip)
	return body
