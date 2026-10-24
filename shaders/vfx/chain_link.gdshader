shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
// Spectral chain link (ChainFx). Translucent ghost: a see-through body with a glowing fresnel
// rim tinted towards the accent (slightly over 1 so it blooms), a shimmer running down the
// chain and a per-link flicker.
// INSTANCE_CUSTOM.r = fade (0..1, >1 flashes), .g = per-link phase.

uniform vec3 color : source_color = vec3(0.72, 1.0, 0.32);
uniform vec3 accent : source_color = vec3(1.0, 0.93, 0.42);
uniform float energy = 1.35;

varying float v_fade;
varying float v_phase;
varying vec3 v_world;

void vertex() {
	v_fade = INSTANCE_CUSTOM.r;
	v_phase = INSTANCE_CUSTOM.g;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 1.8);
	float band = 0.5 + 0.5 * sin(dot(v_world, vec3(0.9, 0.7, 1.1)) * 2.2 - TIME * 7.0);
	float flick = 0.85 + 0.15 * sin(TIME * 11.0 + v_phase * 37.0);
	vec3 c = mix(color * 0.8, accent, rim * 0.85 + band * 0.2);
	ALBEDO = c * energy * (0.7 + rim * 0.7 + band * 0.2) * flick * max(v_fade, 1.0);
	ALPHA = clamp((0.32 + rim * 0.6 + band * 0.08) * flick * min(v_fade, 1.0), 0.0, 1.0);
}
