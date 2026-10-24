shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Smoke puff particle (FireFx): soft, billowing, slowly turning dark grey blob; fades by COLOR.a.

uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float density = 0.75;

varying float v_seed;

// Sine-free hash: stays random at large coordinates (the sin() hash turned blocky there).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a = TIME * 0.3 + v_seed * 6.28;
	vec2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * c;
	float n = noise(r * 2.2 + v_seed * 11.0) * 0.6 + noise(r * 5.0 - v_seed * 3.0) * 0.4;
	float blob = 1.0 - smoothstep(0.35, 1.0, length(c) + (n - 0.5) * 0.6);
	// The particle colour lights the smoke: warm from the fire below, grey higher up.
	ALBEDO = tint * COLOR.rgb * (0.8 + 0.4 * n);
	ALPHA = clamp(blob * density * COLOR.a, 0.0, 1.0);
}
