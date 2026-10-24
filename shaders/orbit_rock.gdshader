shader_type spatial;
render_mode cull_back, world_vertex_coords;

// Rocks levitating in slow orbits around a floating island, animated entirely on the GPU.
#define ORBIT
#include "res://shaders/include/rock_common.gdshaderinc"
