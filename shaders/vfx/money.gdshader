shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Money Rain (MoneyRain.gd) particles: a fluttering banknote (green paper, border, portrait
// oval, corner marks). Fades out by the particle COLOR.a (dithered).

uniform vec3 paper : source_color = vec3(0.55, 0.78, 0.5);
uniform vec3 ink : source_color = vec3(0.12, 0.32, 0.16);

varying float v_seed;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	// Flutter: tip about the note's long axis and curl it a little.
	float a = 1.1 + sin(TIME * (5.0 + v_seed * 4.0) + v_seed * 20.0) * 0.7;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(VERTEX.x, VERTEX.y * c - VERTEX.z * s, VERTEX.y * s + VERTEX.z * c);
	VERTEX.y += sin(VERTEX.x * 9.0 + TIME * 8.0 + v_seed * 6.0) * 0.025;
	NORMAL = vec3(0.0, -s, c);
}

float box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// Dithered fade-out by the particle alpha.
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	if (COLOR.a < dither) {
		discard;
	}
	vec2 p = c * vec2(1.0, 0.5);
	float border = smoothstep(0.02, 0.0, abs(box(p, vec2(0.86, 0.38)))) + smoothstep(0.015, 0.0, abs(box(p, vec2(0.8, 0.33)))) * 0.7;
	float oval = smoothstep(0.03, 0.0, abs(length(p / vec2(0.2, 0.26)) - 1.0) * 0.2);
	float face = smoothstep(1.0, 0.8, length((p - vec2(0.0, 0.02)) / vec2(0.1, 0.14))) * 0.6;
	float marks = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 corner = vec2(i % 2 == 0 ? -0.66 : 0.66, i < 2 ? -0.2 : 0.2);
		marks += smoothstep(0.07, 0.04, length(p - corner)) * 0.8;
	}
	float lines = smoothstep(0.4, 0.5, sin(p.x * 90.0)) * step(0.45, abs(p.x)) * step(abs(p.y), 0.25) * 0.25;
	float ink_amt = clamp(border + oval + face + marks + lines, 0.0, 1.0);
	ALBEDO = mix(paper, ink, ink_amt * 0.85);
	ROUGHNESS = 0.85;
	EMISSION = paper * 0.15;
}
