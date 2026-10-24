shader_type canvas_item;
// Ink of a Primordial spell page (InventoryUI): the dark artwork turned into pale violet light
// that breathes and shimmers, with a faint glow spilling around the lines.

uniform vec4 ink_color : source_color = vec4(0.82, 0.66, 1.0, 1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	// Soft halo: the alpha of nearby texels.
	vec2 px = TEXTURE_PIXEL_SIZE * 4.0;
	float halo = (texture(TEXTURE, UV + vec2(px.x, 0)).a + texture(TEXTURE, UV - vec2(px.x, 0)).a
		+ texture(TEXTURE, UV + vec2(0, px.y)).a + texture(TEXTURE, UV - vec2(0, px.y)).a) * 0.25;
	float shimmer = 0.75 + 0.25 * sin(TIME * 2.4 + UV.y * 14.0);
	vec3 col = mix(ink_color.rgb, vec3(1.0), a * 0.4) * (1.1 + 0.5 * shimmer);
	COLOR = vec4(col, clamp(a + halo * 0.45 * shimmer, 0.0, 1.0));
}
