#[compute]
#version 450

// Bakes procedural material textures. Tiling materials only use lattice-periodic
// noise (period = integer multiple of the texture), so they wrap seamlessly.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer AlbedoBuf { uint albedo_out[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer NormalBuf { uint normal_out[]; };

layout(push_constant, std430) uniform Params {
	int size;
	int mode;
	float normal_strength;
	float pad;
} pc;

#include "noise_lib.glsl"

#define MODE_GRASS 0
#define MODE_ROCK 1
#define MODE_DIRT 2
#define MODE_SNOW 3
#define MODE_BARK_OAK 4
#define MODE_BARK_PINE 5
#define MODE_LEAVES 6
#define MODE_NEEDLES 7
#define MODE_MACRO 8
#define MODE_MOSS 9
#define MODE_DETAIL 10
#define MODE_WATER 11

float saturate(float x) { return clamp(x, 0.0, 1.0); }

// Stretched worley blob used for blades of grass. M is an integer matrix so tiling survives.
float blade_layer(vec2 uv, mat2 m, vec2 freq, uint seed) {
	vec2 p = (m * uv) * freq;
	vec4 w = worley_p(p, ivec2(freq), 0.9, seed);
	return pow(saturate(1.0 - w.x * 1.35), 1.5) * (0.55 + 0.45 * w.z);
}

void mat_grass(vec2 uv, out vec3 col, out float h) {
	vec2 warp = vec2(fbm_p(uv * 6.0, ivec2(6), 3, 0.5, 5U), fbm_p(uv * 6.0, ivec2(6), 3, 0.5, 6U)) * 0.012;
	vec2 q = uv + warp;
	float b = 0.0;
	b = max(b, blade_layer(q, mat2(1.0, 0.0, 0.0, 1.0), vec2(64.0, 13.0), 101U));
	b = max(b, blade_layer(q, mat2(0.0, 1.0, 1.0, 0.0), vec2(60.0, 12.0), 102U));
	b = max(b, blade_layer(q, mat2(1.0, 1.0, -1.0, 1.0), vec2(44.0, 10.0), 103U));
	b = max(b, blade_layer(q, mat2(1.0, -1.0, 1.0, 1.0), vec2(46.0, 9.0), 104U));
	float fine = fbm_p(uv * 48.0, ivec2(48), 3, 0.5, 107U) * 0.5 + 0.5;
	float base = fbm_p(uv * 4.0, ivec2(4), 5, 0.55, 11U) * 0.5 + 0.5;
	float dry = smoothstep(0.55, 0.8, fbm_p(uv * 3.0, ivec2(3), 4, 0.5, 23U) * 0.5 + 0.5);

	vec3 soil = vec3(0.17, 0.15, 0.08);
	vec3 low = vec3(0.12, 0.2, 0.05);
	vec3 mid = vec3(0.25, 0.37, 0.1);
	vec3 tip = vec3(0.42, 0.52, 0.18);
	vec3 straw = vec3(0.5, 0.45, 0.24);
	float cover = smoothstep(0.02, 0.25, b + fine * 0.15);
	col = mix(soil, low, cover);
	col = mix(col, mid, smoothstep(0.2, 0.6, b));
	col = mix(col, tip, smoothstep(0.6, 1.0, b) * (0.6 + 0.4 * base));
	col = mix(col, col * vec3(1.15, 1.05, 0.75) + straw * 0.25, dry * 0.6);
	col *= 0.85 + 0.3 * base;

	// Sparse tiny flowers.
	vec4 fw = worley_p(uv * 22.0, ivec2(22), 0.8, 131U);
	if (fw.z > 0.965 && fw.x < 0.07) {
		col = mix(col, fw.z > 0.985 ? vec3(0.92, 0.88, 0.55) : vec3(0.85, 0.85, 0.9), smoothstep(0.07, 0.03, fw.x));
	}
	h = saturate(b * 0.8 + fine * 0.2);
}

void mat_rock(vec2 uv, out vec3 col, out float h) {
	vec2 warp = vec2(fbm_p(uv * 4.0, ivec2(4), 5, 0.5, 31U), fbm_p(uv * 4.0, ivec2(4), 5, 0.5, 32U)) * 0.06;
	vec2 q = uv + warp;
	vec4 w1 = worley_p(q * 4.0, ivec2(4), 1.0, 33U);
	vec4 w2 = worley_p(q * 11.0 + warp * 6.0, ivec2(11), 1.0, 34U);
	float crack1 = smoothstep(0.0, 0.035, w1.y - w1.x);
	float crack2 = smoothstep(0.0, 0.025, w2.y - w2.x);
	float rough = fbm_p(uv * 6.0, ivec2(6), 7, 0.58, 35U) * 0.5 + 0.5;
	float grain = fbm_p(uv * 64.0, ivec2(64), 3, 0.6, 36U) * 0.5 + 0.5;
	float tone = fbm_p(uv * 2.0, ivec2(2), 4, 0.5, 39U) * 0.5 + 0.5;
	float strata = sin((q.y * 7.0 + rough * 0.9) * 6.28318) * 0.5 + 0.5;

	// Faceted surface: each plate tilts a bit, fbm gives the rough breakage.
	float facet = w1.x * (w1.z - 0.5) * 0.35;
	h = 0.3 + w1.z * 0.15 + rough * 0.45 + grain * 0.07 + strata * 0.08 + facet;
	h *= mix(0.45, 1.0, crack1) * mix(0.8, 1.0, crack2);
	h = saturate(h);

	vec3 warm = vec3(0.46, 0.42, 0.37);
	vec3 cool = vec3(0.37, 0.38, 0.39);
	col = mix(cool, warm, tone * 0.7 + w1.z * 0.3);
	col *= 0.7 + 0.45 * rough + 0.12 * grain;
	col = mix(col, col * vec3(0.88, 0.84, 0.78), strata * 0.35);
	col *= mix(0.45, 1.0, crack1) * mix(0.75, 1.0, crack2);
	vec4 lw = worley_p(uv * 36.0, ivec2(36), 0.9, 37U);
	float lichen_mask = smoothstep(0.5, 0.72, fbm_p(uv * 4.0, ivec2(4), 3, 0.5, 38U) * 0.5 + 0.5);
	float spot = smoothstep(0.45, 0.25, lw.x) * step(0.45, lw.z) * lichen_mask * crack1;
	col = mix(col, lw.z > 0.8 ? vec3(0.6, 0.48, 0.28) : vec3(0.5, 0.53, 0.36), spot * 0.7);
}

void mat_dirt(vec2 uv, out vec3 col, out float h) {
	float base = fbm_p(uv * 6.0, ivec2(6), 6, 0.55, 51U) * 0.5 + 0.5;
	float clumps = fbm_p(uv * 20.0, ivec2(20), 3, 0.5, 52U) * 0.5 + 0.5;
	col = mix(vec3(0.24, 0.17, 0.11), vec3(0.4, 0.31, 0.21), base);
	col *= 0.85 + 0.25 * clumps;
	h = base * 0.35 + clumps * 0.2;

	vec4 p1 = worley_p(uv * 26.0, ivec2(26), 0.9, 53U);
	float r1 = 0.18 + 0.2 * p1.z;
	if (p1.z > 0.35 && p1.x < r1) {
		float dome = sqrt(saturate(1.0 - (p1.x / r1) * (p1.x / r1)));
		vec3 stone = mix(vec3(0.36, 0.34, 0.31), vec3(0.52, 0.47, 0.4), fract(p1.z * 17.0));
		col = mix(col, stone * (0.75 + 0.35 * dome), smoothstep(r1, r1 - 0.05, p1.x));
		h = max(h, 0.45 + dome * 0.5);
	}
	vec4 p2 = worley_p(uv * 70.0, ivec2(70), 0.9, 54U);
	float r2 = 0.22 + 0.15 * p2.z;
	if (p2.z > 0.55 && p2.x < r2) {
		float dome = sqrt(saturate(1.0 - (p2.x / r2) * (p2.x / r2)));
		col = mix(col, vec3(0.42, 0.38, 0.33) * (0.75 + 0.3 * dome), smoothstep(r2, r2 - 0.08, p2.x) * 0.8);
		h = max(h, 0.35 + dome * 0.3);
	}
	// Dark organic specks.
	vec4 sp = worley_p(uv * 90.0, ivec2(90), 1.0, 55U);
	col *= 1.0 - 0.35 * step(0.9, sp.z) * smoothstep(0.25, 0.1, sp.x);
	h = saturate(h);
}

void mat_snow(vec2 uv, out vec3 col, out float h) {
	float drift = fbm_p(uv * 3.0, ivec2(3), 5, 0.5, 61U) * 0.5 + 0.5;
	float fine = fbm_p(uv * 24.0, ivec2(24), 4, 0.55, 62U) * 0.5 + 0.5;
	h = drift * 0.7 + fine * 0.3;
	col = mix(vec3(0.72, 0.78, 0.88), vec3(0.95, 0.96, 0.98), smoothstep(0.2, 0.8, h));
	vec4 s = worley_p(uv * 120.0, ivec2(120), 1.0, 63U);
	col += vec3(0.05) * step(0.93, s.z) * smoothstep(0.2, 0.0, s.x);
}

void mat_bark(vec2 uv, bool pine, out vec3 col, out float h) {
	vec2 warp = vec2(fbm_p(uv * vec2(4.0, 2.0), ivec2(4, 2), 4, 0.5, 71U), fbm_p(uv * vec2(4.0, 2.0), ivec2(4, 2), 4, 0.5, 72U));
	if (pine) {
		vec2 q = uv + warp * vec2(0.03, 0.02);
		vec4 w = worley_p(q * vec2(7.0, 5.0), ivec2(7, 5), 0.9, 73U);
		float gap = smoothstep(0.0, 0.12, w.y - w.x);
		float flake = fbm_p(uv * vec2(24.0, 16.0), ivec2(24, 16), 4, 0.55, 74U) * 0.5 + 0.5;
		h = gap * (0.55 + 0.25 * w.z + 0.2 * flake);
		col = mix(vec3(0.08, 0.05, 0.04), mix(vec3(0.3, 0.2, 0.14), vec3(0.42, 0.3, 0.22), w.z), gap);
		col *= 0.8 + 0.35 * flake;
	} else {
		vec2 q = uv + warp * vec2(0.04, 0.01);
		vec4 w = worley_p(q * vec2(10.0, 2.0), ivec2(10, 2), 1.0, 75U);
		float fissure = smoothstep(0.0, 0.22, w.y - w.x);
		float fib = fbm_p(uv * vec2(40.0, 6.0), ivec2(40, 6), 4, 0.55, 76U) * 0.5 + 0.5;
		h = fissure * (0.6 + 0.4 * fib);
		col = mix(vec3(0.1, 0.08, 0.06), mix(vec3(0.3, 0.25, 0.2), vec3(0.42, 0.37, 0.3), fib), fissure);
		float moss = smoothstep(0.55, 0.75, fbm_p(uv * 3.0, ivec2(3), 4, 0.5, 77U) * 0.5 + 0.5);
		col = mix(col, vec3(0.28, 0.34, 0.14), moss * fissure * 0.7);
	}
	h = saturate(h);
}

void mat_moss(vec2 uv, out vec3 col, out float h) {
	vec4 w = worley_p(uv * 30.0, ivec2(30), 1.0, 81U);
	float tuft = pow(saturate(1.0 - w.x * 1.3), 0.8);
	float base = fbm_p(uv * 5.0, ivec2(5), 5, 0.55, 82U) * 0.5 + 0.5;
	float fine = fbm_p(uv * 80.0, ivec2(80), 2, 0.5, 83U) * 0.5 + 0.5;
	h = tuft * 0.7 + fine * 0.3;
	col = mix(vec3(0.09, 0.15, 0.04), vec3(0.3, 0.42, 0.1), h);
	col *= 0.8 + 0.4 * base;
}

// Height detail for close-range ground displacement (linear data, not colour):
// R = soil bumps and clods, G = fractured stone relief, B = micro roughness.
void mat_detail(vec2 uv, out vec3 col) {
	float soil = fbm_p(uv * 5.0, ivec2(5), 5, 0.55, 101U) * 0.5 + 0.5;
	vec4 clod = worley_p(uv * 22.0, ivec2(22), 0.9, 102U);
	soil = soil * 0.75 + (1.0 - smoothstep(0.0, 0.7, clod.x)) * 0.25 * clod.z;
	vec2 w = vec2(fbm_p(uv * 4.0, ivec2(4), 3, 0.5, 103U), fbm_p(uv * 4.0, ivec2(4), 3, 0.5, 104U)) * 0.05;
	vec4 plates = worley_p((uv + w) * 6.0, ivec2(6), 1.0, 105U);
	float crack = smoothstep(0.0, 0.08, plates.y - plates.x);
	float ridge = 1.0 - abs(fbm_p(uv * 7.0, ivec2(7), 5, 0.5, 106U));
	float stone = (ridge * ridge * 0.6 + plates.z * 0.4) * mix(0.35, 1.0, crack);
	float micro = fbm_p(uv * 40.0, ivec2(40), 3, 0.6, 107U) * 0.5 + 0.5;
	col = vec3(soil, saturate(stone), micro);
}

// Small wind-driven wave heights for the water normal map.
void mat_water(vec2 uv, out vec3 col, out float h) {
	vec2 w = vec2(fbm_p(uv * 3.0, ivec2(3), 3, 0.5, 111U), fbm_p(uv * 3.0, ivec2(3), 3, 0.5, 112U)) * 0.08;
	float a = fbm_p((uv + w) * vec2(6.0, 4.0), ivec2(6, 4), 5, 0.55, 113U);
	float b = fbm_p((uv - w) * vec2(4.0, 7.0), ivec2(4, 7), 4, 0.5, 114U);
	float ripple = 1.0 - abs(fbm_p(uv * 12.0, ivec2(12), 3, 0.5, 115U));
	h = (a * 0.5 + b * 0.35) * 0.5 + 0.5 + ripple * ripple * 0.15;
	col = vec3(h);
}

// --- Foliage cards (not tiling; alpha is coverage) --------------------------

float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

void mat_leaves(vec2 uv, out vec3 col, out float alpha, out float h) {
	col = vec3(0.0);
	alpha = 0.0;
	h = 0.0;
	float aa = 1.5 / float(pc.size);
	// Main twig from bottom-center upwards, slightly curved.
	vec2 twig_a = vec2(0.5, 0.99);
	vec2 twig_b = vec2(0.47, 0.18);
	float tt;
	float td = seg_dist(uv, twig_a, twig_b, tt);
	float tw = mix(0.012, 0.004, tt);
	if (td < tw) {
		col = vec3(0.25, 0.18, 0.1);
		alpha = smoothstep(tw, tw - aa, td);
		h = 0.3;
	}
	const int LEAVES = 26;
	for (int i = 0; i < LEAVES; i++) {
		uint s = uint(i) * 7349U + 17U;
		float fi = float(i) / float(LEAVES - 1);
		float side = (i % 2 == 0) ? 1.0 : -1.0;
		vec2 base = mix(twig_a, twig_b, 0.12 + fi * 0.88);
		float ang = radians(-90.0 + side * mix(70.0, 25.0, fi) + (hash2f(ivec2(i, 1), s) - 0.5) * 40.0);
		float len = mix(0.3, 0.17, fi) * (0.85 + 0.3 * hash2f(ivec2(i, 2), s));
		float wid = len * (0.2 + 0.08 * hash2f(ivec2(i, 3), s));
		vec2 dir = vec2(cos(ang), sin(ang));
		// Short petiole before the blade starts.
		vec2 start = base + dir * 0.025;
		float pt;
		float pd = seg_dist(uv, base, start, pt);
		if (pd < 0.003) {
			col = vec3(0.3, 0.3, 0.12);
			alpha = max(alpha, smoothstep(0.003, 0.003 - aa, pd));
			h = 0.35;
		}
		vec2 d = uv - start;
		float t = dot(d, dir) / len;
		float sdist = dot(d, vec2(-dir.y, dir.x));
		if (t < 0.0 || t > 1.0) {
			continue;
		}
		float halfw = wid * pow(sin(3.14159 * pow(t, 0.8)), 0.75);
		float edge = halfw - abs(sdist);
		if (edge <= 0.0) {
			continue;
		}
		float s_n = sdist / max(halfw, 1e-4);
		float hue = hash2f(ivec2(i, 4), s);
		vec3 leaf = mix(vec3(0.16, 0.3, 0.06), vec3(0.32, 0.45, 0.1), hue);
		leaf = mix(leaf, vec3(0.45, 0.42, 0.12), step(0.9, hue) * 0.6);
		float vein = smoothstep(0.08, 0.0, abs(s_n)) * 0.6
			+ smoothstep(0.1, 0.0, abs(fract(t * 7.0 - abs(s_n) * 1.2) - 0.5) - 0.38) * 0.15;
		leaf *= 0.85 + 0.25 * t;
		leaf = mix(leaf, leaf * 1.4 + 0.04, vein);
		leaf *= mix(0.7, 1.0, smoothstep(0.0, 0.3, edge / wid));
		col = leaf;
		alpha = max(alpha, smoothstep(0.0, aa, edge));
		h = 0.5 + 0.35 * (1.0 - s_n * s_n) + vein * 0.1;
	}
}

void mat_needles(vec2 uv, out vec3 col, out float alpha, out float h) {
	col = vec3(0.0);
	alpha = 0.0;
	h = 0.0;
	float aa = 1.5 / float(pc.size);
	// Twig runs left to right along the card with a slight arc.
	float twig_y = 0.5 + 0.05 * sin(uv.x * 3.14159);
	float td = abs(uv.y - twig_y);
	float tw = mix(0.012, 0.004, uv.x);
	if (uv.x > 0.02 && uv.x < 0.97 && td < tw) {
		col = vec3(0.3, 0.2, 0.12);
		alpha = smoothstep(tw, tw - aa, td);
		h = 0.4;
	}
	float step_x = 0.011;
	int center = int(uv.x / step_x);
	for (int k = -24; k <= 2; k++) {
		int idx = center + k;
		float x0 = float(idx) * step_x;
		if (x0 < 0.03 || x0 > 0.95) {
			continue;
		}
		for (int side = 0; side < 2; side++) {
			float sg = side == 0 ? 1.0 : -1.0;
			uint s = uint(idx * 2 + side) * 2654435761U;
			float jitter = hash2f(ivec2(idx, side), s);
			float ang = radians(mix(38.0, 62.0, jitter));
			float len = mix(0.24, 0.12, smoothstep(0.6, 0.95, x0)) * (0.85 + 0.25 * hash2f(ivec2(idx, side + 5), s));
			vec2 a = vec2(x0, 0.5 + 0.05 * sin(x0 * 3.14159));
			vec2 b = a + vec2(cos(ang), sg * sin(ang)) * len;
			float t;
			float d = seg_dist(uv, a, b, t);
			float w = mix(0.0045, 0.0015, t);
			if (d < w) {
				vec3 nc = mix(vec3(0.07, 0.17, 0.08), vec3(0.2, 0.33, 0.14), jitter);
				nc *= 0.8 + 0.35 * t;
				col = nc;
				alpha = max(alpha, smoothstep(w, w - aa, d));
				h = 0.5 + 0.5 * (1.0 - d / w);
			}
		}
	}
}

void eval_mat(vec2 uv, out vec3 col, out float alpha, out float h) {
	alpha = 1.0;
	if (pc.mode == MODE_GRASS) {
		mat_grass(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_ROCK) {
		mat_rock(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_DIRT) {
		mat_dirt(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_SNOW) {
		mat_snow(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_BARK_OAK) {
		mat_bark(uv, false, col, h);
		alpha = h;
	} else if (pc.mode == MODE_BARK_PINE) {
		mat_bark(uv, true, col, h);
		alpha = h;
	} else if (pc.mode == MODE_LEAVES) {
		mat_leaves(uv, col, alpha, h);
	} else if (pc.mode == MODE_NEEDLES) {
		mat_needles(uv, col, alpha, h);
	} else if (pc.mode == MODE_WATER) {
		mat_water(uv, col, h);
	} else if (pc.mode == MODE_DETAIL) {
		mat_detail(uv, col);
		h = col.g;
	} else if (pc.mode == MODE_MOSS) {
		mat_moss(uv, col, h);
		alpha = h;
	} else {
		col = vec3(fbm_p(uv * 2.0, ivec2(2), 6, 0.55, 91U), fbm_p(uv * 5.0, ivec2(5), 5, 0.55, 92U),
				fbm_p(uv * 11.0, ivec2(11), 4, 0.55, 93U)) * 0.5 + 0.5;
		h = col.r;
	}
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= pc.size || px.y >= pc.size) {
		return;
	}
	float inv = 1.0 / float(pc.size);
	vec2 uv = (vec2(px) + 0.5) * inv;
	vec3 col;
	float alpha;
	float h;
	eval_mat(uv, col, alpha, h);
	vec3 c2;
	float a2;
	float hx;
	float hy;
	eval_mat(uv + vec2(inv, 0.0), c2, a2, hx);
	eval_mat(uv + vec2(0.0, inv), c2, a2, hy);
	vec3 n = normalize(vec3(-(hx - h) * pc.normal_strength, (hy - h) * pc.normal_strength, 1.0));
	uint i = uint(px.y * pc.size + px.x);
	albedo_out[i] = packUnorm4x8(vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0)));
	normal_out[i] = packUnorm4x8(vec4(n * 0.5 + 0.5, 1.0));
}
