shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Performance-mode leaves and needles (GraphicsQuality).
#define LITE
#include "res://shaders/include/foliage_body.gdshaderinc"
