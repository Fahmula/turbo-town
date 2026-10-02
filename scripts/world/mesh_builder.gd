@tool
class_name MeshBuilder
extends RefCounted
## Accumulates triangles (with vertex colours and UVs) and turns them into an
## ArrayMesh and/or trimesh collision.
##
## add_tri / add_quad make flat faces. The shape helpers (add_bevel_box,
## add_lathe, add_sweep, add_tri_ex, add_quad_ex) take per-vertex normals, so
## bevels and round parts shade smoothly while flat faces stay flat
## (ART_BIBLE.md §24 "weighted normals" look).
##
## Winding convention for all helpers: give corners counter-clockwise as seen
## from the side the face should be visible from (normal = (b-a)x(c-a)).
## They are flipped internally to Godot's clockwise front-face order.
## The smooth helpers orient their triangles themselves.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
## Second UV channel: stamped on every vertex from `uv2`; only written to the
## mesh once set_uv2() has been called (per-building data for the facade shader).
var uv2s := PackedVector2Array()
var uv2 := Vector2.ZERO
var _has_uv2 := false


func is_empty() -> bool:
	return verts.is_empty()


## Value stamped into UV2 for every vertex added from now on.
func set_uv2(v: Vector2) -> void:
	uv2 = v
	_has_uv2 = true


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
	uv2s.append(uv2); uv2s.append(uv2); uv2s.append(uv2)


## Triangle with per-vertex normals and colours, corners CCW from the front.
func add_tri_ex(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	verts.append(a); verts.append(c); verts.append(b)
	normals.append(na); normals.append(nc); normals.append(nb)
	colors.append(ca); colors.append(cc); colors.append(cb)
	uvs.append(uva); uvs.append(uvc); uvs.append(uvb)
	uv2s.append(uv2); uv2s.append(uv2); uv2s.append(uv2)


## Like add_tri_ex, but flips the corners if needed so the face points along
## `outward` (lets the smooth helpers ignore winding).
func _tri_out(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, uva: Vector2, uvb: Vector2, uvc: Vector2, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		add_tri_ex(a, c, b, na, nc, nb, ca, cc, cb, uva, uvc, uvb)
	else:
		add_tri_ex(a, b, c, na, nb, nc, ca, cb, cc, uva, uvb, uvc)


## Quad (corners in order around the edge) with per-vertex normals and colours.
func add_quad_ex(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, uvd := Vector2.ZERO) -> void:
	var outward := na + nb + nc + nd
	_tri_out(a, b, c, na, nb, nc, ca, cb, cc, uva, uvb, uvc, outward)
	_tri_out(a, c, d, na, nc, nd, ca, cc, cd, uva, uvc, uvd, outward)


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, uvd := Vector2.ZERO) -> void:
	add_tri(a, b, c, col, uva, uvb, uvc)
	add_tri(a, c, d, col, uva, uvc, uvd)


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


# ---------------------------------------------------------- shape helpers ---

## Box with chamfered edges (`bevel` metres). Flat faces keep their own normal
## and the chamfers blend between the two faces they join, so edges catch the
## light like a rounded bevel. `col_bottom` (alpha >= 0) tints the box from
## the bottom (contact AO, stained bases); otherwise the box is one colour.
## UVs are metres, planar per face (on the sides: u along, v up from the base).
func add_bevel_box(xform: Transform3D, size: Vector3, bevel: float, col: Color,
		col_bottom := Color(0, 0, 0, -1.0), skip_bottom := true) -> void:
	var h := size * 0.5
	var b := clampf(bevel, 0.0, minf(h.x, minf(h.y, h.z)) * 0.95)
	var k := h - Vector3(b, b, b)
	var bot := col if col_bottom.a < 0.0 else col_bottom
	var basis := xform.basis.orthonormalized()
	var face_pts := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
	# Faces.
	for a in 3:
		for s: float in [-1.0, 1.0]:
			if skip_bottom and a == 1 and s < 0.0:
				continue
			var u := (a + 1) % 3
			var v := (a + 2) % 3
			var n := Vector3.ZERO
			n[a] = s
			var p: Array[Vector3] = []
			for c: Array in face_pts:
				var q := Vector3.ZERO
				q[a] = s * h[a]
				q[u] = c[0] * k[u]
				q[v] = c[1] * k[v]
				p.append(q)
			_bevel_quad(xform, basis, p, [n, n, n, n], [a, a, a, a], h, col, bot)
	# Edge chamfers between face (a, sa) and face (c, sc), running along e.
	for a in 3:
		for c in range(a + 1, 3):
			var e := 3 - a - c
			for sa: float in [-1.0, 1.0]:
				for sc: float in [-1.0, 1.0]:
					var na := Vector3.ZERO
					na[a] = sa
					var nc := Vector3.ZERO
					nc[c] = sc
					var p: Array[Vector3] = []
					for se: float in [-1.0, 1.0]:
						var q := Vector3.ZERO
						q[a] = sa * h[a]
						q[c] = sc * k[c]
						q[e] = se * k[e]
						p.append(q)
					for se: float in [1.0, -1.0]:
						var q := Vector3.ZERO
						q[c] = sc * h[c]
						q[a] = sa * k[a]
						q[e] = se * k[e]
						p.append(q)
					_bevel_quad(xform, basis, p, [na, na, nc, nc], [a, a, c, c], h, col, bot)
	# Corner triangles.
	if b <= 0.0:
		return
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p0 := Vector3(sx * h.x, sy * k.y, sz * k.z)
				var p1 := Vector3(sx * k.x, sy * h.y, sz * k.z)
				var p2 := Vector3(sx * k.x, sy * k.y, sz * h.z)
				var n0 := basis * Vector3(sx, 0, 0)
				var n1 := basis * Vector3(0, sy, 0)
				var n2 := basis * Vector3(0, 0, sz)
				_tri_out(xform * p0, xform * p1, xform * p2, n0, n1, n2,
					_grad(bot, col, p0.y, h.y), _grad(bot, col, p1.y, h.y), _grad(bot, col, p2.y, h.y),
					_face_uv(p0, 0, h), _face_uv(p1, 1, h), _face_uv(p2, 2, h), basis * Vector3(sx, sy, sz))


func _bevel_quad(xform: Transform3D, basis: Basis, p: Array[Vector3], n: Array, axes: Array, h: Vector3, col: Color, bot: Color) -> void:
	var w: Array[Vector3] = []
	var wn: Array[Vector3] = []
	var cs: Array[Color] = []
	var uv: Array[Vector2] = []
	for i in 4:
		w.append(xform * p[i])
		wn.append(basis * (n[i] as Vector3))
		cs.append(_grad(bot, col, p[i].y, h.y))
		uv.append(_face_uv(p[i], axes[i], h))
	var outward := wn[0] + wn[1] + wn[2] + wn[3]
	_tri_out(w[0], w[1], w[2], wn[0], wn[1], wn[2], cs[0], cs[1], cs[2], uv[0], uv[1], uv[2], outward)
	_tri_out(w[0], w[2], w[3], wn[0], wn[2], wn[3], cs[0], cs[2], cs[3], uv[0], uv[2], uv[3], outward)


static func _grad(bot: Color, top: Color, y: float, hy: float) -> Color:
	return bot.lerp(top, clampf((y + hy) / maxf(2.0 * hy, 1e-4), 0.0, 1.0))


## Planar UV in metres for a point on the face along `axis`.
static func _face_uv(p: Vector3, axis: int, h: Vector3) -> Vector2:
	match axis:
		0:
			return Vector2(p.z + h.z, p.y + h.y)
		2:
			return Vector2(p.x + h.x, p.y + h.y)
	return Vector2(p.x + h.x, p.z + h.z)


## Surface of revolution around the local Y axis. `profile` points are
## (radius, height) from bottom to top; end on radius 0 to close a cap.
## Joints sharper than `smooth_deg` stay hard edges, softer ones are smoothed.
## `cols` has one colour per profile point (a single colour is used for all).
## UVs: u = metres around (at that radius), v = metres along the profile.
func add_lathe(xform: Transform3D, profile: PackedVector2Array, sides: int, cols: PackedColorArray, smooth_deg := 35.0) -> void:
	var basis := xform.basis.orthonormalized()
	var np := profile.size()
	if np < 2:
		return
	var seg_n: Array[Vector2] = []
	for i in np - 1:
		var d := profile[i + 1] - profile[i]
		seg_n.append(Vector2(d.y, -d.x).normalized())
	var cos_lim := cos(deg_to_rad(smooth_deg))
	var ring: Array[Vector3] = []
	for s in sides + 1:
		var ang := TAU * s / sides
		ring.append(Vector3(cos(ang), 0.0, sin(ang)))
	var v := 0.0
	for i in np - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var n0 := seg_n[i]
		var n1 := seg_n[i]
		if i > 0 and seg_n[i - 1].dot(seg_n[i]) > cos_lim:
			n0 = (seg_n[i - 1] + seg_n[i]).normalized()
		if i < np - 2 and seg_n[i + 1].dot(seg_n[i]) > cos_lim:
			n1 = (seg_n[i + 1] + seg_n[i]).normalized()
		var c0 := cols[mini(i, cols.size() - 1)]
		var c1 := cols[mini(i + 1, cols.size() - 1)]
		var v1 := v + p0.distance_to(p1)
		for s in sides:
			var ra := ring[s]
			var rb := ring[s + 1]
			var a0 := xform * (ra * p0.x + Vector3.UP * p0.y)
			var b0 := xform * (rb * p0.x + Vector3.UP * p0.y)
			var a1 := xform * (ra * p1.x + Vector3.UP * p1.y)
			var b1 := xform * (rb * p1.x + Vector3.UP * p1.y)
			var na0 := basis * (ra * n0.x + Vector3.UP * n0.y)
			var nb0 := basis * (rb * n0.x + Vector3.UP * n0.y)
			var na1 := basis * (ra * n1.x + Vector3.UP * n1.y)
			var nb1 := basis * (rb * n1.x + Vector3.UP * n1.y)
			var u0 := TAU * s / sides
			var u1 := TAU * (s + 1) / sides
			var out := na0 + nb0 + na1 + nb1
			_tri_out(a0, b0, b1, na0, nb0, nb1, c0, c0, c1,
				Vector2(u0 * p0.x, v), Vector2(u1 * p0.x, v), Vector2(u1 * p1.x, v1), out)
			_tri_out(a0, b1, a1, na0, nb1, na1, c0, c1, c1,
				Vector2(u0 * p0.x, v), Vector2(u1 * p1.x, v1), Vector2(u0 * p1.x, v1), out)
		v = v1


## Extrudes `profile` ((across, up) points, ordered left to right over the
## top) along `path`, with smooth normals across profile joints softer than
## `smooth_deg`. Sections stay upright. `cols`: one colour per profile point.
## UVs: u = metres along the path, v = metres along the profile.
func add_sweep(path: PackedVector3Array, profile: PackedVector2Array, cols: PackedColorArray,
		smooth_deg := 35.0, closed_path := false, caps := true) -> void:
	var n := path.size()
	var np := profile.size()
	if n < 2 or np < 2:
		return
	var rights := _path_rights(path, closed_path)
	var seg_n: Array[Vector2] = []
	for k in np - 1:
		var d := profile[k + 1] - profile[k]
		seg_n.append(Vector2(-d.y, d.x).normalized())
	var cos_lim := cos(deg_to_rad(smooth_deg))
	var dist := PackedFloat32Array()
	dist.resize(n + 1)
	dist[0] = 0.0
	for i in n:
		dist[i + 1] = dist[i] + path[i].distance_to(path[(i + 1) % n])
	var seg_count := n if closed_path else n - 1
	var pv := 0.0
	for k in np - 1:
		var pa := profile[k]
		var pb := profile[k + 1]
		var na2 := seg_n[k]
		var nb2 := seg_n[k]
		if k > 0 and seg_n[k - 1].dot(seg_n[k]) > cos_lim:
			na2 = (seg_n[k - 1] + seg_n[k]).normalized()
		if k < np - 2 and seg_n[k + 1].dot(seg_n[k]) > cos_lim:
			nb2 = (seg_n[k + 1] + seg_n[k]).normalized()
		var ca := cols[mini(k, cols.size() - 1)]
		var cb := cols[mini(k + 1, cols.size() - 1)]
		var pv1 := pv + pa.distance_to(pb)
		for i in seg_count:
			var i1 := (i + 1) % n
			var a := path[i] + rights[i] * pa.x + Vector3.UP * pa.y
			var b := path[i] + rights[i] * pb.x + Vector3.UP * pb.y
			var c := path[i1] + rights[i1] * pb.x + Vector3.UP * pb.y
			var d := path[i1] + rights[i1] * pa.x + Vector3.UP * pa.y
			var nai := rights[i] * na2.x + Vector3.UP * na2.y
			var nbi := rights[i] * nb2.x + Vector3.UP * nb2.y
			var nbj := rights[i1] * nb2.x + Vector3.UP * nb2.y
			var naj := rights[i1] * na2.x + Vector3.UP * na2.y
			var u0 := dist[i]
			var u1 := dist[i + 1]
			add_quad_ex(a, b, c, d, nai, nbi, nbj, naj, ca, cb, cb, ca,
				Vector2(u0, pv), Vector2(u0, pv1), Vector2(u1, pv1), Vector2(u1, pv))
		pv = pv1
	if closed_path or not caps:
		return
	for end in [0, n - 1]:
		var t := (path[mini(end + 1, n - 1)] - path[maxi(end - 1, 0)])
		t.y = 0.0
		var out := -t.normalized() if end == 0 else t.normalized()
		var pts: Array[Vector3] = []
		for pv2 in profile:
			pts.append(path[end] + rights[end] * pv2.x + Vector3.UP * pv2.y)
		var cc := cols[cols.size() / 2]
		for k in range(1, np - 1):
			_tri_out(pts[0], pts[k], pts[k + 1], out, out, out, cc, cc, cc,
				Vector2(profile[0].x, profile[0].y), Vector2(profile[k].x, profile[k].y), Vector2(profile[k + 1].x, profile[k + 1].y), out)


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
	if _has_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## The same mesh with automatic LODs (as the glTF importer makes them): the
## renderer swaps in simpler versions with distance, below a pixel of error.
## For meshes seen from far away (props, trees, buildings); one surface.
static func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() != 1:
		return mesh
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.index()
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mesh.surface_get_material(0))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


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
