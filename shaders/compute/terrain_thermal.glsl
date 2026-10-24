#[compute]
#version 450

// Stage 3: thermal erosion. Material on slopes steeper than the talus angle slides
// to lower neighbours, forming scree and smoothing droplet artefacts. Written as a
// symmetric gather so it conserves mass without atomics (ping-pong buffers).

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Src { int src[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Dst { int dst[]; };

layout(push_constant, std430) uniform Params {
	int res;
	float talus;
	float rate;
	float pad;
} pc;

const float FIXED = 65536.0;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= pc.res || id.y >= pc.res) {
		return;
	}
	float h = float(src[id.y * pc.res + id.x]) / FIXED;
	float delta = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) {
				continue;
			}
			ivec2 n = id + ivec2(x, y);
			if (n.x < 0 || n.y < 0 || n.x >= pc.res || n.y >= pc.res) {
				continue;
			}
			float dist = (x != 0 && y != 0) ? 1.41421356 : 1.0;
			float d = float(src[n.y * pc.res + n.x]) / FIXED - h;
			float excess = abs(d) / dist - pc.talus;
			if (excess > 0.0) {
				delta += sign(d) * excess * dist * pc.rate * 0.125;
			}
		}
	}
	dst[id.y * pc.res + id.x] = int((h + delta) * FIXED);
}
