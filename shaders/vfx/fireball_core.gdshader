shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The fireball itself (Fireball): a camera-facing ball of roiling fire. Swirling noise spins
// round a white-hot heart, fading through yellow and orange into a deep red rim with flame
// tongues flickering out of its edge.

uniform float energy = 3.0;
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.7);
uniform vec3 mid : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 edge : source_color = vec3(0.85, 0.15, 0.04);

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float t = TIME;
	// Swirl: angle advances with time, faster inside.
	float sw = a + t * 2.5 + (1.0 - r) * 3.0;
	float n = fbm(vec2(cos(sw), sin(sw)) * 1.6 + vec2(r * 3.0 - t * 1.5, t * 0.7));
	// Flame tongues lick out of the rim.
	float tongues = fbm(vec2(a * 2.5 + t * 1.5, r * 4.0 - t * 4.0));
	float radius = 0.55 + 0.25 * tongues;
	float body = 1.0 - smoothstep(radius - 0.25, radius, r - (n - 0.5) * 0.25);
	float heat = clamp(1.0 - r / radius + (n - 0.5) * 0.6, 0.0, 1.0);
	vec3 col = mix(edge, mid, smoothstep(0.0, 0.45, heat));
	col = mix(col, hot, smoothstep(0.45, 0.85, heat));
	col += hot * exp(-r * r * 30.0) * 1.5;
	float halo = exp(-r * r * 3.0) * 0.25;
	ALBEDO = (col * body + mid * halo) * energy;
	ALPHA = clamp(body + halo, 0.0, 1.0);
}
