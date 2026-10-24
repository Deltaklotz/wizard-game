shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Additive glowing particle for the dash spell. Colour and fade come from the particle COLOR.
//   streak = false: round billboarded mote with a soft halo and a hot core.
//   streak = true:  thin line along the quad's Y (the particle is aligned to its velocity),
//                   tapered at both ends, brightest towards the head.

uniform bool streak = false;
uniform float energy = 3.0;
// Black hole (simple look): particles within `hole.w` metres of the line of sight to its centre
// `hole.xyz` are hidden by its shadow if they are behind it or close to it (the infall). w = 0: off.
uniform vec4 hole = vec4(0.0);

void vertex() {
	if (!streak) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s,
			INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a;
	float core;
	if (streak) {
		float across = 1.0 - c.x * c.x;
		float head = 0.5 - 0.5 * c.y;  // 1 at the top (head), 0 at the tail
		float along = smoothstep(0.0, 0.25, head) * (1.0 - smoothstep(0.85, 1.0, head));
		a = across * across * along * (0.35 + 0.65 * head);
		core = pow(across, 8.0) * head;
	} else {
		float r = length(c);
		a = exp(-r * r * 5.0) * (1.0 - smoothstep(0.8, 1.0, r));
		core = exp(-r * r * 40.0);
	}
	if (hole.w > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 to_c = hole.xyz - CAMERA_POSITION_WORLD;
		vec3 ray = normalize(wp - CAMERA_POSITION_WORLD);
		bool covered = dot(wp - hole.xyz, to_c) > 0.0 || distance(wp, hole.xyz) < hole.w * 1.6;
		if (covered && length(cross(to_c, ray)) < hole.w) {
			a = 0.0;
		}
	}
	ALBEDO = (COLOR.rgb + vec3(core * 0.8)) * energy;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
