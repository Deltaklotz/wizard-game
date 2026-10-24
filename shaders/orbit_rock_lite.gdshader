shader_type spatial;
render_mode cull_back, world_vertex_coords;

// Performance-mode orbiting rocks (GraphicsQuality).
#define ORBIT
#define LITE
#include "res://shaders/include/rock_common.gdshaderinc"
