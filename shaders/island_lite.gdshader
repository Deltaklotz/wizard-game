shader_type spatial;
render_mode cull_back;

// Performance-mode islands (GraphicsQuality).
#define LITE
#include "res://shaders/include/island_body.gdshaderinc"
