@tool
class_name Ramp
extends StaticBody3D
## Parametric stunt ramp. Drop ramp.tscn into any scene and tweak the values in
## the inspector; the mesh and collision rebuild live in the editor.
##
## The ramp starts at the node origin at ground level and rises towards -Z
## (so drive at it along -Z). Rotate the node to aim it.

enum RampShape { WEDGE, KICKER, QUARTER_PIPE, BUMP }

@export var shape := RampShape.KICKER:
	set(v):
		shape = v
		_queue_rebuild()
@export_range(0.5, 200.0, 0.1) var length := 10.0:
	set(v):
		length = v
		_queue_rebuild()
@export_range(0.1, 60.0, 0.1) var height := 2.5:
	set(v):
		height = v
		_queue_rebuild()
@export_range(1.0, 60.0, 0.1) var width := 6.0:
	set(v):
		width = v
		_queue_rebuild()
## Flat platform after the slope (m).
@export_range(0.0, 100.0, 0.1) var deck_length := 0.0:
	set(v):
		deck_length = v
		_queue_rebuild()
@export var surface_color := Color(1.0, 0.74, 0.22):
	set(v):
		surface_color = v
		_queue_rebuild()
@export var stripe_color := Color(0.92, 0.16, 0.14):
	set(v):
		stripe_color = v
		_queue_rebuild()
@export var stripe_width := 0.6:
	set(v):
		stripe_width = v
		_queue_rebuild()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _pending := false


func _ready() -> void:
	set_meta("surface_grip", 1.0)
	_rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild.call_deferred()


func profile_height(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match shape:
		RampShape.WEDGE:
			return height * t
		RampShape.KICKER:
			# Circular arc through (0,0) and (length, height), tangent to the ground.
			var r := (length * length + height * height) / (2.0 * height)
			var x := t * length
			return r - sqrt(maxf(r * r - x * x, 0.0))
		RampShape.QUARTER_PIPE:
			var x2 := t * length
			var r2 := length
			return (r2 - sqrt(maxf(r2 * r2 - x2 * x2, 0.0))) * height / length
		RampShape.BUMP:
			return height * sin(PI * t)
	return 0.0


func _rebuild() -> void:
	_pending = false
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		add_child(_mesh_instance)
	if _collision == null:
		_collision = CollisionShape3D.new()
		add_child(_collision)

	var mb := MeshBuilder.new()
	var hw := width * 0.5
	var segs := maxi(int(length / 0.8), 6)
	if shape == RampShape.WEDGE:
		segs = maxi(int(length / 1.5), 2)
	var zs: Array[float] = []
	var ys: Array[float] = []
	for i in segs + 1:
		var t := float(i) / segs
		# QUARTER_PIPE: bunch samples near the steep top.
		if shape == RampShape.QUARTER_PIPE:
			t = sin(t * PI * 0.5) * 0.985
		zs.append(-t * length)
		ys.append(profile_height(t))
	if deck_length > 0.0 and shape != RampShape.BUMP:
		var steps := maxi(int(deck_length / 2.0), 1)
		for k in steps:
			zs.append(-length - deck_length * float(k + 1) / steps)
			ys.append(ys[ys.size() - 1])

	# Deck: painted plywood sheets (1.22 x 2.44 m with screws, street_props.gdshader
	# class 15) with hazard-striped edges; the sides are steel plate with
	# stiffening ribs, a galvanised edge rail and a base angle (see below).
	var deck := Color(surface_color, StreetKit.DECK)
	var side_col := Color(0.27, 0.285, 0.3, StreetKit.STEEL_DECK)
	var side_low := Color(0.15, 0.155, 0.16, StreetKit.STEEL_DECK)
	var sw := minf(stripe_width, hw * 0.3)
	# Normals along the profile: smooth on curves, hard where the slope meets the deck.
	var seg_n: Array[Vector3] = []
	for i in zs.size() - 1:
		var d := Vector3(0, ys[i + 1] - ys[i], zs[i + 1] - zs[i])
		seg_n.append(Vector3(0, -d.z, d.y).normalized())
	var dist := 0.0
	for i in zs.size() - 1:
		var p0 := Vector3(0, ys[i], zs[i])
		var p1 := Vector3(0, ys[i + 1], zs[i + 1])
		var n0 := seg_n[i]
		var n1 := seg_n[i]
		if i > 0 and seg_n[i - 1].dot(seg_n[i]) > 0.9:
			n0 = (seg_n[i - 1] + seg_n[i]).normalized()
		if i < seg_n.size() - 1 and seg_n[i + 1].dot(seg_n[i]) > 0.9:
			n1 = (seg_n[i + 1] + seg_n[i]).normalized()
		var d0 := dist
		dist += p0.distance_to(p1)
		var stripe := Color(stripe_color if int(d0 / 1.2) % 2 == 0 else Color(0.92, 0.91, 0.87), StreetKit.DECK)
		var xs := [-hw, -hw + sw, hw - sw, hw]
		var cols := [stripe, deck, stripe]
		for k in 3:
			var a := Vector3(xs[k], p0.y, p0.z)
			var b := Vector3(xs[k + 1], p0.y, p0.z)
			var c := Vector3(xs[k + 1], p1.y, p1.z)
			var e := Vector3(xs[k], p1.y, p1.z)
			var col: Color = cols[k]
			mb.add_quad_ex(a, b, c, e, n0, n0, n1, n1, col, col, col, col,
				Vector2(xs[k], d0), Vector2(xs[k + 1], d0), Vector2(xs[k + 1], dist), Vector2(xs[k], dist))
		# Sides down to the ground.
		mb.add_quad_ex(Vector3(hw, 0, p0.z), Vector3(hw, 0, p1.z), Vector3(hw, p1.y, p1.z), Vector3(hw, p0.y, p0.z),
			Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, side_low, side_low, side_col, side_col,
			Vector2(d0, 0.0), Vector2(dist, 0.0), Vector2(dist, p1.y), Vector2(d0, p0.y))
		mb.add_quad_ex(Vector3(-hw, 0, p1.z), Vector3(-hw, 0, p0.z), Vector3(-hw, p0.y, p0.z), Vector3(-hw, p1.y, p1.z),
			Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, side_low, side_low, side_col, side_col,
			Vector2(dist, 0.0), Vector2(d0, 0.0), Vector2(d0, p0.y), Vector2(dist, p1.y))
	# Back wall.
	var last_z: float = zs[zs.size() - 1]
	var last_y: float = ys[ys.size() - 1]
	if last_y > 0.01:
		var back := Vector3.FORWARD
		mb.add_quad_ex(Vector3(-hw, 0, last_z), Vector3(-hw, last_y, last_z), Vector3(hw, last_y, last_z), Vector3(hw, 0, last_z),
			back, back, back, back, side_low, side_col, side_col, side_low,
			Vector2(-hw, 0.0), Vector2(-hw, last_y), Vector2(hw, last_y), Vector2(hw, 0.0))
	# The collider is the deck, sides and back only; the steel trim below is looks.
	_collision.shape = mb.build_collision_shape()
	_add_steel(mb, hw, zs, ys)
	_mesh_instance.mesh = mb.build_mesh(StreetKit.material())


## Galvanised edge rails along the deck, stiffening ribs on the steel side
## plates and a base angle (all in the deck's mesh, so no extra draw calls).
func _add_steel(mb: MeshBuilder, hw: float, zs: Array[float], ys: Array[float]) -> void:
	var galv := StreetKit.k(StreetKit.GALV, StreetKit.METAL)
	var rib := Color(0.34, 0.355, 0.375, StreetKit.PAINTED)
	var last := zs.size() - 1
	var step := maxi(1, ceili(last / 24.0))
	for s: float in [-1.0, 1.0]:
		var x := s * (hw + 0.025)
		var i := 0
		while i < last:
			var j := mini(i + step, last)
			StreetKit.beam(mb, Vector3(x, ys[i] - 0.035, zs[i]), Vector3(x, ys[j] - 0.035, zs[j]), 0.05, 0.07, galv, 0.01)
			i = j
		var acc := 0.0
		for q in last:
			acc += absf(zs[q + 1] - zs[q])
			if acc >= 1.6 and ys[q + 1] > 0.3:
				acc = 0.0
				mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(s * (hw + 0.012), ys[q + 1] * 0.5 - 0.02, zs[q + 1])),
					Vector3(0.025, ys[q + 1] - 0.14, 0.07), 0.008, rib, Color(0, 0, 0, -1), false)
		StreetKit.beam(mb, Vector3(s * (hw + 0.02), 0.045, zs[0]), Vector3(s * (hw + 0.02), 0.045, zs[last]), 0.05, 0.09, galv, 0.01)
	# Stiffening ribs across the back wall.
	if ys[last] > 0.5:
		var nribs := maxi(int(hw * 2.0 / 1.6), 1)
		for r in nribs + 1:
			var rx := -hw + hw * 2.0 * float(r) / nribs
			mb.add_bevel_box(Transform3D(Basis.IDENTITY, Vector3(rx, ys[last] * 0.5, zs[last] - 0.025)), Vector3(0.07, ys[last] - 0.12, 0.05), 0.01, rib, Color(0, 0, 0, -1), false)
