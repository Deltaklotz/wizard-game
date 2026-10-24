#[compute]
#version 450

// Stage 2: particle-based hydraulic erosion. Each invocation is one water droplet
// that rolls downhill, picking up sediment on steep/fast sections and depositing it
// where it slows down. Heights are fixed-point ints updated atomically, and every
// change is also accumulated into erosion/deposition/flow maps for texturing.
//
// Deterministic: droplets only READ the snapshot (the heights when this batch started) and
// only ADD their changes to the live heights with integer atomics. Integer addition gives the
// same sum in any order, so the result no longer depends on how the GPU schedules the
// droplets (reading the live, changing heights made the same seed differ by up to ~1 m).
// The script copies the live heights into the snapshot between batches, so later batches
// still flow over the changes of earlier ones.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Heights { int heights[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer Snapshot { int snapshot[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer BrushOffsets { ivec2 brush_offsets[]; };
layout(set = 0, binding = 3, std430) restrict readonly buffer BrushWeights { float brush_weights[]; };
layout(set = 0, binding = 4, std430) restrict buffer ErosionAcc { int erosion_acc[]; };
layout(set = 0, binding = 5, std430) restrict buffer DepositAcc { int deposit_acc[]; };
layout(set = 0, binding = 6, std430) restrict buffer FlowAcc { uint flow_acc[]; };

layout(push_constant, std430) uniform Params {
	int res;
	int brush_count;
	int droplet_offset;
	int seed;
	int max_lifetime;
	float inertia;
	float capacity_factor;
	float min_capacity;
	float erode_speed;
	float deposit_speed;
	float evaporate_speed;
	float gravity;
	float start_water;
	float start_speed;
	float height_scale;
	float pad;
} pc;

#include "noise_lib.glsl"

const float FIXED = 65536.0;
const float ACC_FIXED = 4096.0;

// Heights inside the simulation are divided by height_scale so the classic
// erosion constants behave the same regardless of the terrain's vertical range.
float H(ivec2 c) {
	return float(snapshot[c.y * pc.res + c.x]) / FIXED / pc.height_scale;
}

void add_height(ivec2 c, float amount) {
	atomicAdd(heights[c.y * pc.res + c.x], int(amount * pc.height_scale * FIXED));
}

vec3 height_and_gradient(vec2 pos) {
	ivec2 c = ivec2(floor(pos));
	vec2 f = pos - vec2(c);
	float nw = H(c);
	float ne = H(c + ivec2(1, 0));
	float sw = H(c + ivec2(0, 1));
	float se = H(c + ivec2(1, 1));
	float gx = (ne - nw) * (1.0 - f.y) + (se - sw) * f.y;
	float gy = (sw - nw) * (1.0 - f.x) + (se - ne) * f.x;
	float h = nw * (1.0 - f.x) * (1.0 - f.y) + ne * f.x * (1.0 - f.y) + sw * (1.0 - f.x) * f.y + se * f.x * f.y;
	return vec3(gx, gy, h);
}

void main() {
	uint id = gl_GlobalInvocationID.x + uint(pc.droplet_offset);
	uint s = hash_u(id * 747796405U + uint(pc.seed));
	float margin = 4.0;
	float span = float(pc.res - 1) - margin * 2.0;
	vec2 pos = vec2(margin) + vec2(float(s & 0xFFFFU), float(hash_u(s) & 0xFFFFU)) / 65535.0 * span;
	vec2 dir = vec2(0.0);
	float speed = pc.start_speed;
	float water = pc.start_water;
	float sediment = 0.0;

	for (int life = 0; life < pc.max_lifetime; life++) {
		ivec2 cell = ivec2(floor(pos));
		vec2 off = pos - vec2(cell);
		vec3 hg = height_and_gradient(pos);

		dir = dir * pc.inertia - hg.xy * (1.0 - pc.inertia);
		float len = length(dir);
		if (len < 1e-6) {
			break;
		}
		dir /= len;
		pos += dir;
		if (pos.x < margin || pos.y < margin || pos.x > float(pc.res - 1) - margin || pos.y > float(pc.res - 1) - margin) {
			break;
		}

		atomicAdd(flow_acc[cell.y * pc.res + cell.x], 1U);

		float new_h = height_and_gradient(pos).z;
		float dh = new_h - hg.z;
		float capacity = max(-dh * speed * water * pc.capacity_factor, pc.min_capacity);

		if (sediment > capacity || dh > 0.0) {
			// Fill the pit we just rolled into, or drop surplus sediment.
			float amount = dh > 0.0 ? min(dh, sediment) : (sediment - capacity) * pc.deposit_speed;
			sediment -= amount;
			float w00 = (1.0 - off.x) * (1.0 - off.y);
			float w10 = off.x * (1.0 - off.y);
			float w01 = (1.0 - off.x) * off.y;
			float w11 = off.x * off.y;
			add_height(cell, amount * w00);
			add_height(cell + ivec2(1, 0), amount * w10);
			add_height(cell + ivec2(0, 1), amount * w01);
			add_height(cell + ivec2(1, 1), amount * w11);
			atomicAdd(deposit_acc[cell.y * pc.res + cell.x], int(amount * pc.height_scale * ACC_FIXED));
		} else {
			float amount = min((capacity - sediment) * pc.erode_speed, -dh);
			for (int i = 0; i < pc.brush_count; i++) {
				ivec2 c = cell + brush_offsets[i];
				if (c.x < 0 || c.y < 0 || c.x >= pc.res || c.y >= pc.res) {
					continue;
				}
				float d = min(H(c), amount * brush_weights[i]);
				add_height(c, -d);
				atomicAdd(erosion_acc[c.y * pc.res + c.x], int(d * pc.height_scale * ACC_FIXED));
				sediment += d;
			}
		}

		speed = sqrt(max(speed * speed - dh * pc.gravity, 0.0));
		water *= 1.0 - pc.evaporate_speed;
	}
}
