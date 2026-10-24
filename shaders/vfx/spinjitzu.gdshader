shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// One layer of a Spinjitzu tornado (Spinjitzu.gd): a shallow funnel-lip ring (mesh radius
// `inner`..1, outer edge raised) covered in the simple black hole disk's streaming filaments
// (bh_lite_common: thin arcs of matter racing round, two advected copies cross-faded so the
// shear never winds up). Many of these stacked and widening upwards form the tornado.
// Local angle 0 = -Z, the way the player faces: on the mid layers (`window`) the filaments
// thin out there between two bright seams, so others see the facing and the player sees out.

#include "res://shaders/vfx/bh_lite_common.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.2);
uniform vec3 accent : source_color = vec3(1.0, 0.96, 0.82);
uniform float energy = 1.7;
uniform float inner = 0.35;
instance uniform float strength = 1.0;
// Revolutions per second and pattern variation per layer.
instance uniform float speed = 1.3;
instance uniform float seed = 0.0;
// 1 = the local player's own tornado, seen from inside.
instance uniform float inside = 0.0;
// 0..1: how much of the facing window this layer has.
instance uniform float window = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float r = length(v_local.xz);
	float u = clamp((r - inner) / (1.0 - inner), 0.0, 1.0);
	float ang = atan(v_local.x, -v_local.z);
	// Faster inside, slower at the rim (the shear streaks the filaments into arcs).
	float omega = speed * 6.2831853 * (1.25 - 0.45 * u);
	float period = 1.3;
	float c1 = fract(TIME / period);
	float c2 = fract(TIME / period + 0.5);
	float w1 = 1.0 - abs(c1 * 2.0 - 1.0);
	float lr = 1.0 + u * 0.9;
	vec2 m = mix(bhl_pattern(ang + omega * c2 * period, lr, seed + 17.0),
		bhl_pattern(ang + omega * c1 * period, lr, seed), w1);
	// Faint at the inner edge: the inner rims of all layers line up in the middle of the view
	// and would add up to a white column.
	float edge = smoothstep(0.0, 0.4, u) * (1.0 - smoothstep(0.65, 1.0, u));
	float a = (m.y * 1.7 + m.x * m.x * 0.22) * edge;
	// Facing window and its seams.
	float d = abs(ang);
	float win_w = mix(0.62, 1.0, inside);
	float win = window * (1.0 - smoothstep(win_w * 0.55, win_w, d));
	float seam = window * exp(-pow((d - win_w) / 0.09, 2.0)) * edge * (1.0 - inside);
	a *= 1.0 - win * 0.92;
	vec3 col = mix(accent, color, smoothstep(0.1, 0.5, u));
	ALBEDO = (col * a + accent * seam * 0.9) * energy * strength * mix(1.0, 0.3, inside);
}
