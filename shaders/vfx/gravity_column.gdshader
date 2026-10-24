shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Gravity Field (GravityField.gd): an endless column of crushing force. Bright edges (fresnel),
// bands rushing downwards, faint vertical streaks; strongest near the ground. Placed on a
// cylinder whose local y = metres above the ground.

uniform vec3 color : source_color = vec3(0.42, 0.25, 1.0);
uniform vec3 accent : source_color = vec3(0.85, 0.75, 1.0);
uniform float energy = 1.6;
// Bands per metre and their downward speed (m/s).
uniform float band_scale = 0.11;
uniform float fall_speed = 22.0;
instance uniform float strength = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float y = v_local.y;
	float ang = atan(v_local.x, v_local.z);
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	// Bands falling down the column (sharp lower edge, trailing glow above).
	float b = fract(y * band_scale + TIME * fall_speed * band_scale);
	float band = smoothstep(0.0, 0.04, b) * pow(1.0 - b, 5.0);
	// Second, finer set.
	float b2 = fract(y * band_scale * 3.1 + TIME * fall_speed * band_scale * 4.2);
	float band2 = smoothstep(0.0, 0.03, b2) * pow(1.0 - b2, 9.0) * 0.4;
	// Vertical streaks round the wall.
	float streak = pow(0.5 + 0.5 * sin(ang * 14.0 + sin(ang * 5.0 + y * 0.02) * 2.0), 6.0);
	float low = exp(-y / 60.0);
	float bottom = smoothstep(0.0, 0.8, y);
	vec3 col = color * (0.04 + edge * 0.7) + accent * (band + band2) * (0.25 + edge * 0.9) + color * streak * 0.15;
	col *= mix(0.45, 1.6, low) * bottom;
	ALBEDO = col * energy * strength;
}
