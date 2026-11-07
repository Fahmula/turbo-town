shader_type spatial;
// Car paint (ART_BIBLE.md §13, §14): every vehicle's "Paint" and "Stripe"
// surfaces and the parked cars. VehicleBodyVisual.paint_material() makes one
// per car.
//
// * Gloss: a low base roughness plus a clear coat. Reflection probes (the
//   player's VehicleReflection) replace Godot's clear-coat reflection with the
//   base layer's, so the base itself must be glossy for crisp reflections.
// * Metallic paints: colour "flop" (brighter facing the camera, darker at
//   grazing angles) and fine flakes that glint up close (faded with distance).
// * Reflections of the ground are toned down, so the lower doors read dark
//   like a real car's instead of mirroring the sky's pale ground half.
// * Grime: `dirt` (0..1) dusts the lower body (object-space height, broken up
//   by splash noise). VehicleBodyVisual raises it while driving on dirt.
// * Damage: vertex colour, written by VehicleDamage when it dents a mesh,
//   stored inverted so meshes without colours read as clean (Godot's default
//   vertex colour is white): G = 1 - scrape, B = 1 - paint loss (R and A
//   reserved). The mask goes clean paint -> scuffed (rougher, lighter) ->
//   primer #8C8C88 -> bare steel #9A9C9E, as streaks along the body for
//   scrapes and blotches for impacts.
// Object space: origin at wheel-centre height, -Z forward, +Y up.

render_mode cull_back;

#include "res://assets/shaders/vehicle/car_paint.gdshaderinc"
