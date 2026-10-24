#[compute]
#version 450

// Multi-scale erosion: transfers the large-scale erosion result (computed on a
// coarse grid) onto the full-resolution heightmap by adding the upsampled
// height difference, and seeds the fine erosion maps with the coarse ones.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer FineHeights { int fine[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer CoarseOriginal { int coarse_orig[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer CoarseEroded { int coarse_eroded[]; };
layout(set = 0, binding = 3, std430) restrict readonly buffer CoarseErosion { int coarse_ero[]; };
layout(set = 0, binding = 4, std430) restrict readonly buffer CoarseDeposit { int coarse_dep[]; };
layout(set = 0, binding = 5, std430) restrict readonly buffer CoarseFlow { uint coarse_flow[]; };
layout(set = 0, binding = 6, std430) restrict buffer FineErosion { int fine_ero[]; };
layout(set = 0, binding = 7, std430) restrict buffer FineDeposit { int fine_dep[]; };
layout(set = 0, binding = 8, std430) restrict buffer FineFlow { uint fine_flow[]; };

layout(push_constant, std430) uniform Params {
	int res_fine;
	int res_coarse;
	int ratio;
	float flow_scale;
} pc;

int idx(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(pc.res_coarse - 1));
	return c.y * pc.res_coarse + c.x;
}

// Uniform cubic B-spline weights: C2-smooth, so no creases along coarse cell lines.
vec4 bspline(float t) {
	float it = 1.0 - t;
	return vec4(it * it * it, 3.0 * t * t * t - 6.0 * t * t + 4.0, -3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0, t * t * t) / 6.0;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= pc.res_fine || id.y >= pc.res_fine) {
		return;
	}
	vec2 g = vec2(id) / float(pc.ratio);
	ivec2 c = ivec2(floor(g));
	vec2 f = g - vec2(c);
	vec4 wx = bspline(f.x);
	vec4 wy = bspline(f.y);
	float delta = 0.0;
	float e = 0.0;
	float dp = 0.0;
	float fl = 0.0;
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			int i = idx(c + ivec2(x - 1, y - 1));
			float w = wx[x] * wy[y];
			delta += float(coarse_eroded[i] - coarse_orig[i]) * w;
			e += float(coarse_ero[i]) * w;
			dp += float(coarse_dep[i]) * w;
			fl += float(coarse_flow[i]) * w;
		}
	}
	int fi = id.y * pc.res_fine + id.x;
	fine[fi] += int(delta);
	fine_ero[fi] += int(e);
	fine_dep[fi] += int(dp);
	fine_flow[fi] += uint(fl * pc.flow_scale);
}
