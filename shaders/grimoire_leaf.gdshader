shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/grimoire_parchment.gdshaderinc"

// Rotation of the leaf root around the spine (0 = lying on the right, PI = on the left).
uniform float angle = 0.0;
// Bend in radians per meter; the leaf is shaped as a circular arc.
uniform float curl = 0.0;

uniform float front_seed = 0.0;
uniform float back_seed = 1.0;
uniform sampler2D front_content : source_color, hint_default_transparent;
uniform sampler2D back_content : source_color, hint_default_transparent;
uniform float front_strength = 0.0;
uniform float back_strength = 0.0;
// The arcane circle behind a spell symbol (see grimoire_page.gdshader), frozen while turning.
uniform float front_circle_strength = 0.0;
uniform float back_circle_strength = 0.0;
uniform vec3 front_circle_color : source_color = vec3(0.4, 0.6, 1.0);
uniform vec3 back_circle_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float front_circle_angle = 0.0;
uniform float back_circle_angle = 0.0;

void vertex() {
	// Leaf is authored flat along +X; bend it around the spine (Z axis).
	float d = VERTEX.x;
	float th = angle + curl * d;
	vec2 p;
	if (abs(curl) < 0.0001) {
		p = vec2(cos(angle), sin(angle)) * d;
	} else {
		p = vec2(sin(th) - sin(angle), cos(angle) - cos(th)) / curl;
	}
	VERTEX.x = p.x;
	VERTEX.y += p.y;
	NORMAL = vec3(-sin(th), cos(th), 0.0);
}

void fragment() {
	vec3 c;
	if (FRONT_FACING) {
		c = parchment(UV, front_seed);
		c = mix(c, front_circle_color * 0.5, arcane_circle(UV, front_circle_angle) * front_circle_strength * 0.88);
		vec4 ink = texture(front_content, UV);
		c = mix(c, ink.rgb, ink.a * front_strength);
	} else {
		c = parchment(UV, back_seed);
		c = mix(c, back_circle_color * 0.5, arcane_circle(UV, back_circle_angle) * back_circle_strength * 0.88);
		vec4 ink = texture(back_content, UV);
		c = mix(c, ink.rgb, ink.a * back_strength);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	// Thin paper lets a little light through.
	BACKLIGHT = vec3(0.25, 0.2, 0.14);
}

void light() {
	DIFFUSE_LIGHT += page_diffuse(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
