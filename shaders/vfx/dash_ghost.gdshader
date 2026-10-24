shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
// Afterimage of a dashing wizard: glowing fresnel silhouette with drifting arcane noise.

uniform vec4 color : source_color = vec4(0.5, 0.65, 1.0, 1.0);
uniform float energy = 2.0;
uniform float fade_all = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float bands = 0.5 + 0.5 * sin(world_pos.y * 22.0 - TIME * 9.0);
	ALBEDO = color.rgb * energy * (0.25 + rim * 1.4 + bands * 0.15);
	ALPHA = clamp(fade_all * (0.2 + rim * 0.8), 0.0, 1.0);
}
