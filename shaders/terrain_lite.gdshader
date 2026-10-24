shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Performance-mode terrain (GraphicsQuality): the same look with far fewer texture reads.

#define LITE
#include "res://shaders/include/terrain_body.gdshaderinc"
