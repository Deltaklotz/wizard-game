shader_type spatial;
render_mode blend_add, cull_back, unshaded;

uniform vec4 glow_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed);
	ALBEDO = glow_color.rgb;
	ALPHA = rim * pulse;
}
