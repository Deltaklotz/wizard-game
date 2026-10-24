#[compute]
#version 450

// Stage 1: layered noise heightmap. Heights are written as fixed-point ints
// so the erosion stage can modify them with atomics.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer Heights { int heights[]; };

layout(push_constant, std430) uniform Params {
	int res;
	int seed;
	float cell_size;
	float base_height;
	float continent_freq;
	float continent_amp;
	float hill_freq;
	float hill_amp;
	float mountain_freq;
	float mountain_amp;
	float mountain_mask_freq;
	float mountain_coverage;
	float warp_freq;
	float warp_amp;
	float border_width;
	float border_amp;
	float detail_freq;
	float detail_amp;
	float valley_depth;
	float pad;
} pc;

#include "noise_lib.glsl"

const float FIXED = 65536.0;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= pc.res || id.y >= pc.res) {
		return;
	}
	uint s = hash_u(uint(pc.seed));
	vec2 seed_off = vec2(float(s & 0xFFFFU), float(s >> 16)) * 0.37;
	vec2 p = vec2(id) * pc.cell_size;
	vec2 ps = p + seed_off;

	// Domain warp bends every other layer so nothing looks grid aligned.
	vec2 warp = vec2(fbm(ps * pc.warp_freq, 4, 0.5, s + 1U), fbm(ps * pc.warp_freq + 31.7, 4, 0.5, s + 2U));
	vec2 q = ps + warp * pc.warp_amp;

	// Continental layer: broad lowlands and highlands.
	float cont = fbm(q * pc.continent_freq, 5, 0.5, s + 3U);
	float highland = smoothstep(-0.25, 0.45, cont);

	// Rolling hills, stronger on the highlands.
	float hills = fbm(q * pc.hill_freq, 5, 0.5, s + 4U) * pc.hill_amp * (0.35 + 0.65 * highland);

	// Ridged mountain ranges only where the mask allows.
	float mask_n = fbm(q * pc.mountain_mask_freq, 3, 0.5, s + 5U) * 0.5 + 0.5;
	float mmask = smoothstep(1.0 - pc.mountain_coverage - 0.12, 1.0 - pc.mountain_coverage + 0.18, mask_n);
	float r = ridged(q * pc.mountain_freq, 7, 0.5, s + 6U);
	float mountains = pow(r, 1.8) * pc.mountain_amp * mmask;
	mountains += smoothstep(0.0, 1.0, mmask) * pc.mountain_amp * 0.12;

	// River-like valleys: carve along the zero crossings of a warped noise field.
	float vn = abs(fbm(q * pc.continent_freq * 2.3, 4, 0.5, s + 10U));
	float valley = (1.0 - smoothstep(0.0, 0.12, vn)) * pc.valley_depth * (1.0 - mmask * 0.7);

	// Ring of mountains along the border keeps the player inside the map.
	vec2 uvn = vec2(id) / float(pc.res - 1);
	float edge = min(min(uvn.x, 1.0 - uvn.x), min(uvn.y, 1.0 - uvn.y)) * float(pc.res - 1) * pc.cell_size;
	edge += fbm(q * 0.006, 3, 0.5, s + 7U) * pc.border_width * 0.45;
	float bm = 1.0 - smoothstep(0.0, pc.border_width, edge);
	float border = bm * bm * pc.border_amp * (0.5 + 0.5 * ridged(q * pc.mountain_freq * 1.4, 6, 0.5, s + 8U));

	float detail = fbm(ps * pc.detail_freq, 4, 0.5, s + 9U) * pc.detail_amp;

	float h = pc.base_height + cont * pc.continent_amp + hills + mountains + border + detail - valley;
	h = max(h, 0.5);
	heights[id.y * pc.res + id.x] = int(h * FIXED);
}
