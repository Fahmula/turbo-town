shader_type spatial;
// Pedestrians (ART_BIBLE.md §34, "Pedestrians"): one material for the whole
// crowd. Every person's mesh (tools/blender/make_pedestrians.py) puts each
// region on a cell of a 16x16 palette (4x4-texel cells, its PED_CELLS order);
// this recolours the cells per person from instance uniforms
// (PedestrianLook.dress), so everyone shares one material and draws in one
// call. Flat PBR colours as on the player: skin ~0.55 roughness, cotton
// ~0.85, denim ~0.8, shoes ~0.6, hair ~0.6.
render_mode cull_back;

uniform sampler2D palette : source_color, filter_nearest;

instance uniform vec4 skin_color : source_color = vec4(0.76, 0.56, 0.44, 1.0);
instance uniform vec4 hair_color : source_color = vec4(0.21, 0.14, 0.10, 1.0);
instance uniform vec4 top_color : source_color = vec4(0.45, 0.55, 0.45, 1.0);
instance uniform vec4 bottom_color : source_color = vec4(0.25, 0.28, 0.36, 1.0);
instance uniform vec4 shoe_color : source_color = vec4(0.88, 0.87, 0.84, 1.0);
instance uniform vec4 accent_color : source_color = vec4(0.70, 0.55, 0.20, 1.0);
// Roughness of the top and bottom (denim, cotton, a jacket's nylon...).
instance uniform vec2 cloth_rough = vec2(0.85, 0.8);

void fragment() {
	// Cell index in PED_CELLS order. glTF flips V, so the palette's first row
	// of cells (Blender's bottom row) is at the top of UV space's last row.
	ivec2 c = clamp(ivec2(floor(UV * 4.0)), ivec2(0), ivec2(3));
	int cell = (3 - c.y) * 4 + c.x;
	vec3 col = texture(palette, UV).rgb;
	float rough = 0.6;
	switch (cell) {
		case 0: col = skin_color.rgb; rough = 0.55; break;                            // skin
		case 1: col = skin_color.rgb * vec3(0.74, 0.56, 0.68); rough = 0.45; break;   // lips
		case 2: rough = 0.3; break;                                                   // sclera
		case 3: rough = 0.3; break;                                                   // iris
		case 4: rough = 0.3; break;                                                   // pupil
		case 5: col = hair_color.rgb; rough = 0.6; break;                             // hair, brows
		case 6: col = top_color.rgb; rough = cloth_rough.x; break;                    // top
		case 7: col = bottom_color.rgb; rough = cloth_rough.y; break;                 // bottom
		case 8: col = shoe_color.rgb; rough = 0.6; break;                             // shoe upper
		case 9: rough = 0.7; break;                                                   // sole
		case 10: col = skin_color.rgb * vec3(0.31, 0.20, 0.27); rough = 0.5; break;   // mouth
		case 11: col = mix(shoe_color.rgb, vec3(0.5), 0.35); rough = 0.8; break;      // laces
		case 12: col = shoe_color.rgb * 0.35 + 0.02; rough = 0.6; break;              // heel tab
		case 13: col = accent_color.rgb; rough = 0.7; break;                          // cap, zip
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
