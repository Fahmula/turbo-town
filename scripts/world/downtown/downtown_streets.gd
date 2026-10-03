@tool
class_name DowntownStreets
extends RefCounted
## Street-level dressing of the Downtown City MegaKit showcase blocks
## (experiment/quaternius-downtown-city): sidewalk furniture and details
## from the kit around DowntownBlock's buildings. Called by CityBuilder once
## all blocks are built.

var city: CityBuilder
var downtown: DowntownBlock


func _init(city_builder: CityBuilder, blocks: DowntownBlock) -> void:
	city = city_builder
	downtown = blocks


## `root`: the City node; `body`: static collision for solid props;
## `intersections`: RoadBuilder.intersections (x, z, side flags).
func build(root: Node3D, body: StaticBody3D, intersections: Array[Vector3]) -> void:
	pass
