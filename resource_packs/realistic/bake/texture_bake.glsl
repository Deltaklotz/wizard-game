#[compute]
#version 450

// "Realistic" resource pack: high-resolution material bake. Same outputs as the default
// baker (albedo RGB + height in alpha, tangent-space normal), but every material is built
// from scattered primitives (individual grass blades, pebbles, twigs, bark plates, moss
// tufts) layered by height, with true Voronoi crack edges, mineral grains, weathering and
// baked cavity occlusion. Each pixel is 2x2 supersampled; normals use central differences.
// Every noise and scatter lookup is lattice-periodic, so the textures tile seamlessly.
// The image is baked in horizontal strips (row_offset) to stay clear of GPU timeouts.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer AlbedoBuf { uint albedo_out[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer NormalBuf { uint normal_out[]; };

layout(push_constant, std430) uniform Params {
	int size;
	int mode;
	float normal_strength;
	int row_offset;
} pc;

#include "res://shaders/compute/noise_lib.glsl"

#define MODE_GRASS 0
#define MODE_ROCK 1
#define MODE_DIRT 2
#define MODE_SNOW 3
#define MODE_BARK_OAK 4
#define MODE_BARK_PINE 5
#define MODE_LEAVES 6
#define MODE_NEEDLES 7
#define MODE_MOSS 9
#define MODE_WATER 11

const float TAU = 6.28318530718;

float saturate(float x) { return clamp(x, 0.0, 1.0); }

float fbmp(vec2 uv, int f, int oct, float gain, uint seed) {
	return fbm_p(uv * float(f), ivec2(f), oct, gain, seed) * 0.5 + 0.5;
}

float fbmp2(vec2 uv, ivec2 f, int oct, float gain, uint seed) {
	return fbm_p(uv * vec2(f), f, oct, gain, seed) * 0.5 + 0.5;
}

vec2 warp(vec2 uv, int f, float amp, uint seed) {
	return vec2(fbm_p(uv * float(f), ivec2(f), 4, 0.5, seed), fbm_p(uv * float(f), ivec2(f), 4, 0.5, seed + 77U)) * amp;
}

// Voronoi with the exact distance to the nearest cell border (two-pass).
// Returns (border distance, cell id, F1).
vec3 voronoi_edge(vec2 x, ivec2 period, float jitter, uint seed) {
	ivec2 i = ivec2(floor(x));
	vec2 f = x - vec2(i);
	vec2 mr = vec2(0.0);
	ivec2 mc = ivec2(0);
	float md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int xx = -1; xx <= 1; xx++) {
			ivec2 o = ivec2(xx, y);
			vec2 r = vec2(o) + 0.5 + (hash2v(wrap_cell(i + o, period), seed) - 0.5) * jitter - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mc = o;
			}
		}
	}
	float edge = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int xx = -2; xx <= 2; xx++) {
			ivec2 o = mc + ivec2(xx, y);
			vec2 r = vec2(o) + 0.5 + (hash2v(wrap_cell(i + o, period), seed) - 0.5) * jitter - f;
			if (dot(mr - r, mr - r) > 1e-5) {
				edge = min(edge, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec3(edge, hash2f(wrap_cell(i + mc, period), seed ^ 0x9E3779B9U), sqrt(md));
}

// --- Scattered primitives ------------------------------------------------------------

// A layer of grass blades: `n` cells per side, two blades per cell with random direction,
// length, width and a slight curve. The top-most blade wins (height compositing).
void blade_layer(vec2 uv, int n, uint seed, float len, float wid, float h0, float h1,
		vec3 c_base, vec3 c_tip, float hue_var, float density, inout vec3 col, inout float h) {
	vec2 p = uv * float(n);
	ivec2 ci = ivec2(floor(p));
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			ivec2 c = ci + ivec2(dx, dy);
			ivec2 cw = wrap_cell(c, ivec2(n));
			for (int k = 0; k < 2; k++) {
				uint s = seed + uint(k) * 7919U;
				if (hash2f(cw, s + 11U) > density) {
					continue;
				}
				vec2 root = vec2(c) + hash2v(cw, s);
				float a = hash2f(cw, s ^ 0x51EDU) * TAU;
				float L = len * (0.6 + 0.7 * hash2f(cw, s + 3U));
				vec2 dir = vec2(cos(a), sin(a));
				vec2 d = p - root;
				float t = dot(d, dir) / L;
				if (t < 0.0 || t > 1.0) {
					continue;
				}
				float bend = (hash2f(cw, s + 5U) - 0.5) * 0.7 * L;
				float side = dot(d, vec2(-dir.y, dir.x)) - bend * t * t;
				float w = wid * (0.7 + 0.6 * hash2f(cw, s + 7U)) * pow(1.0 - t, 0.55) * smoothstep(0.0, 0.08, t + 0.02);
				if (abs(side) > w) {
					continue;
				}
				float sn = side / w;
				float bh = mix(h0, h1, t) * (0.75 + 0.25 * hash2f(cw, s + 9U)) + (1.0 - sn * sn) * 0.035;
				if (bh > h) {
					h = bh;
					float hue = hash2f(cw, s + 13U);
					vec3 bc = mix(c_base, c_tip, smoothstep(0.0, 1.0, t));
					bc *= 1.0 + (hue - 0.5) * hue_var;
					bc = mix(bc, bc * vec3(1.2, 1.08, 0.65), step(0.93, hue) * 0.7);
					// Rounded blade: darker edges, a faint lighter midrib.
					bc *= 0.78 + 0.3 * (1.0 - sn * sn);
					bc += vec3(0.025, 0.03, 0.01) * smoothstep(0.18, 0.0, abs(sn));
					col = bc;
				}
			}
		}
	}
}

// Stones: ellipses with a rounded dome, speckled surface and a soft contact shadow.
void pebble_layer(vec2 uv, int n, uint seed, float density, float rmin, float rmax, vec3 ca, vec3 cb,
		float hbase, float hscale, inout vec3 col, inout float h) {
	vec2 p = uv * float(n);
	ivec2 ci = ivec2(floor(p));
	float shadow = 1.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = ci + ivec2(dx, dy);
			ivec2 cw = wrap_cell(c, ivec2(n));
			if (hash2f(cw, seed + 1U) > density) {
				continue;
			}
			vec2 center = vec2(c) + 0.25 + hash2v(cw, seed) * 0.5;
			float r = mix(rmin, rmax, pow(hash2f(cw, seed + 2U), 1.5));
			float a = hash2f(cw, seed + 3U) * TAU;
			float aspect = 0.6 + 0.4 * hash2f(cw, seed + 4U);
			vec2 d = p - center;
			d = vec2(dot(d, vec2(cos(a), sin(a))), dot(d, vec2(-sin(a), cos(a)))) / vec2(1.0, aspect);
			// Irregular outline.
			float ang = atan(d.y, d.x);
			float wob = 1.0 + 0.12 * sin(ang * 3.0 + hash2f(cw, seed + 5U) * TAU) + 0.06 * sin(ang * 5.0 + a);
			float q = length(d) / (r * wob);
			if (q < 1.0) {
				float dome = sqrt(saturate(1.0 - q * q));
				float ph = hbase + dome * hscale * (0.6 + 0.8 * r / rmax);
				if (ph > h) {
					h = ph;
					float tone = hash2f(cw, seed + 6U);
					vec3 sc = mix(ca, cb, tone);
					sc = mix(sc, sc * vec3(1.15, 0.95, 0.8), step(0.8, tone) * 0.6);
					float speck = fbm_p(p * 6.0, ivec2(n * 6), 3, 0.6, seed + 8U) * 0.5 + 0.5;
					sc *= 0.9 + 0.2 * speck;
					sc *= 0.62 + 0.45 * dome;
					col = sc;
				}
			} else if (q < 1.45) {
				shadow = min(shadow, mix(0.55, 1.0, smoothstep(1.0, 1.45, q)));
			}
		}
	}
	col *= shadow;
}

// Thin twigs lying on the ground.
void twig_layer(vec2 uv, int n, uint seed, float density, inout vec3 col, inout float h) {
	vec2 p = uv * float(n);
	ivec2 ci = ivec2(floor(p));
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = ci + ivec2(dx, dy);
			ivec2 cw = wrap_cell(c, ivec2(n));
			if (hash2f(cw, seed + 1U) > density) {
				continue;
			}
			vec2 a = vec2(c) + hash2v(cw, seed);
			float ang = hash2f(cw, seed + 2U) * TAU;
			vec2 dir = vec2(cos(ang), sin(ang));
			float L = 0.5 + 0.5 * hash2f(cw, seed + 3U);
			vec2 d = p - a;
			float t = clamp(dot(d, dir) / L, 0.0, 1.0);
			float dist = length(d - dir * t * L - vec2(-dir.y, dir.x) * sin(t * 3.14159) * 0.06);
			float w = 0.035 * (1.0 - t * 0.5);
			if (dist < w) {
				float th = 0.32 + sqrt(saturate(1.0 - dist / w)) * 0.12;
				if (th > h) {
					h = th;
					col = mix(vec3(0.2, 0.14, 0.09), vec3(0.34, 0.26, 0.18), hash2f(cw, seed + 4U)) * (0.7 + 0.35 * (1.0 - dist / w));
				}
			} else if (dist < w * 2.5) {
				col *= mix(0.7, 1.0, smoothstep(w, w * 2.5, dist));
			}
		}
	}
}

// Fallen leaf fragments.
void litter_layer(vec2 uv, int n, uint seed, float density, inout vec3 col, inout float h) {
	vec2 p = uv * float(n);
	ivec2 ci = ivec2(floor(p));
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 c = ci + ivec2(dx, dy);
			ivec2 cw = wrap_cell(c, ivec2(n));
			if (hash2f(cw, seed + 1U) > density) {
				continue;
			}
			vec2 center = vec2(c) + hash2v(cw, seed);
			float ang = hash2f(cw, seed + 2U) * TAU;
			vec2 d = p - center;
			d = vec2(dot(d, vec2(cos(ang), sin(ang))), dot(d, vec2(-sin(ang), cos(ang))));
			float L = 0.35 + 0.25 * hash2f(cw, seed + 3U);
			float t = d.x / L;
			if (abs(t) > 1.0) {
				continue;
			}
			float halfw = L * 0.45 * sqrt(1.0 - t * t);
			if (abs(d.y) < halfw) {
				float lh = 0.22 + 0.06 * (1.0 - abs(d.y) / halfw);
				if (lh > h) {
					h = lh;
					float tone = hash2f(cw, seed + 4U);
					vec3 lc = mix(vec3(0.36, 0.22, 0.1), vec3(0.55, 0.42, 0.2), tone);
					lc = mix(lc, vec3(0.25, 0.18, 0.1), step(0.7, tone));
					lc *= 0.85 + 0.2 * smoothstep(0.1, 0.0, abs(d.y) / halfw);
					col = lc;
				}
			}
		}
	}
}

// --- Materials ----------------------------------------------------------------------

void mat_grass(vec2 uv, out vec3 col, out float h) {
	float lush = fbmp(uv, 3, 5, 0.5, 201U);
	float dry = smoothstep(0.52, 0.75, fbmp(uv, 2, 4, 0.5, 202U));
	// Soil between the blades.
	float soil_n = fbmp(uv, 12, 5, 0.55, 203U);
	col = mix(vec3(0.1, 0.075, 0.045), vec3(0.2, 0.15, 0.09), soil_n);
	h = 0.04 + 0.06 * soil_n;
	pebble_layer(uv, 38, 204U, 0.25, 0.12, 0.3, vec3(0.3, 0.28, 0.25), vec3(0.46, 0.42, 0.36), 0.03, 0.12, col, h);
	// Thatch: dead blades lying flat.
	blade_layer(uv, 30, 210U, 1.4, 0.07, 0.1, 0.2, vec3(0.3, 0.25, 0.14), vec3(0.52, 0.46, 0.3), 0.5, 0.9, col, h);
	// Living grass, three layers from short and dense to tall and sparse.
	vec3 base = mix(vec3(0.07, 0.13, 0.03), vec3(0.1, 0.16, 0.04), lush);
	vec3 tip = mix(vec3(0.33, 0.45, 0.13), vec3(0.42, 0.55, 0.16), lush);
	tip = mix(tip, vec3(0.55, 0.52, 0.25), dry * 0.6);
	blade_layer(uv, 44, 220U, 1.3, 0.085, 0.25, 0.6, base, tip, 0.45, 0.95, col, h);
	blade_layer(uv, 58, 230U, 1.5, 0.08, 0.35, 0.8, base * 1.1, tip * 1.05, 0.5, 0.9, col, h);
	blade_layer(uv, 36, 240U, 1.7, 0.075, 0.45, 1.0, base * 1.2, tip * 1.12, 0.55, 0.55, col, h);
	// Small flowers and seed heads here and there.
	vec4 fw = worley_p(uv * 26.0, ivec2(26), 0.85, 250U);
	if (fw.z > 0.955 && fw.x < 0.09) {
		float petal = smoothstep(0.09, 0.05, fw.x);
		vec3 fc = fw.z > 0.985 ? vec3(0.95, 0.85, 0.35) : (fw.z > 0.97 ? vec3(0.92, 0.92, 0.95) : vec3(0.6, 0.45, 0.8));
		fc = mix(fc, vec3(0.9, 0.7, 0.2), smoothstep(0.035, 0.0, fw.x));
		col = mix(col, fc, petal);
		h = max(h, 0.9 * petal);
	}
	// Depth between blades reads as shadow.
	col *= mix(0.42, 1.05, pow(saturate(h), 0.7));
	col *= 0.9 + 0.2 * fbmp(uv, 6, 3, 0.5, 260U);
	h = saturate(h);
}

void mat_rock(vec2 uv, out vec3 col, out float h) {
	vec2 w = warp(uv, 3, 0.08, 301U) + warp(uv, 9, 0.012, 317U);
	vec2 q = uv + w;
	// Joints: thin, sharp fractures between large blocks, with chipped, rounded edges.
	vec3 big = voronoi_edge(q * 4.0, ivec2(4), 1.0, 302U);
	float joint = 1.0 - smoothstep(0.004, 0.018, big.x);
	float chip = 1.0 - smoothstep(0.0, 0.12, big.x);
	// Wandering crevices and hairline cracks.
	float crev = pow(1.0 - abs(fbm_p(q * 6.0, ivec2(6), 4, 0.5, 303U)), 40.0);
	vec3 hair = voronoi_edge((q + warp(uv, 12, 0.01, 304U)) * 15.0, ivec2(15), 0.9, 305U);
	float hair_mask = smoothstep(0.5, 0.65, fbmp(uv, 5, 3, 0.5, 318U));
	float hairline = (1.0 - smoothstep(0.0, 0.012, hair.x)) * hair_mask;
	float rough = fbmp(q, 5, 7, 0.55, 306U);
	float bumps = fbmp(q, 24, 4, 0.55, 307U);
	float grain = fbmp(uv, 128, 3, 0.6, 308U);
	float strata = sin((q.y * 9.0 + rough * 1.6) * TAU) * 0.5 + 0.5;

	h = 0.3 + big.y * 0.15 + rough * 0.38 + bumps * 0.1 + grain * 0.04 + strata * 0.04;
	h -= chip * 0.14 + joint * 0.3 + crev * 0.22 + hairline * 0.08;
	h = saturate(h);

	// Mottled mineral colour: cool grey, warm buff, blue-grey patches.
	float tone = fbmp(uv, 2, 4, 0.5, 309U);
	float mottle = fbmp(q, 10, 5, 0.6, 319U);
	vec3 grey = vec3(0.45, 0.44, 0.42);
	vec3 warm = vec3(0.54, 0.49, 0.41);
	vec3 cool = vec3(0.37, 0.39, 0.41);
	col = mix(cool, grey, smoothstep(0.25, 0.6, tone));
	col = mix(col, warm, smoothstep(0.5, 0.85, tone * 0.5 + big.y * 0.3 + mottle * 0.3) * 0.75);
	col *= 0.8 + 0.3 * rough + 0.14 * (mottle - 0.5);
	col = mix(col, col * vec3(0.92, 0.88, 0.82), strata * 0.25);
	// Fine crystal grains, low contrast.
	vec4 g1 = worley_p(uv * 340.0, ivec2(340), 1.0, 310U);
	vec4 g2 = worley_p(uv * 260.0, ivec2(260), 1.0, 311U);
	col *= 1.0 - 0.28 * step(0.7, g1.z) * smoothstep(0.45, 0.2, g1.x);
	col *= 1.0 + 0.18 * step(0.75, g2.z) * smoothstep(0.4, 0.15, g2.x);
	// Rain streaks running down, rust stains.
	float streak = fbmp2(uv + vec2(0.0, w.x), ivec2(32, 2), 4, 0.5, 312U);
	float wet = smoothstep(0.55, 0.8, streak) * smoothstep(0.35, 0.7, fbmp(uv, 3, 3, 0.5, 313U));
	col *= 1.0 - wet * 0.22;
	float rust = smoothstep(0.64, 0.82, fbmp(uv, 4, 5, 0.55, 314U));
	col = mix(col, col * vec3(1.2, 0.92, 0.68), rust * 0.5);
	// Crusty lichen colonies.
	float lichen_mask = smoothstep(0.62, 0.78, fbmp(q, 5, 4, 0.5, 315U)) * (1.0 - chip);
	vec4 lw = worley_p(uv * 70.0, ivec2(70), 0.9, 316U);
	float crust = smoothstep(0.6, 0.3, lw.x + (bumps - 0.5) * 0.3) * lichen_mask;
	vec3 lichen = lw.z > 0.8 ? vec3(0.68, 0.58, 0.32) : (lw.z > 0.35 ? vec3(0.6, 0.63, 0.52) : vec3(0.48, 0.52, 0.38));
	col = mix(col, lichen * (0.85 + 0.25 * grain), crust * 0.7);
	h = saturate(h + crust * 0.03);
	// Cavity darkening.
	col *= 1.0 - joint * 0.65 - crev * 0.3 - hairline * 0.3 - chip * 0.1;
	col *= mix(0.72, 1.08, h);
}

void mat_dirt(vec2 uv, out vec3 col, out float h) {
	vec2 w = warp(uv, 4, 0.03, 401U);
	float base = fbmp(uv + w, 6, 6, 0.55, 402U);
	float moist = smoothstep(0.5, 0.75, fbmp(uv, 3, 4, 0.5, 403U));
	col = mix(vec3(0.22, 0.16, 0.1), vec3(0.4, 0.31, 0.21), base);
	col = mix(col, col * vec3(0.62, 0.6, 0.62), moist);
	h = base * 0.3;
	// Clods.
	vec3 cl = voronoi_edge((uv + w * 3.0) * 18.0, ivec2(18), 1.0, 404U);
	float clod = smoothstep(0.0, 0.12, cl.x);
	h += clod * 0.12 * (0.6 + 0.4 * cl.y);
	col *= mix(0.9, 1.0, clod);
	// Dried mud cracks in drier patches.
	float dry = smoothstep(0.55, 0.7, fbmp(uv, 2, 4, 0.5, 405U)) * (1.0 - moist);
	vec3 mud = voronoi_edge((uv + w * 2.0) * 9.0, ivec2(9), 1.0, 406U);
	float mud_crack = 1.0 - smoothstep(0.004, 0.016, mud.x);
	col = mix(col, col * 0.4, mud_crack * dry);
	col = mix(col, col * vec3(1.12, 1.08, 1.0), dry * 0.4);
	h -= mud_crack * dry * 0.15;
	// Grit.
	int grit_n = pc.size * 3 / 4;
	float grit = hash2f(wrap_cell(ivec2(floor(uv * float(grit_n))), ivec2(grit_n)), 407U);
	col *= 0.9 + 0.2 * grit;
	h += grit * 0.03;
	pebble_layer(uv, 70, 410U, 0.35, 0.1, 0.3, vec3(0.35, 0.33, 0.3), vec3(0.52, 0.47, 0.4), 0.2, 0.2, col, h);
	pebble_layer(uv, 28, 411U, 0.4, 0.15, 0.38, vec3(0.33, 0.31, 0.29), vec3(0.55, 0.5, 0.43), 0.25, 0.4, col, h);
	pebble_layer(uv, 9, 412U, 0.3, 0.12, 0.28, vec3(0.38, 0.36, 0.34), vec3(0.5, 0.46, 0.4), 0.3, 0.55, col, h);
	litter_layer(uv, 22, 420U, 0.18, col, h);
	twig_layer(uv, 12, 430U, 0.2, col, h);
	col *= mix(0.65, 1.05, saturate(h * 1.4));
	h = saturate(h);
}

void mat_snow(vec2 uv, out vec3 col, out float h) {
	vec2 w = warp(uv, 3, 0.05, 501U);
	float drift = fbmp(uv + w, 3, 5, 0.5, 502U);
	// Wind ripples (sastrugi) whose strength varies across the drift.
	float ripple_amp = smoothstep(0.35, 0.75, fbmp(uv, 2, 3, 0.5, 503U));
	float ripple = sin((uv.y + w.x * 1.5) * 38.0 * TAU + drift * 5.0) * 0.5 + 0.5;
	ripple = pow(ripple, 2.2);
	float fine = fbmp(uv, 30, 4, 0.55, 504U);
	h = drift * 0.6 + ripple * ripple_amp * 0.18 + fine * 0.12;
	// Compacted, icy patches are smoother and bluer.
	float ice = smoothstep(0.65, 0.8, fbmp(uv, 4, 4, 0.5, 505U));
	h = mix(h, drift * 0.6 + 0.1, ice * 0.7);
	col = mix(vec3(0.66, 0.72, 0.83), vec3(0.95, 0.96, 0.99), smoothstep(0.15, 0.75, h));
	col = mix(col, vec3(0.7, 0.8, 0.9), ice * 0.4);
	// Sparkles.
	vec4 s = worley_p(uv * 180.0, ivec2(180), 1.0, 506U);
	col += vec3(0.08) * step(0.94, s.z) * smoothstep(0.18, 0.0, s.x);
	h = saturate(h);
}

void mat_bark_oak(vec2 uv, out vec3 col, out float h) {
	vec2 w = warp(uv, 4, 0.015, 601U) * vec2(1.0, 0.3);
	vec2 q = uv + w;
	// Furrows follow the zero crossings of vertically stretched noise: they wander,
	// fork and merge like real oak bark. A finer set adds shallower grooves.
	float n1 = fbm_p(q * vec2(9.0, 2.0), ivec2(9, 2), 5, 0.5, 602U);
	float n2 = fbm_p(q * vec2(20.0, 3.0), ivec2(20, 3), 4, 0.5, 609U);
	float ridge = pow(smoothstep(0.0, 0.35, abs(n1)), 0.55);
	float groove = smoothstep(0.0, 0.12, abs(n2));
	float furrow = smoothstep(0.0, 0.06, abs(n1));
	// Short cracks across the ridges.
	vec3 blocks = voronoi_edge(q * vec2(9.0, 30.0), ivec2(9, 30), 0.9, 603U);
	float cross_crack = (1.0 - smoothstep(0.0, 0.05, blocks.x)) * smoothstep(0.3, 0.7, ridge)
			* smoothstep(0.45, 0.65, fbmp(uv, 6, 3, 0.5, 610U));
	float fib = fbmp2(uv, ivec2(72, 4), 4, 0.55, 604U);
	float rough = fbmp(uv, 14, 5, 0.55, 605U);
	h = ridge * (0.6 + 0.15 * blocks.y + 0.15 * fib + 0.1 * rough) * mix(0.8, 1.0, groove);
	h -= cross_crack * 0.12;
	h = saturate(h);
	vec3 bark = mix(vec3(0.3, 0.27, 0.23), vec3(0.5, 0.46, 0.4), fib * 0.45 + rough * 0.3 + blocks.y * 0.25);
	col = mix(vec3(0.1, 0.075, 0.055), bark, furrow);
	col *= mix(0.8, 1.0, groove) * (1.0 - cross_crack * 0.35);
	// Green algae on the damp side, pale lichen spots on ridges.
	float damp = smoothstep(0.5, 0.78, fbmp(uv, 3, 4, 0.5, 606U));
	col = mix(col, vec3(0.22, 0.28, 0.1) * (0.7 + 0.4 * rough), damp * (1.0 - ridge * 0.6) * 0.75);
	vec4 lw = worley_p(uv * vec2(48.0, 24.0), ivec2(48, 24), 0.9, 607U);
	float lichen = smoothstep(0.5, 0.2, lw.x) * step(0.62, lw.z) * ridge * smoothstep(0.55, 0.7, fbmp(uv, 4, 3, 0.5, 608U));
	col = mix(col, vec3(0.62, 0.65, 0.55), lichen * 0.7);
	col *= mix(0.82, 1.04, h);
}

void mat_bark_pine(vec2 uv, out vec3 col, out float h) {
	vec2 w = warp(uv, 4, 0.035, 701U);
	vec2 q = uv + w;
	// Irregular domed plates, each built from a few flaking layers.
	vec3 plates = voronoi_edge(q * vec2(6.0, 4.0), ivec2(6, 4), 1.0, 702U);
	float gap = smoothstep(0.004, 0.03, plates.x);
	float dome = smoothstep(0.0, 0.25, plates.x);
	vec3 flakes = voronoi_edge((q + warp(uv, 8, 0.01, 706U)) * vec2(18.0, 12.0), ivec2(18, 12), 1.0, 703U);
	float layer = floor(flakes.y * 3.0) / 3.0;
	float flake_edge = smoothstep(0.0, 0.02, flakes.x);
	float rough = fbmp(uv, 16, 4, 0.55, 704U);
	float fine = fbmp(uv, 64, 3, 0.55, 705U);
	h = gap * (0.3 + 0.3 * dome + 0.15 * plates.y + 0.15 * layer + 0.1 * rough);
	h *= mix(0.9, 1.0, flake_edge);
	h = saturate(h + fine * 0.03);
	// Grey-brown weathered surface; freshly flaked layers show the orange-red inner bark.
	vec3 outer = mix(vec3(0.3, 0.24, 0.2), vec3(0.45, 0.38, 0.32), rough * 0.6 + fine * 0.4);
	vec3 inner = mix(vec3(0.46, 0.26, 0.15), vec3(0.6, 0.37, 0.22), rough * 0.6 + fine * 0.4);
	float fresh = step(0.6, flakes.y) * smoothstep(0.35, 0.7, plates.y) * smoothstep(0.3, 0.6, fbmp(q, 30, 3, 0.5, 707U));
	vec3 pc_col = mix(outer, inner, fresh * 0.75);
	col = mix(vec3(0.1, 0.065, 0.045), pc_col, gap);
	col *= mix(0.82, 1.0, flake_edge) * mix(0.85, 1.0, dome);
	col *= mix(0.88, 1.03, h);
}

void mat_moss(vec2 uv, out vec3 col, out float h) {
	float lush = fbmp(uv, 4, 4, 0.5, 901U);
	col = vec3(0.05, 0.07, 0.025);
	h = 0.05;
	// Fuzzy tufts of many thin fronds, in three layers.
	for (int layer = 0; layer < 3; layer++) {
		int n = 34 + layer * 22;
		vec2 p = uv * float(n);
		ivec2 ci = ivec2(floor(p));
		uint seed = 910U + uint(layer) * 31U;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				ivec2 c = ci + ivec2(dx, dy);
				ivec2 cw = wrap_cell(c, ivec2(n));
				vec2 center = vec2(c) + hash2v(cw, seed);
				vec2 d = p - center;
				float r = length(d);
				float ang = atan(d.y, d.x) + hash2f(cw, seed + 1U) * TAU;
				float k = 9.0 + floor(hash2f(cw, seed + 2U) * 6.0);
				float frond = pow(abs(cos(ang * k * 0.5)), 2.0);
				float rad = (0.6 + 0.35 * hash2f(cw, seed + 3U)) * (0.55 + 0.45 * frond);
				if (r < rad) {
					float th = (0.3 + float(layer) * 0.18) * (1.0 - r / rad) + 0.12 + float(layer) * 0.12;
					if (th > h) {
						h = th;
						float tone = hash2f(cw, seed + 4U);
						vec3 mc = mix(vec3(0.13, 0.22, 0.05), vec3(0.33, 0.44, 0.11), tone * 0.6 + lush * 0.4);
						mc = mix(mc, vec3(0.42, 0.43, 0.15), step(0.92, tone) * 0.5);
						col = mc * (0.7 + 0.35 * (1.0 - r / rad)) * (0.85 + 0.2 * frond);
					}
				}
			}
		}
	}
	// Sporophytes: tiny red-brown capsules.
	vec4 sp = worley_p(uv * 55.0, ivec2(55), 0.9, 950U);
	if (sp.z > 0.9 && sp.x < 0.08) {
		float cap = smoothstep(0.08, 0.04, sp.x);
		col = mix(col, vec3(0.42, 0.2, 0.1), cap);
		h = max(h, 0.95 * cap);
	}
	col *= 0.9 + 0.2 * fbmp(uv, 96, 3, 0.6, 960U);
	col *= mix(0.6, 1.05, saturate(h));
	h = saturate(h);
}

// Wind waves from integer wave vectors (tiling), plus fine capillary ripples.
void mat_water(vec2 uv, out vec3 col, out float h) {
	h = 0.0;
	float amp = 0.3;
	for (int i = 0; i < 8; i++) {
		uint s = 1100U + uint(i) * 17U;
		ivec2 k = ivec2(int(hash2f(ivec2(i, 0), s) * 6.0) + 2 + i, int(hash2f(ivec2(i, 1), s) * 7.0) - 3);
		float phase = hash2f(ivec2(i, 2), s) * TAU;
		float wave = sin(dot(uv, vec2(k)) * TAU + phase + fbm_p(uv * 4.0, ivec2(4), 3, 0.5, s) * 1.5);
		// Sharper crests, wider troughs (Gerstner-like).
		h += amp * (1.0 - pow(1.0 - (wave * 0.5 + 0.5), 1.6));
		amp *= 0.72;
	}
	h = h * 0.5 + fbmp(uv, 16, 4, 0.55, 1150U) * 0.12;
	col = vec3(h);
}

// --- Foliage cards (not tiling; alpha is coverage) ----------------------------------

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
	// Twig with a side branch.
	vec2 twig_a = vec2(0.5, 0.995);
	vec2 twig_b = vec2(0.47, 0.12);
	float tt;
	float td = seg_dist(uv, twig_a, twig_b, tt);
	float tw = mix(0.011, 0.003, tt);
	if (td < tw) {
		col = mix(vec3(0.22, 0.15, 0.09), vec3(0.32, 0.24, 0.14), tt) * (0.8 + 0.3 * (1.0 - td / tw));
		alpha = smoothstep(tw, tw - aa, td);
		h = 0.3 + 0.1 * (1.0 - td / tw);
	}
	const int LEAVES = 30;
	for (int i = 0; i < LEAVES; i++) {
		uint s = uint(i) * 7349U + 1717U;
		float fi = float(i) / float(LEAVES - 1);
		float side = (i % 2 == 0) ? 1.0 : -1.0;
		vec2 base = mix(twig_a, twig_b, 0.1 + fi * 0.9);
		float ang = radians(-90.0 + side * mix(72.0, 22.0, fi) + (hash2f(ivec2(i, 1), s) - 0.5) * 36.0);
		float len = mix(0.28, 0.15, fi) * (0.85 + 0.3 * hash2f(ivec2(i, 2), s));
		float wid = len * (0.22 + 0.08 * hash2f(ivec2(i, 3), s));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 start = base + dir * 0.022;
		float pt;
		float pd = seg_dist(uv, base, start, pt);
		if (pd < 0.0028) {
			col = vec3(0.3, 0.32, 0.12);
			alpha = max(alpha, smoothstep(0.0028, 0.0028 - aa, pd));
			h = max(h, 0.35);
		}
		vec2 d = uv - start;
		// Leaves droop a little: bend the blade's axis.
		float t = dot(d, dir) / len;
		if (t < 0.0 || t > 1.0) {
			continue;
		}
		float curve = (hash2f(ivec2(i, 6), s) - 0.5) * 0.1 * len;
		float sdist = dot(d, vec2(-dir.y, dir.x)) - curve * t * t;
		float halfw = wid * pow(sin(3.14159 * pow(t, 0.75)), 0.7);
		// Serrated margin.
		float teeth = 1.0 - 0.07 * abs(sin(t * 34.0 + hash2f(ivec2(i, 7), s) * 6.0));
		halfw *= teeth;
		float edge = halfw - abs(sdist);
		if (edge <= 0.0) {
			continue;
		}
		float s_n = sdist / max(halfw, 1e-4);
		// Insect holes and brown spots on some leaves.
		vec2 lp = vec2(t, s_n * 0.3) * 8.0;
		vec4 hw = worley_p(lp + float(i) * 3.1, ivec2(0), 1.0, s + 50U);
		float damaged = step(0.8, hash2f(ivec2(i, 8), s));
		if (damaged > 0.5 && hw.z > 0.85 && hw.x < 0.18) {
			continue;
		}
		float hue = hash2f(ivec2(i, 4), s);
		vec3 leaf = mix(vec3(0.13, 0.26, 0.05), vec3(0.3, 0.44, 0.09), hue);
		leaf = mix(leaf, vec3(0.5, 0.45, 0.1), step(0.92, hue) * 0.6);
		// Midrib and pinnate secondary veins.
		float mid = smoothstep(0.07, 0.0, abs(s_n));
		float vein_t = fract(t * 9.0 - abs(s_n) * 1.4);
		float secondary = smoothstep(0.1, 0.0, abs(vein_t - 0.5) - 0.42) * smoothstep(0.95, 0.4, abs(s_n));
		// Translucent centre, darker rim and the side curling away from the light.
		leaf *= 0.8 + 0.3 * t * (1.0 - t) * 4.0 * 0.5;
		leaf *= mix(0.7, 1.05, smoothstep(0.0, 0.35, edge / wid));
		leaf *= 1.0 + s_n * side * 0.12;
		leaf = mix(leaf, leaf * 1.45 + vec3(0.04, 0.05, 0.0), mid * 0.9 + secondary * 0.35);
		if (damaged > 0.5) {
			float spot = smoothstep(0.35, 0.1, hw.x) * step(0.6, hw.z);
			leaf = mix(leaf, vec3(0.35, 0.25, 0.1), spot);
		}
		col = leaf;
		alpha = max(alpha, smoothstep(0.0, aa, edge));
		h = 0.5 + 0.3 * (1.0 - s_n * s_n) - mid * 0.06 - secondary * 0.03;
	}
}

void mat_needles(vec2 uv, out vec3 col, out float alpha, out float h) {
	col = vec3(0.0);
	alpha = 0.0;
	h = 0.0;
	float aa = 1.5 / float(pc.size);
	float twig_y = 0.5 + 0.05 * sin(uv.x * 3.14159);
	float td = abs(uv.y - twig_y);
	float tw = mix(0.011, 0.0035, uv.x);
	if (uv.x > 0.02 && uv.x < 0.97 && td < tw) {
		float scale = fract(uv.x * 90.0);
		col = mix(vec3(0.26, 0.17, 0.1), vec3(0.4, 0.28, 0.16), scale) * (0.75 + 0.35 * (1.0 - td / tw));
		alpha = smoothstep(tw, tw - aa, td);
		h = 0.4;
	}
	float step_x = 0.0075;
	int center = int(uv.x / step_x);
	for (int k = -36; k <= 2; k++) {
		int idx = center + k;
		float x0 = float(idx) * step_x;
		if (x0 < 0.03 || x0 > 0.95) {
			continue;
		}
		for (int side = 0; side < 4; side++) {
			float sg = (side % 2 == 0) ? 1.0 : -1.0;
			uint s = uint(idx * 4 + side) * 2654435761U;
			float jitter = hash2f(ivec2(idx, side), s);
			float ang = radians(mix(35.0, 68.0, jitter) + (side >= 2 ? 12.0 : 0.0));
			float len = mix(0.22, 0.1, smoothstep(0.6, 0.95, x0)) * (0.8 + 0.3 * hash2f(ivec2(idx, side + 5), s));
			if (side >= 2) {
				len *= 0.8;
			}
			vec2 a = vec2(x0, 0.5 + 0.05 * sin(x0 * 3.14159));
			vec2 b = a + vec2(cos(ang), sg * sin(ang)) * len;
			float t;
			float d = seg_dist(uv, a, b, t);
			float w = mix(0.0042, 0.0012, t * t);
			if (d < w) {
				// Fresh growth at the tip of the twig is lighter.
				float fresh = smoothstep(0.75, 0.93, x0);
				vec3 nc = mix(vec3(0.05, 0.14, 0.07), vec3(0.17, 0.3, 0.12), jitter);
				nc = mix(nc, vec3(0.33, 0.48, 0.16), fresh * 0.8);
				nc *= 0.75 + 0.4 * t;
				nc *= side >= 2 ? 0.8 : 1.0;
				// Pale stomatal line along the needle.
				nc += vec3(0.04, 0.06, 0.04) * smoothstep(0.35, 0.0, d / w);
				float nh = (side >= 2 ? 0.45 : 0.6) + 0.35 * (1.0 - d / w);
				if (nh > h || alpha < 0.5) {
					col = nc;
					h = nh;
				}
				alpha = max(alpha, smoothstep(w, w - aa, d));
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
		mat_bark_oak(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_BARK_PINE) {
		mat_bark_pine(uv, col, h);
		alpha = h;
	} else if (pc.mode == MODE_LEAVES) {
		mat_leaves(uv, col, alpha, h);
	} else if (pc.mode == MODE_NEEDLES) {
		mat_needles(uv, col, alpha, h);
	} else if (pc.mode == MODE_WATER) {
		mat_water(uv, col, h);
	} else {
		mat_moss(uv, col, h);
		alpha = h;
	}
}

float height_at(vec2 uv) {
	vec3 c;
	float a;
	float h;
	eval_mat(uv, c, a, h);
	return h;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy) + ivec2(0, pc.row_offset);
	if (px.x >= pc.size || px.y >= pc.size) {
		return;
	}
	float inv = 1.0 / float(pc.size);
	vec2 uv = (vec2(px) + 0.5) * inv;
	// 2x2 supersampling of colour, coverage and height.
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float h = 0.0;
	for (int s = 0; s < 4; s++) {
		vec2 o = (vec2(s % 2, s / 2) - 0.5) * 0.5 * inv;
		vec3 c;
		float a;
		float hh;
		eval_mat(uv + o, c, a, hh);
		col += c;
		alpha += a;
		h += hh;
	}
	col *= 0.25;
	alpha *= 0.25;
	// Central differences; strength is given per 1024 px so it matches the default baker.
	float scale = pc.normal_strength * float(pc.size) / 1024.0 * 0.5;
	float hx = height_at(uv + vec2(inv, 0.0)) - height_at(uv - vec2(inv, 0.0));
	float hy = height_at(uv + vec2(0.0, inv)) - height_at(uv - vec2(0.0, inv));
	vec3 n = normalize(vec3(-hx * scale, hy * scale, 1.0));
	uint i = uint(px.y * pc.size + px.x);
	albedo_out[i] = packUnorm4x8(vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0)));
	normal_out[i] = packUnorm4x8(vec4(n * 0.5 + 0.5, 1.0));
}
