shader_type spatial;

// Stacked page edges with a worn gilt finish. UV.y is height in meters.
uniform vec3 paper_color : source_color = vec3(0.82, 0.74, 0.58);
uniform vec3 gilt_color : source_color = vec3(0.86, 0.63, 0.27);
uniform float gilt : hint_range(0.0, 1.0) = 0.55;
uniform float lines_per_meter = 2400.0;

float pe_hash(float x) {
	return fract(sin(x * 91.345) * 47453.5453);
}

void fragment() {
	float s = UV.y * lines_per_meter;
	float leaf = floor(s);
	float line = abs(fract(s) - 0.5) * 2.0;
	float gap = smoothstep(0.7, 1.0, line);
	// Fade the lines out before they start to alias.
	gap *= 1.0 - smoothstep(0.35, 0.8, fwidth(s));
	float wear = pe_hash(leaf) * 0.35 + 0.65 * smoothstep(0.2, 0.9, pe_hash(floor(UV.x * 40.0) + leaf * 0.1));
	float g = gilt * mix(0.55, 1.0, wear);
	vec3 base = mix(paper_color, gilt_color, g);
	ALBEDO = base * (1.0 - gap * 0.5);
	METALLIC = g * 0.75 * (1.0 - gap);
	ROUGHNESS = mix(0.85, 0.3, g);
}
