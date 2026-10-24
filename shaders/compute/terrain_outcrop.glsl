#[compute]
#version 450

// Stage 5b: rock outcrops. Real terrain doesn't just "turn grey" on slopes: where bedrock
// is exposed the ground breaks into steep risers and flatter ledges with rough, bulging
// stone. This pass finds steep (and randomly patchy) areas, terraces them along warped
// contours, adds ridged rock relief, and writes a rock mask for texturing and scatter.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Src { int src[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Dst { int dst[]; };
layout(set = 0, binding = 2, std430) restrict writeonly buffer RockOut { float rock_out[]; };

layout(push_constant, std430) uniform Params {
	int res;
	int seed;
	float cell_size;
	float slope_start;
	float slope_end;
	float terrace_height;
	float outcrop_amp;
	float patchiness;
} pc;

#include "noise_lib.glsl"

const float FIXED = 65536.0;

float H(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(pc.res - 1));
	return float(src[c.y * pc.res + c.x]) / FIXED;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= pc.res || id.y >= pc.res) {
		return;
	}
	uint s = hash_u(uint(pc.seed) ^ 0xA5A5A5A5U);
	vec2 p = vec2(id) * pc.cell_size + vec2(float(s & 0xFFFFU), float(s >> 16)) * 0.31;
	float h = H(id);

	// Slope over a 5-cell footprint so single-cell noise doesn't trigger rock.
	float dx = (H(id + ivec2(2, 0)) - H(id - ivec2(2, 0))) / (4.0 * pc.cell_size);
	float dz = (H(id + ivec2(0, 2)) - H(id - ivec2(0, 2))) / (4.0 * pc.cell_size);
	float slope = length(vec2(dx, dz));

	float patches = fbm(p * 0.018, 4, 0.5, s + 1U);
	float grain = fbm(p * 0.07, 3, 0.5, s + 2U);
	float m = smoothstep(pc.slope_start, pc.slope_end, slope + patches * pc.patchiness + grain * 0.08);

	// Terraces along noise-warped contours: steep risers, flatter treads.
	float step_h = pc.terrace_height * (0.6 + 0.8 * (fbm(p * 0.008, 2, 0.5, s + 3U) * 0.5 + 0.5));
	float warp = fbm(p * 0.04, 3, 0.5, s + 4U) * step_h * 0.7;
	float t = (h + warp) / step_h;
	float f = fract(t);
	float riser = smoothstep(0.3, 0.7, f);
	float terraced = (floor(t) + mix(f, riser, 0.8)) * step_h - warp;

	// Bulging, fractured stone relief (mostly outward).
	float r = ridged(p * 0.11, 4, 0.5, s + 5U);
	float relief = (r - 0.3) * pc.outcrop_amp + fbm(p * 0.35, 2, 0.5, s + 6U) * pc.outcrop_amp * 0.25;

	// Not every outcrop is terraced, and sheer mountain faces stay continuous
	// instead of turning into contour stripes.
	float terrace_strength = mix(0.15, 0.9, smoothstep(-0.2, 0.3, fbm(p * 0.006, 2, 0.5, s + 7U)))
			* (1.0 - smoothstep(0.85, 1.5, slope));
	float shaped = mix(h, terraced, terrace_strength) + relief;
	float h2 = mix(h, shaped, m);
	dst[id.y * pc.res + id.x] = int(h2 * FIXED);
	rock_out[id.y * pc.res + id.x] = m;
}
