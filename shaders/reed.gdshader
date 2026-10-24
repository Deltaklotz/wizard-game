shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/include/stylized_light.gdshaderinc"

// Reed beds at the lake shore. Bending uses the vertex height above the clump root so
// stems, leaves and seed heads sway together. COLOR.r = shade, COLOR.b = plume/cattail.

uniform vec3 base_color : source_color = vec3(0.22, 0.3, 0.1);
uniform vec3 tip_color : source_color = vec3(0.62, 0.6, 0.32);
uniform vec3 plume_color : source_color = vec3(0.5, 0.45, 0.4);
uniform vec3 cattail_color : source_color = vec3(0.3, 0.18, 0.1);
uniform float wind_strength = 0.12;
uniform float reed_height = 2.2;

varying float v_h;
varying float v_rand;
varying vec3 v_wpos;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	v_rand = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_h = clamp(VERTEX.y / reed_height, 0.0, 1.0);
	float bend = v_h * v_h;
	float gust = sin(TIME * 0.9 + root.x * 0.1 + root.z * 0.07) * 0.5 + 0.5;
	vec2 wind = vec2(sin(TIME * 1.6 + root.x * 0.4 + v_rand * 5.0), cos(TIME * 1.2 + root.z * 0.35)) * (0.4 + gust);
	VERTEX.xz += wind * wind_strength * bend * reed_height;
	VERTEX.y -= dot(wind, wind) * wind_strength * bend * 0.2;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, smoothstep(0.1, 1.0, v_h));
	col *= 0.8 + 0.4 * COLOR.r;
	col = mix(col, col * vec3(1.15, 1.05, 0.8), v_rand * 0.5);
	if (COLOR.b > 0.5) {
		col = COLOR.r < 0.4 ? cattail_color : plume_color * (0.85 + 0.3 * v_rand);
	}
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	AO = mix(0.55, 1.0, v_h);
	BACKLIGHT = col * 0.3;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.5, 0.7, vec3(1.2, 1.1, 0.55), 0.4);
	SPECULAR_LIGHT += stylized_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, ROUGHNESS, 0.03);
}
