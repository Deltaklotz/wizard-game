shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
// Landing preview of the Sword Wall (caster only): a translucent golden ghost of the sword with
// a bright fresnel outline and bands sweeping down it, pulsing gently.

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float energy = 0.9;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float band = smoothstep(0.75, 1.0, sin(v_local.y * 2.0 + TIME * 5.0));
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	ALBEDO = color * energy * pulse * (0.08 + rim * 0.9 + band * 0.25);
}
