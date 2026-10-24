shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The inner body of a Spinjitzu tornado (Spinjitzu.gd): an open funnel inside the stacked
// rings that gives the whirl its density. Covered in the same streaming filaments as the rings
// (bh_lite_common), laid round the funnel as fine horizontal streaks racing round; denser
// towards the silhouette (where the view grazes the surface), so it reads as a volume of wind
// rather than a cone. UV.x = angle (0 = local -Z, the way the player faces), UV.y = height 0..1.
// The facing window and `inside` dimming work like on the rings.

#include "res://shaders/vfx/bh_lite_common.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.2);
uniform vec3 accent : source_color = vec3(1.0, 0.96, 0.82);
uniform float energy = 1.8;
instance uniform float strength = 1.0;
instance uniform float speed = 1.4;
instance uniform float inside = 0.0;

void fragment() {
	float v = UV.y;
	float ang = (UV.x < 0.5 ? UV.x : UV.x - 1.0) * 6.2831853;
	float omega = speed * 6.2831853 * (1.3 - 0.4 * v);
	float period = 1.3;
	float c1 = fract(TIME / period);
	float c2 = fract(TIME / period + 0.5);
	float w1 = 1.0 - abs(c1 * 2.0 - 1.0);
	float lr = 1.0 + v * 1.2;
	vec2 m = mix(bhl_pattern(ang + omega * c2 * period, lr, 31.0), bhl_pattern(ang + omega * c1 * period, lr, 7.0), w1);
	float graze = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float a = (m.y * 1.4 + m.x * m.x * 0.25) * (0.45 + 0.55 * graze);
	// Soft ends (the top stays below the uppermost rings).
	a *= smoothstep(0.0, 0.12, v) * smoothstep(1.0, 0.75, v);
	// Facing window.
	float d = abs(ang);
	float wv = smoothstep(0.15, 0.3, v) * smoothstep(0.9, 0.7, v);
	float win_w = mix(0.62, 1.0, inside);
	a *= 1.0 - (1.0 - smoothstep(win_w * 0.55, win_w, d)) * wv * 0.92;
	vec3 col = mix(color, accent, clamp(m.y * graze, 0.0, 1.0) * 0.6);
	ALBEDO = col * a * energy * strength * mix(1.0, 0.2, inside);
}
