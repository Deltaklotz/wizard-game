shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// A spell page lying in the world (WorldItem): parchment with the spell's ink artwork on the
// front (the back shows it faintly bleeding through, mirrored), darker worn edges, and a glowing
// rim in the rarity colour that pulses. Primordial pages are scorched dark with violet-white
// glowing ink and a rim of black fire.

uniform sampler2D ink : source_color, filter_linear_mipmap;
uniform vec3 glow_color : source_color = vec3(0.35, 0.62, 1.0);
uniform bool primordial = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = FRONT_FACING ? UV : vec2(1.0 - UV.x, UV.y);
	vec2 e = min(uv, 1.0 - uv);
	float edge = min(e.x * 0.71, e.y);  // page aspect 0.71
	float n = noise(uv * 18.0) * 0.6 + noise(uv * 60.0) * 0.4;
	vec4 ink_c = texture(ink, uv);
	float ink_a = ink_c.a * (FRONT_FACING ? 1.0 : 0.18);
	float rim = exp(-edge * 40.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.5);
	vec3 col;
	vec3 emission;
	if (primordial) {
		vec3 paper = vec3(0.09, 0.06, 0.12) * (0.7 + 0.5 * n);
		col = mix(paper, vec3(0.0), ink_a);
		// Black fire licking at the edge: dark tongues with violet-white hot seams.
		float flame = noise(vec2(uv.x * 14.0, uv.y * 10.0 - TIME * 1.6)) * exp(-edge * 18.0);
		emission = vec3(0.75, 0.55, 1.0) * ink_a * (1.4 + 0.6 * sin(TIME * 3.0))
			+ vec3(0.55, 0.3, 1.0) * smoothstep(0.35, 0.6, flame) * 1.5 * pulse;
		col = mix(col, vec3(0.0), smoothstep(0.2, 0.5, flame));
	} else {
		vec3 paper = vec3(0.93, 0.86, 0.7) * (0.88 + 0.12 * n);
		paper *= mix(0.72, 1.0, smoothstep(0.0, 0.08, edge));
		col = mix(paper, vec3(0.17, 0.1, 0.05), ink_a);
		emission = glow_color * rim * 2.2 * pulse + glow_color * ink_a * 0.25;
	}
	ALBEDO = col;
	EMISSION = emission;
	ROUGHNESS = 0.9;
}
