shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
// The Black Hole's spark (BlackHole): a camera-facing star – white-hot core, soft violet halo,
// four long rays turning one way and four short ones turning the other, twinkling – that flares
// up (`flare`) just before the rift opens.

uniform vec3 color : source_color = vec3(0.78, 0.6, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 0.97, 1.0);
uniform float energy = 3.0;
instance uniform float flare = 0.0;
instance uniform float spin = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float twinkle = 0.85 + 0.15 * sin(TIME * 17.0) * sin(TIME * 7.3);
	float core = exp(-r * r * 160.0) * 3.0 + exp(-r * r * 40.0) * 0.6;
	float halo = exp(-r * r * 14.0) * 0.1;
	float long_rays = pow(abs(cos(2.0 * (a + spin))), 60.0) * exp(-r * (3.2 - flare * 1.8));
	float short_rays = pow(abs(cos(2.0 * (a - spin * 1.6) + 0.785)), 40.0) * exp(-r * 7.0) * 0.7;
	float ring = exp(-pow((r - 0.35 - flare * 0.3) / 0.02, 2.0)) * flare * 0.8;
	vec3 col = core_color * core + color * (halo + (long_rays + short_rays) * twinkle + ring);
	ALBEDO = col * energy * (1.0 + flare * 0.8) * (1.0 - smoothstep(0.85, 1.0, r));
}
