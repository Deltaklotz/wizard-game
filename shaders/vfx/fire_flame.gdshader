shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// One flame particle (FireFx), alpha-blended so its colour stays saturated over bright ground
// (additive washed out to white in daylight): a camera-facing tongue of fire – a teardrop narrowing upwards,
// torn by scrolling noise, white-yellow at its root and hot centre, orange to red at the edges.
// Colour/fade over the particle's life come from COLOR (ParticleProcessMaterial colour ramp);
// INSTANCE_CUSTOM.y = age 0..1.

uniform float energy = 1.4;
uniform float stretch = 1.0;

varying float v_age;
varying float v_seed;

// Sine-free hash: stays random at large coordinates (the sin() hash turned blocky there).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s * stretch,
		INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c.y = -c.y;  // +y up
	float t = TIME * 2.4 + v_seed * 17.0;
	// Noise tears the flame: stronger towards the tip, scrolling upwards.
	float up = clamp(c.y * 0.5 + 0.5, 0.0, 1.0);
	float n = noise(vec2(c.x * 2.2 + v_seed * 9.0, c.y * 1.8 - t * 1.6));
	float n2 = noise(vec2(c.x * 5.5 - v_seed * 5.0, c.y * 4.5 - t * 2.8));
	float n3 = noise(vec2(c.x * 11.0 + v_seed * 3.0, c.y * 9.0 - t * 4.0));
	vec2 q = c;
	q.x += (n - 0.5) * (0.4 + 0.9 * up) + (n2 - 0.5) * 0.25 * up;
	// Teardrop: wide round base, narrowing to a ragged tip.
	float width = mix(0.7, 0.1, up);
	float body = 1.0 - length(vec2(q.x / width, (q.y + 0.3) * 0.8));
	// Wisps break off towards the tip.
	body -= (1.0 - (n2 * 0.6 + n3 * 0.4)) * up * 0.7;
	body = clamp(body, 0.0, 1.0);
	float inner = smoothstep(0.08, 0.55, body);
	float core = smoothstep(0.45, 0.9, body) * (1.0 - v_age);
	vec3 rim = vec3(0.8, 0.16, 0.03);
	vec3 col = mix(rim, COLOR.rgb, inner);
	col = mix(col, vec3(1.0, 0.85, 0.5), core * 0.75);
	ALBEDO = col * energy;
	ALPHA = clamp(smoothstep(0.0, 0.45, body) * COLOR.a * 0.9, 0.0, 1.0);
}
