class_name Views
extends RefCounted
## The cameras the players look at the world through. With one player that's
## simply the main viewport's camera. In split-screen each player has their
## own SubViewport (SplitScreen), so world code that follows "the camera"
## (grass, tree detail, sound, what's in sight) asks here instead of
## get_viewport().get_camera_3d(), which in split-screen sees no camera.

## Render layers seen in only one split-screen view (19 and 20): the grass
## around each player, and the marker over the other player.
const VIEW_LAYERS: Array[int] = [1 << 18, 1 << 19]
const ALL_VIEW_LAYERS := (1 << 18) | (1 << 19)
## Wider than this (width / height) is a split-screen view.
const SPLIT_ASPECT := 2.2

## The split-screen views, one per player (empty with one player).
static var _views: Array[SubViewport] = []


static func set_split(views: Array[SubViewport]) -> void:
	_views = views.duplicate()


static func is_split() -> bool:
	return not _views.is_empty()


static func view_count() -> int:
	return maxi(_views.size(), 1)


## Player `i`'s view (null with one player).
static func view(i: int) -> SubViewport:
	return _views[i] if i < _views.size() and is_instance_valid(_views[i]) else null


## The camera each player sees through right now.
static func cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if _views.is_empty():
		if from and from.is_inside_tree():
			var cam := from.get_viewport().get_camera_3d()
			if cam:
				out.append(cam)
		return out
	for v in _views:
		if is_instance_valid(v):
			var cam := v.get_camera_3d()
			if cam:
				out.append(cam)
	return out


## Player `i`'s camera (the main camera with one player).
static func camera(from: Node, i := 0) -> Camera3D:
	if _views.is_empty():
		return from.get_viewport().get_camera_3d() if from and from.is_inside_tree() and i == 0 else null
	var v := view(i)
	return v.get_camera_3d() if v else null


## The camera closest to `pos` (null if there is none).
static func nearest(from: Node, pos: Vector3) -> Camera3D:
	var best: Camera3D = null
	var best_d := INF
	for cam in cameras(from):
		var d := cam.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = cam
	return best


## Distance from `pos` to the nearest camera (INF with none).
static func nearest_distance(from: Node, pos: Vector3) -> float:
	var cam := nearest(from, pos)
	return cam.global_position.distance_to(pos) if cam else INF


## Can any player see `pos` (closer than `max_distance` and in view)?
static func sees(from: Node, pos: Vector3, max_distance: float) -> bool:
	for cam in cameras(from):
		if cam.global_position.distance_to(pos) < max_distance and cam.is_position_in_frustum(pos):
			return true
	return false


## The field of view a camera should use for `fov` (degrees, vertical, as
## tuned for a full 16:9 screen). A split-screen view is a wide strip: keeping
## the vertical angle would stretch the sides badly, so it keeps (a little
## more than) the full screen's sideways view instead and crops the top and
## bottom.
static func fit_fov(cam: Camera3D, fov: float) -> float:
	if _views.is_empty() or cam == null or not cam.is_inside_tree():
		return fov
	var size := cam.get_viewport().get_visible_rect().size
	if size.y < 1.0:
		return fov
	var aspect := size.x / size.y
	if aspect < SPLIT_ASPECT:
		return fov
	var half_h := tan(deg_to_rad(fov) * 0.5) * 16.0 / 9.0 * 1.12
	return rad_to_deg(2.0 * atan(half_h / aspect))
