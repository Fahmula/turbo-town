shader_type spatial;
// The player's car paint (ART_BIBLE.md §13): car_paint plus the garage's
// finishes (pearl, chrome), two-tone, side decals and race numbers.
// VehicleBodyVisual.set_paint_style swaps a car's paint to this shader only
// when it needs it, so traffic never pays for it.

render_mode cull_back;

#define PAINT_CUSTOM
#include "res://assets/shaders/vehicle/car_paint.gdshaderinc"
