// Shared by the simple black hole ("Fancy black hole" off): black_hole_lens.gdshader and
// black_hole_disk.gdshader. Cheap stand-ins for black_hole.gdshader's accretion disk – the
// same colours and streaming filaments, evaluated once per pixel instead of along a ray march.

uniform vec3 disk_hot : source_color = vec3(1.0, 0.93, 0.8);
uniform vec3 disk_warm : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 disk_cool : source_color = vec3(0.75, 0.22, 0.12);
uniform float disk_energy = 3.0;
uniform float disk_strength = 1.0;
uniform float disk_spin = 1.0;

// Sine-free hash (the sin() hash turns blocky at large coordinates).
float bhl_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float bhl_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(bhl_hash(i), bhl_hash(i + vec3(1, 0, 0)), f.x), mix(bhl_hash(i + vec3(0, 1, 0)), bhl_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(bhl_hash(i + vec3(0, 0, 1)), bhl_hash(i + vec3(1, 0, 1)), f.x), mix(bhl_hash(i + vec3(0, 1, 1)), bhl_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Disk matter at polar angle a and log-radius coordinate lr: (body 0..1.5, filaments).
vec2 bhl_pattern(float a, float lr, float seed) {
	vec2 c = vec2(cos(a), sin(a));
	float body = bhl_noise(vec3(c * 2.5, lr * 9.0 + seed)) * 0.65 + bhl_noise(vec3(c * 5.0, lr * 18.0 + seed + 4.0)) * 0.35;
	float lanes = smoothstep(0.25, 0.65, bhl_noise(vec3(c * 4.0, lr * 22.0 + seed * 2.0)));
	float n1 = bhl_noise(vec3(c * 3.0, lr * 70.0 + seed));
	float streak = pow(1.0 - abs(n1 * 2.0 - 1.0), 10.0);
	return vec2(clamp(0.25 + 1.2 * body * lanes, 0.0, 1.5), streak * (0.45 + 0.55 * lanes));
}

// Keplerian streaming: two copies of the pattern advect on staggered cycles and cross-fade,
// so it keeps flowing round without winding up into rings. r in horizon radii.
vec2 bhl_flow(float ang, float r, float inner, float seed) {
	float omega = disk_spin * 2.4 * pow(max(r / inner, 0.3), -1.5);
	float period = 2.6;
	float c1 = fract(TIME / period);
	float c2 = fract(TIME / period + 0.5);
	float w1 = 1.0 - abs(c1 * 2.0 - 1.0);
	float lr = log(max(r, 0.1));
	return mix(bhl_pattern(ang - omega * c2 * period, lr, seed + 17.0), bhl_pattern(ang - omega * c1 * period, lr, seed), w1);
}

// Temperature falls outwards: white-hot -> gold -> deep red (u = 0 inner edge .. 1 outer).
vec3 bhl_color(float u) {
	vec3 col = mix(disk_hot, disk_warm, smoothstep(0.0, 0.3, u));
	return mix(col, disk_cool, smoothstep(0.3, 1.0, u));
}
