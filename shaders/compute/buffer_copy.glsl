#[compute]
#version 450

// Copies one int buffer into another (GpuCompute.copy - the erosion snapshot between batches).

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Src { int src[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Dst { int dst[]; };

layout(push_constant, std430) uniform Params {
	int count;
	int pad0;
	int pad1;
	int pad2;
} pc;

void main() {
	int i = int(gl_GlobalInvocationID.x);
	if (i < pc.count) {
		dst[i] = src[i];
	}
}
