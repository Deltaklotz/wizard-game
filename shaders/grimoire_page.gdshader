shader_type spatial;
render_mode cull_back;

#include "res://shaders/grimoire_parchment.gdshaderinc"

uniform float seed = 0.0;
// Spell artwork / text for this page face. Empty for now.
uniform sampler2D page_content : source_color, hint_default_transparent;
uniform float content_strength = 0.0;
// Arcane circle behind the spell symbol (Grimoire._update_circle): strength 0 = none (no spell),
// the spell's theme colour, its turn (the cooldown spin) and a one-off glow when it stops.
uniform float circle_strength = 0.0;
uniform vec3 circle_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float circle_angle = 0.0;
uniform float circle_flash = 0.0;
// Angle the circle turns during one frame (rad): smeared over that arc, so a fast spin blurs
// instead of strobing.
uniform float circle_blur = 0.0;

void fragment() {
	vec3 c = parchment(UV, seed);
	vec4 ink = texture(page_content, UV);
	// Circle in coloured ink, under the symbol.
	float circ = 0.0;
	if (circle_strength > 0.0) {
		if (circle_blur > 0.01) {
			for (int i = 0; i < 6; i++) {
				circ += arcane_circle(UV, circle_angle - circle_blur * float(i) / 5.0);
			}
			circ /= 6.0;
		} else {
			circ = arcane_circle(UV, circle_angle);
		}
		circ *= circle_strength;
	}
	c = mix(c, circle_color * 0.5, circ * 0.88);
	c = mix(c, ink.rgb, ink.a * content_strength);
	EMISSION = circle_color * circ * (1.0 - ink.a * content_strength) * circle_flash * 3.0;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}

void light() {
	DIFFUSE_LIGHT += page_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
