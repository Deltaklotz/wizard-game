shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
// One layer of the Infernal Torrent's cone (InfernoBeam), drawn as a cel-shaded shell: hard-edged
// shapes cut from noise with an alpha scissor (opaque pipeline, so the nested layers sort
// themselves by depth).
//   layer 0: black smoke with indigo patches and burning red edges (outermost)
//   layer 1: crimson flame with hot pink tongues
//   layer 2: white-pink core streaks near the muzzle
// The mesh is a unit tube (UV.x = angle 0..1, UV.y = 0..1 along); the vertex shader lays it
// along -Z to `length_m` with the cone radius r0 + spread * d, billowing with noise, and closes
// it in a rounded head. The noise lives in log-radius coordinates along the cone, so the shapes
// grow with the beam and stream outwards like an expanding jet.

#include "res://shaders/vfx/inferno_common.gdshaderinc"

uniform int layer = 0;
uniform float length_m = 10.0;
uniform float r0 = 0.35;
uniform float spread = 0.17;
uniform float radius_scale = 1.0;
// 0..1: the beam's strength (erodes the shapes as it falls).
uniform float intensity = 1.0;
// Metres cut off at the muzzle end (the tail flies off when the beam ends).
uniform float cut = 0.0;
// 1 = the beam ends in the air (the head dissolves), 0 = it ends in a surface.
uniform float open_end = 1.0;
// Erodes the shapes within these distances of the camera (the caster's own view).
uniform vec2 near_fade = vec2(1.5, 7.0);
// Extra erosion of the inner side of the cone (seen from inside it) and around the centre of
// the view - the caster has to see what they are burning.
uniform float inside_erode = 0.0;
uniform float aim_clear = 0.0;
uniform float flow = 2.6;
uniform float seed = 0.0;

varying float v_ang;
varying float v_xi;
varying float v_d;
varying float v_s;
varying vec3 v_world;
varying float v_up;
varying vec3 v_out;

float xi_of(float d) {
	return log((r0 + spread * d) / r0) / spread;
}

void vertex() {
	float s = UV.y;
	float d = s * length_m;
	float ang = UV.x * TAU;
	float xi = xi_of(d);
	float r = (r0 + spread * d) * radius_scale;
	// Rounded head: the radius closes over roughly one radius before the end.
	float head = clamp((length_m - d) / max(r * 0.9, 0.05), 0.0, 1.0);
	r *= sqrt(1.0 - (1.0 - head) * (1.0 - head));
	// Billowing lumps streaming outwards (and twisting a little).
	float t = TIME * flow;
	float spin = ang + TIME * 0.6 + xi * 0.25;
	float bulge = inf_noise3(vec3(cos(spin) * 1.3, sin(spin) * 1.3, xi * 0.55 - t * 0.55 + seed)) * 0.65
		+ inf_noise3(vec3(cos(spin) * 3.1, sin(spin) * 3.1, xi * 1.2 - t * 1.1 + seed + 7.0)) * 0.35;
	r *= 0.7 + 0.7 * bulge * smoothstep(0.0, 2.0, d);
	VERTEX = vec3(cos(ang) * r, sin(ang) * r, -d);
	NORMAL = normalize(vec3(cos(ang), sin(ang), spread));
	v_ang = ang;
	v_xi = xi;
	v_d = d;
	v_s = s;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_out = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_up = v_out.y;
}

vec4 shade(vec3 cam_pos, vec3 cam_fwd) {
	float t = TIME * flow;
	float spin = v_ang + TIME * (0.9 + 0.4 * float(layer)) + v_xi * 0.35;
	vec2 ring = vec2(cos(spin), sin(spin));
	float along = v_xi;
	vec3 p;
	if (layer == 2) {
		// Core: streaks stretched along the flow.
		p = vec3(ring * 2.6, along * 0.35 - t * 1.6 + seed);
	} else {
		// Shapes stretched along the flow (streaming tongues and wisps).
		p = vec3(ring * 3.0, along * 0.75 - t + seed + float(layer) * 13.0);
	}
	vec3 warp = vec3(inf_noise3(p * 0.6 + 3.1), inf_noise3(p * 0.6 + 17.7), 0.0) - 0.5;
	float dens = inf_fbm3(p + warp * 1.6);

	// Shared erosion: weakening beam, the tail cut off, a dissolving head in the air, and the
	// caster's own camera.
	float erode = (1.0 - intensity) * 0.75;
	float cam = 1.0 - smoothstep(near_fade.x, near_fade.y, distance(v_world, cam_pos));
	erode += cam * 0.9;
	erode += open_end * smoothstep(0.72, 1.0, v_s) * 0.55;
	erode += (1.0 - smoothstep(cut, cut + 6.0 + cut * 0.3, v_d)) * step(0.001, cut);
	vec3 to_cam = cam_pos - v_world;
	erode += inside_erode * step(dot(v_out, to_cam), 0.0);
	float off_axis = 1.0 - dot(normalize(-to_cam), cam_fwd);
	erode += aim_clear * (1.0 - smoothstep(0.0014, 0.008, off_axis));

	vec3 col;
	float a;
	if (layer == 0) {
		// Smoke: sparse right at the muzzle, thickening further out.
		float thr = 0.56 - 0.08 * smoothstep(0.04, 0.45, v_s) + 0.35 * (1.0 - smoothstep(1.5, 9.0, v_d)) + erode;
		a = step(thr, dens);
		float patch = inf_noise3(p * 0.7 + vec3(4.0, 9.0, 2.0)) * 0.8 + v_up * 0.45;
		col = mix(INF_BLACK, INF_INDIGO, step(0.66, patch));
		// Smouldering red where the flame shines through thin smoke, and burning edges.
		float smoulder = step(0.66, inf_noise3(p * 1.3 + 31.0));
		col = mix(col, INF_RED * 0.18, smoulder * (1.0 - step(0.66, patch)));
		col = mix(col, INF_RED * 1.1, 1.0 - step(0.035 + 0.02 * v_s, dens - thr));
	} else if (layer == 1) {
		float thr = 0.4 + 0.16 * smoothstep(0.45, 1.0, v_s) + erode;
		a = step(thr, dens);
		col = INF_RED * 1.15;
		col = mix(col, INF_HOT * 1.3, step(thr + 0.28, dens));
	} else {
		float thr = 0.44 + 0.5 * smoothstep(0.0, 0.55, v_s) + erode;
		a = step(thr, dens);
		col = mix(INF_HOT * 1.4, INF_PALE * 1.7, step(thr + 0.14, dens));
	}
	return vec4(col, a);
}

void fragment() {
	vec4 c = shade(CAMERA_POSITION_WORLD, -INV_VIEW_MATRIX[2].xyz);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
