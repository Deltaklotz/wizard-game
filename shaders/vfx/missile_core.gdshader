shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Magic / homing missile head (Missile.gd): camera-facing orb with a hot core, a soft halo and a
// turning four-point star flare.

uniform vec3 color : source_color = vec3(0.7, 0.4, 1.0);
uniform vec3 accent : source_color = vec3(1.0, 0.85, 1.0);
uniform float energy = 2.4;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float t = TIME * 4.0;
	vec2 q = mat2(vec2(cos(t), sin(t)), vec2(-sin(t), cos(t))) * c;
	float star = exp(-abs(q.x) * 30.0) * exp(-abs(q.y) * 2.5) + exp(-abs(q.y) * 30.0) * exp(-abs(q.x) * 2.5);
	float halo = exp(-r * r * 10.0);
	float core = exp(-r * r * 60.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 25.0);
	vec3 col = color * (halo * 0.8 + star * 0.6) + accent * core * 2.0;
	ALBEDO = col * energy * pulse * (1.0 - smoothstep(0.85, 1.0, r));
}
