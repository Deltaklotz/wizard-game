// Body of foliage.gdshader / foliage_lite.gdshader (#define LITE: no normal map, no specular).

#include "res://shaders/include/stylized_light.gdshaderinc"

// Alpha-tested leaf/needle cards with wind sway, translucency and per-tree tint.
// Vertex COLOR: r = sway weight, g = cluster phase.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform vec3 tint_a : source_color = vec3(0.9, 1.0, 0.85);
uniform vec3 tint_b : source_color = vec3(1.1, 1.0, 0.75);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.0;
uniform float translucency = 0.6;
uniform float texture_size = 1024.0;

varying float v_var;
varying vec3 v_wpos;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	v_var = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float sway = COLOR.r;
	float phase = COLOR.g * 6.2831 + dot(root.xz, vec2(0.13, 0.11));
	float t = TIME * wind_speed;
	vec3 gust = vec3(sin(t * 1.3 + phase), sin(t * 2.3 + phase * 1.7) * 0.35, cos(t * 1.1 + phase * 0.6));
	vec3 flutter = vec3(sin(t * 7.0 + phase * 5.0 + VERTEX.y * 3.0)) * 0.25;
	VERTEX += (gust + flutter) * wind_strength * sway;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// Keep coverage in distant mips so canopies don't thin out.
	vec2 dx = dFdx(UV * texture_size);
	vec2 dy = dFdy(UV * texture_size);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALPHA = tex.a * (1.0 + mip * 0.25);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 tint = mix(tint_a, tint_b, v_var);
	ALBEDO = tex.rgb * tint;
#ifndef LITE
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
#endif
	// Both sides share the (spherical) vertex normal instead of being flipped.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = tex.rgb * tint * translucency;
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.5, translucency, vec3(1.3, 1.2, 0.55), 0.5);
#ifndef LITE
	SPECULAR_LIGHT += stylized_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, ROUGHNESS, 0.03);
#endif
}
