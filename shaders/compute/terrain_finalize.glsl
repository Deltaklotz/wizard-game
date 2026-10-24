#[compute]
#version 450

// Stage 4: convert heights to floats and pack the erosion maps into an RGBA8
// control map used by the terrain shader and the scatter system:
//   R = deposited sediment (soft soil / dirt)
//   G = water flow (channels, damp ground)
//   B = eroded material (exposed rock)
//   A = concavity (0.5 flat, >0.5 hollows, <0.5 ridges)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Heights { int heights[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer ErosionAcc { int erosion_acc[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer DepositAcc { int deposit_acc[]; };
layout(set = 0, binding = 3, std430) restrict readonly buffer FlowAcc { uint flow_acc[]; };
layout(set = 0, binding = 4, std430) restrict writeonly buffer HeightOut { float height_out[]; };
layout(set = 0, binding = 5, std430) restrict writeonly buffer ControlOut { uint control_out[]; };

layout(push_constant, std430) uniform Params {
	int res;
	float erosion_norm;
	float deposit_norm;
	float flow_norm;
	float concavity_scale;
	float pad0;
	float pad1;
	float pad2;
} pc;

const float FIXED = 65536.0;
const float ACC_FIXED = 4096.0;

float hgt(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(pc.res - 1));
	return float(heights[c.y * pc.res + c.x]) / FIXED;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= pc.res || id.y >= pc.res) {
		return;
	}
	float h = hgt(id);
	height_out[id.y * pc.res + id.x] = h;

	// Soften the droplet trails with a small blur.
	float ero = 0.0;
	float dep = 0.0;
	float flow = 0.0;
	float wsum = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 c = clamp(id + ivec2(x, y), ivec2(0), ivec2(pc.res - 1));
			float w = 1.0 / (1.0 + float(x * x + y * y));
			int i = c.y * pc.res + c.x;
			ero += float(erosion_acc[i]) / ACC_FIXED * w;
			dep += float(deposit_acc[i]) / ACC_FIXED * w;
			flow += float(flow_acc[i]) * w;
			wsum += w;
		}
	}
	ero /= wsum;
	dep /= wsum;
	flow /= wsum;

	float lap = 0.0;
	for (int r = 1; r <= 4; r *= 2) {
		lap += (hgt(id + ivec2(r, 0)) + hgt(id - ivec2(r, 0)) + hgt(id + ivec2(0, r)) + hgt(id - ivec2(0, r)) - 4.0 * h) / float(r);
	}

	vec4 ctl;
	ctl.r = clamp(dep / pc.deposit_norm, 0.0, 1.0);
	ctl.g = clamp(log(1.0 + flow) / log(1.0 + pc.flow_norm), 0.0, 1.0);
	ctl.b = clamp(ero / pc.erosion_norm, 0.0, 1.0);
	ctl.a = clamp(0.5 + lap * pc.concavity_scale, 0.0, 1.0);
	control_out[id.y * pc.res + id.x] = packUnorm4x8(ctl);
}
