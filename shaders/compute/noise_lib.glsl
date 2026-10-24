// Shared noise library for compute shaders.
// Every function takes a seed; functions with a `period` argument tile exactly
// with that lattice period (period <= 0 disables wrapping).

uint hash_u(uint x) {
	x ^= x >> 16;
	x *= 0x7feb352dU;
	x ^= x >> 15;
	x *= 0x846ca68bU;
	x ^= x >> 16;
	return x;
}

uint hash2u(ivec2 p, uint seed) {
	return hash_u(uint(p.x) * 1597334677U ^ hash_u(uint(p.y) * 3812015801U ^ seed));
}

float hash2f(ivec2 p, uint seed) {
	return float(hash2u(p, seed) & 0x00FFFFFFU) / 16777215.0;
}

vec2 hash2v(ivec2 p, uint seed) {
	uint h = hash2u(p, seed);
	return vec2(float(h & 0xFFFFU), float(h >> 16)) / 65535.0;
}

ivec2 wrap_cell(ivec2 c, ivec2 period) {
	// GLSL leaves % undefined for negative operands, so use floored division.
	if (period.x > 0) {
		c.x -= period.x * int(floor(float(c.x) / float(period.x)));
	}
	if (period.y > 0) {
		c.y -= period.y * int(floor(float(c.y) / float(period.y)));
	}
	return c;
}

vec2 grad2(ivec2 p, uint seed) {
	float a = hash2f(p, seed) * 6.28318530718;
	return vec2(cos(a), sin(a));
}

// Gradient noise in roughly [-1, 1].
float gnoise_p(vec2 x, ivec2 period, uint seed) {
	ivec2 i = ivec2(floor(x));
	vec2 f = x - vec2(i);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad2(wrap_cell(i, period), seed), f);
	float b = dot(grad2(wrap_cell(i + ivec2(1, 0), period), seed), f - vec2(1.0, 0.0));
	float c = dot(grad2(wrap_cell(i + ivec2(0, 1), period), seed), f - vec2(0.0, 1.0));
	float d = dot(grad2(wrap_cell(i + ivec2(1, 1), period), seed), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.41421356;
}

float gnoise(vec2 x, uint seed) {
	return gnoise_p(x, ivec2(0), seed);
}

// Fractal sum. Period doubles with frequency so every octave still tiles.
float fbm_p(vec2 x, ivec2 period, int octaves, float gain, uint seed) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		sum += amp * gnoise_p(x, period, seed + uint(o) * 1013U);
		norm += amp;
		x *= 2.0;
		period *= 2;
		amp *= gain;
	}
	return sum / norm;
}

float fbm(vec2 x, int octaves, float gain, uint seed) {
	return fbm_p(x, ivec2(0), octaves, gain, seed);
}

// Ridged multifractal in [0, 1]; sharp crests, the classic mountain-range look.
float ridged(vec2 x, int octaves, float gain, uint seed) {
	float sum = 0.0;
	float amp = 0.5;
	float weight = 1.0;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		float n = 1.0 - abs(gnoise(x, seed + uint(o) * 7919U));
		n *= n;
		n *= weight;
		weight = clamp(n * 2.0, 0.0, 1.0);
		sum += n * amp;
		norm += amp;
		x = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * x;
		amp *= gain;
	}
	return sum / norm;
}

// Worley / cellular noise. Returns (F1, F2, cell hash in [0,1], unused).
vec4 worley_p(vec2 x, ivec2 period, float jitter, uint seed) {
	ivec2 i = ivec2(floor(x));
	vec2 f = x - vec2(i);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			ivec2 o = ivec2(xx, y);
			ivec2 c = wrap_cell(i + o, period);
			vec2 pt = vec2(o) + 0.5 + (hash2v(c, seed) - 0.5) * jitter;
			float d = length(pt - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash2f(c, seed ^ 0x9E3779B9U);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec4(f1, f2, id, 0.0);
}
