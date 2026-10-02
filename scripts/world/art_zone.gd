@tool
class_name ArtZone
extends RefCounted
## Environment art preview (ART_BIBLE.md §31): the world inside RECT is built
## in the new environment style, everything outside it stays legacy until the
## owner approves the look and it rolls out to the whole map.
##
## The preview covered the city's central spine (x = -81..81) and the corridor
## north to the hill road; since the owner approved the look (2026-10-01) RECT
## covers the whole island. Builders route geometry by position with has();
## shaders that can't be split by mesh read the global shader uniform
## `art_zone`.
##
## `--legacy-art` on the command line switches the zone off, for before/after
## screenshots and benchmarks from the same build.

## x/z rectangle (Rect2.position = min corner).
const RECT := Rect2(-700.0, -700.0, 1400.0, 1400.0)

static var enabled := not OS.get_cmdline_user_args().has("--legacy-art")


static func has(x: float, z: float) -> bool:
	return enabled and RECT.has_point(Vector2(x, z))


static func has_point(p: Vector3) -> bool:
	return has(p.x, p.z)


## Publishes the zone to the shaders (x0, z0, x1, z1; empty when disabled).
static func publish() -> void:
	var r := Vector4(RECT.position.x, RECT.position.y, RECT.end.x, RECT.end.y) if enabled else Vector4(0, 0, 0, 0)
	RenderingServer.global_shader_parameter_set("art_zone", r)
