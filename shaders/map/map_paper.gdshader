shader_type canvas_item;

// Aged parchment for the world map: fibres, blotches, darkened and burnt, torn edges.
// Rendered once into the map texture; alpha 0 outside the torn edge.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void fragment() {
	vec2 uv = UV;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float tear = edge - (fbm(uv * 18.0) - 0.5) * 0.03 - 0.008;
	if (tear < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float n = fbm(uv * 6.0);
		float fibre = noise(uv * vec2(900.0, 120.0)) * 0.5 + noise(uv * 2400.0) * 0.5;
		float blot = smoothstep(0.55, 0.8, fbm(uv * 3.0 + 7.0));
		float age = (n - 0.5) * 0.18 + (1.0 - smoothstep(0.0, 0.12, edge)) * 0.35 + (fibre - 0.5) * 0.05 + blot * 0.08;
		vec3 c = vec3(232.0 - age * 120.0, 214.0 - age * 150.0, 172.0 - age * 170.0) / 255.0;
		// Scorched rim right at the torn edge.
		c *= mix(vec3(0.45, 0.35, 0.3), vec3(1.0), smoothstep(0.0, 0.006, tear));
		// Fold creases in thirds and half.
		float crease = max(max(1.0 - smoothstep(0.0, 0.0012, abs(uv.x - 0.3333)), 1.0 - smoothstep(0.0, 0.0012, abs(uv.x - 0.6667))),
				1.0 - smoothstep(0.0, 0.0012, abs(uv.y - 0.5)));
		c *= 1.0 - crease * 0.07;
		COLOR = vec4(c, 1.0);
	}
}
