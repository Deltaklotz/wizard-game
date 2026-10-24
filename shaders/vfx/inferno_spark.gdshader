shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Dashed white-hot streak racing down the Infernal Torrent (InfernoBeam): a thin line along the
// quad's Y (aligned to the particle's velocity) broken into dashes, like the dotted spark trails
// of a hand-drawn fire. Colour and fade from the particle COLOR.

uniform float energy = 2.5;
uniform float dashes = 5.0;
uniform vec2 near_fade = vec2(0.8, 3.0);
// Where the torrent currently ends (a shield, wall or the ground): billows / sparks that flew
// past it are cut off there, so they don't pass through what stopped the beam. Set per
// frame by InfernoBeam; the defaults (no end) leave the impact splash untouched.
uniform vec3 beam_origin = vec3(0.0);
uniform vec3 beam_dir = vec3(0.0, 0.0, -1.0);
uniform float beam_len = 1e9;

varying float v_seed;
varying vec3 v_world;

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
	v_world = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float across = 1.0 - c.x * c.x;
	float head = 0.5 - 0.5 * c.y;
	float dash = step(0.42, fract(UV.y * dashes + v_seed * 7.0));
	float along = smoothstep(0.0, 0.2, head) * (1.0 - smoothstep(0.9, 1.0, head));
	float a = pow(across, 3.0) * along * dash * (0.3 + 0.7 * head);
	float fade = smoothstep(near_fade.x, near_fade.y, distance(v_world, CAMERA_POSITION_WORLD));
	ALBEDO = (COLOR.rgb + vec3(pow(across, 10.0)) * 0.6) * energy;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float past = smoothstep(beam_len - 0.6, beam_len, dot(wp - beam_origin, beam_dir));
	ALPHA = clamp(a * COLOR.a * fade * (1.0 - past), 0.0, 1.0);
}
