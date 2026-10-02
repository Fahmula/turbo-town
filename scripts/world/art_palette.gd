@tool
class_name ArtPalette
extends RefCounted
## The world's base colours (ART_BIBLE.md §5), in sRGB like any Color().
## Builders read these instead of their own Color() literals, so a palette
## change happens in one place. Small accents (signs, boats, awnings...) stay
## in the builders. The road shaders (road_surface, junction) keep uniform
## defaults that mirror ASPHALT, ROAD_WHITE, ROAD_YELLOW and CONCRETE; the sea
## colours live in water.gdshader (values in ART_BIBLE.md §5).

# Roads and paved ground
const ASPHALT := Color(0.275, 0.278, 0.29)
const ASPHALT_DARK := Color(0.25, 0.253, 0.265)
const ROAD_WHITE := Color(0.894, 0.886, 0.855)
const ROAD_YELLOW := Color(0.851, 0.643, 0.129)
const CONCRETE := Color(0.706, 0.69, 0.655)
const CONCRETE_TOP := Color(0.74, 0.725, 0.69)
const CONCRETE_STAINED := Color(0.557, 0.541, 0.51)
## Aprons, quays and forecourts.
const PAVING := Color(0.64, 0.62, 0.58)
const SIDEWALK := Color(0.741, 0.722, 0.682)
const CURB := Color(0.659, 0.639, 0.604)
const PLAZA := Color(0.8, 0.74, 0.64)
## Flat roof membranes.
const ROOF := Color(0.431, 0.424, 0.408)

# Natural ground (pairs are blended by noise)
const GRASS_DARK := Color(0.31, 0.44, 0.2)
const GRASS_LIGHT := Color(0.45, 0.54, 0.26)
const GRASS_DRY := Color(0.54, 0.54, 0.29)
const LAWN := Color(0.36, 0.52, 0.24)
const DIRT := Color(0.56, 0.43, 0.29)
const DIRT_DARK := Color(0.5, 0.38, 0.26)
const DIRT_RUT := Color(0.43, 0.33, 0.23)
const ROCK_DARK := Color(0.5, 0.48, 0.46)
const ROCK_LIGHT := Color(0.58, 0.56, 0.53)
const SAND_LIGHT := Color(0.85, 0.77, 0.6)
const SAND_DARK := Color(0.8, 0.72, 0.55)

# Vegetation
const BARK := Color(0.35, 0.275, 0.21)
const BROADLEAF := Color(0.28, 0.41, 0.17)
## Sunlit canopy tops (foliage_lit).
const FOLIAGE_LIT := Color(0.486, 0.604, 0.271)
const CONIFER := Color(0.19, 0.3, 0.18)
const CONIFER_LIT := Color(0.27, 0.39, 0.23)

# Water features in the city (the sea is water.gdshader)
const POND := Color(0.22, 0.4, 0.45)
const FOUNTAIN := Color(0.3, 0.48, 0.52)

## Building walls (BuildingKit), by facade style (ART_BIBLE.md §5).
const STUCCO_WALLS := [
	Color(0.847, 0.8, 0.706), Color(0.788, 0.541, 0.439), Color(0.561, 0.71, 0.682),
	Color(0.886, 0.812, 0.604), Color(0.88, 0.86, 0.81), Color(0.8, 0.62, 0.58),
]
const LIMESTONE_WALLS := [Color(0.784, 0.718, 0.604), Color(0.82, 0.78, 0.7), Color(0.7, 0.68, 0.64)]
const BRICK_WALLS := [Color(0.557, 0.29, 0.227), Color(0.47, 0.27, 0.21), Color(0.7, 0.58, 0.44)]
const MULLIONS := [Color(0.227, 0.247, 0.267), Color(0.55, 0.57, 0.6)]
const PANEL_WALLS := [Color(0.86, 0.85, 0.81), Color(0.66, 0.64, 0.6), Color(0.52, 0.58, 0.64)]
const TRIM_WHITE := Color(0.91, 0.894, 0.855)
## Shop fascias and awnings: muted accents.
const SHOP_ACCENTS := [
	Color(0.55, 0.2, 0.17), Color(0.18, 0.3, 0.45), Color(0.22, 0.38, 0.27),
	Color(0.72, 0.52, 0.2), Color(0.28, 0.28, 0.3),
]
