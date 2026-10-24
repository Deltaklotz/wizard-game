shader_type canvas_item;
// Red flash at the screen edges when the player takes damage; stays faintly at low health.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float edge = smoothstep(0.35, 1.0, r);
	float beat = 0.75 + 0.25 * sin(TIME * 5.0);
	float a = edge * (intensity * 0.85 + low_health * 0.35 * beat);
	COLOR = vec4(0.55, 0.02, 0.04, clamp(a, 0.0, 0.9));
}
