// Shared helpers of the Infernal Torrent (InfernoBeam): hash/noise, the palette, and the cone
// the beam's shells and particles live in.

// Palette (linear): crimson flame, hot pink core, black smoke, indigo smoke patches, pale rose.
const vec3 INF_RED = vec3(1.0, 0.035, 0.055);
const vec3 INF_HOT = vec3(1.0, 0.16, 0.22);
const vec3 INF_PALE = vec3(1.0, 0.55, 0.6);
const vec3 INF_BLACK = vec3(0.006, 0.003, 0.008);
const vec3 INF_INDIGO = vec3(0.026, 0.013, 0.17);
const vec3 INF_ROSE = vec3(1.0, 0.66, 0.74);

// Sine-free hash: stays random at large coordinates (the sin() hash turned blocky there).
float inf_hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float inf_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float inf_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(inf_hash3(i), inf_hash3(i + vec3(1, 0, 0)), f.x);
	float b = mix(inf_hash3(i + vec3(0, 1, 0)), inf_hash3(i + vec3(1, 1, 0)), f.x);
	float c = mix(inf_hash3(i + vec3(0, 0, 1)), inf_hash3(i + vec3(1, 0, 1)), f.x);
	float d = mix(inf_hash3(i + vec3(0, 1, 1)), inf_hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float inf_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(inf_hash2(i), inf_hash2(i + vec2(1, 0)), f.x),
		mix(inf_hash2(i + vec2(0, 1)), inf_hash2(i + vec2(1, 1)), f.x), f.y);
}

float inf_fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * inf_noise3(p);
		p = p * 2.07 + vec3(5.3, 1.7, 9.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

float inf_fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * inf_noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Hard cel edge with a pixel-wide anti-aliased transition.
float inf_cel(float v, float threshold) {
	float w = max(fwidth(v), 0.002);
	return smoothstep(threshold - w, threshold + w, v);
}
