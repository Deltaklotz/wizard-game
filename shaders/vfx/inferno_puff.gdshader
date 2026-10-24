shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
// Cel-shaded billow particle of the Infernal Torrent (InfernoBeam): a camera-facing blob cut
// from noise with an alpha scissor (hard anime edges, sorted by depth like solid geometry).
//   flame = false: black smoke with indigo patches and a burning red rim.
//   flame = true:  crimson flame with a hot pink heart.
// It erodes away over its life (INSTANCE_CUSTOM.y = age 0..1) and near the camera; COLOR.a
// scales it (the emitter's fade).

#include "res://shaders/vfx/inferno_common.gdshaderinc"

uniform bool flame = false;
uniform vec2 near_fade = vec2(1.5, 7.0);
// Extra erosion around the centre of the view (the caster's own torrent).
uniform float aim_clear = 0.0;
// Where the torrent currently ends (a shield, wall or the ground): billows / sparks that flew
// past it are cut off there, so they don't pass through what stopped the beam. Set per
// frame by InfernoBeam; the defaults (no end) leave the impact splash untouched.
uniform vec3 beam_origin = vec3(0.0);
uniform vec3 beam_dir = vec3(0.0, 0.0, -1.0);
uniform float beam_len = 1e9;

varying float v_age;
varying float v_seed;
varying vec3 v_world;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	v_world = MODEL_MATRIX[3].xyz;
}

vec4 shade(vec2 uv, vec3 cam_pos, vec3 cam_fwd, float fade, vec3 frag_world) {
	vec2 c = uv * 2.0 - 1.0;
	float a = TIME * (flame ? 1.4 : 0.5) + v_seed * 6.28;
	vec2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * c;
	vec2 q = r * 1.6 + v_seed * 17.0;
	q += (vec2(inf_noise2(q * 0.8 + 3.0), inf_noise2(q * 0.8 + 11.0)) - 0.5) * 1.4;
	float n = inf_fbm2(q);
	float body = 1.0 - length(c) * 1.05 + (n - 0.5) * 1.5;
	// Torn: holes and ragged bites grow as it ages.
	body -= (0.15 + v_age * 0.55) * smoothstep(0.45, 0.8, inf_noise2(q * 2.3 + 7.0));
	float cam = 1.0 - smoothstep(near_fade.x, near_fade.y, distance(v_world, cam_pos));
	float off_axis = 1.0 - dot(normalize(v_world - cam_pos), cam_fwd);
	float clear = aim_clear * (1.0 - smoothstep(0.0014, 0.008, off_axis));
	// Eaten away (raggedly, by the noise) over the last metre before the beam's end.
	float past = smoothstep(beam_len - 1.2, beam_len, dot(frag_world - beam_origin, beam_dir));
	float thr = 0.08 + v_age * v_age * 0.75 + cam * 0.9 + (1.0 - fade) * 0.8 + clear + past * 1.6;
	float alpha = step(thr, body);
	vec3 col;
	if (flame) {
		col = INF_RED * 1.15;
		col = mix(col, INF_HOT * 1.3, step(thr + 0.34, body) * (1.0 - v_age));
	} else {
		// Cel light from above: an indigo crescent on the upper side, broken by noise.
		float patch = dot(c, vec2(0.35, -0.85)) + (inf_noise2(q * 0.9 + 40.0) - 0.5) * 0.7;
		col = mix(INF_BLACK, INF_INDIGO, step(0.32, patch));
		col = mix(col, INF_RED * 1.1, 1.0 - step(0.06, body - thr));
	}
	return vec4(col, alpha);
}

void fragment() {
	vec4 c = shade(UV, CAMERA_POSITION_WORLD, -INV_VIEW_MATRIX[2].xyz, COLOR.a, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
