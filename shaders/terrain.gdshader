shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Terrain: flat grid chunks displaced on the GPU from the heightmap, plus close-range
// detail displacement around the player. Body in terrain_body.gdshaderinc.

#include "res://shaders/include/terrain_body.gdshaderinc"
