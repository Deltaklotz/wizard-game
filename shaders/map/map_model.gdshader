shader_type spatial;
render_mode unshaded;

// 3D pieces on the map (floating islands, pebbles, the player pin): flat colour with
// soft directional shading, matching the relief on the sheet.

uniform vec3 base_color : source_color = vec3(0.89, 0.81, 0.62);
uniform vec3 light_dir = vec3(-0.55, 0.75, -0.35);
uniform float ambient = 0.62;
uniform float diffuse = 0.45;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lam = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
	ALBEDO = base_color * (ambient + diffuse * lam);
}
