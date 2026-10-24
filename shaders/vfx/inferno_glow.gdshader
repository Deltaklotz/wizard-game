shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Soft crimson haze around the Infernal Torrent's cone (InfernoBeam): an additive shell a little
// wider than the smoke, brightest where it is seen edge-on, so the cel-shaded body sits in a
// glow that blooms. Same unit tube and cone as inferno_shell.gdshader.

#include "res://shaders/vfx/inferno_common.gdshaderinc"

uniform float length_m = 10.0;
uniform float r0 = 0.35;
uniform float spread = 0.17;
uniform float radius_scale = 1.25;
uniform float intensity = 1.0;
uniform float cut = 0.0;
uniform float open_end = 1.0;
uniform float energy = 0.35;
uniform vec2 near_fade = vec2(2.0, 12.0);

varying float v_s;
varying float v_d;
varying vec3 v_world;

void vertex() {
	float s = UV.y;
	float d = s * length_m;
	float ang = UV.x * TAU;
	float r = (r0 + spread * d) * radius_scale;
	float head = clamp((length_m - d) / max(r * 0.9, 0.05), 0.0, 1.0);
	r *= sqrt(1.0 - (1.0 - head) * (1.0 - head));
	VERTEX = vec3(cos(ang) * r, sin(ang) * r, -d);
	NORMAL = normalize(vec3(cos(ang), sin(ang), spread));
	v_s = s;
	v_d = d;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float glow = pow(edge, 3.0) * 0.8 + 0.04;
	float flicker = 0.85 + 0.15 * inf_noise2(vec2(v_d * 0.15 - TIME * 3.0, TIME * 2.0));
	float fade = smoothstep(0.0, 0.08, v_s) * (1.0 - smoothstep(0.55, 0.9, v_s) * (0.5 + 0.5 * open_end));
	fade *= smoothstep(near_fade.x, near_fade.y, distance(v_world, CAMERA_POSITION_WORLD));
	fade *= smoothstep(cut, cut + 8.0, v_d + step(cut, 0.001) * 8.0);
	ALBEDO = INF_RED * energy * glow * flicker;
	ALPHA = clamp(fade * intensity, 0.0, 1.0);
}
