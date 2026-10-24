shader_type spatial;
render_mode cull_disabled;

// Lily pads and flowers floating on the lake; they bob and drift very slightly.
// Pads: UV = (angle / TAU, radius). COLOR.g = petal, COLOR.b = stamen.

uniform vec3 pad_color : source_color = vec3(0.16, 0.36, 0.1);
uniform vec3 pad_old : source_color = vec3(0.42, 0.4, 0.14);
uniform vec3 rim_color : source_color = vec3(0.45, 0.16, 0.12);

varying float v_rand;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	v_rand = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float t = TIME * 0.7 + v_rand * 6.2831;
	VERTEX.y += sin(t + VERTEX.x * 2.0) * 0.006 + sin(t * 0.6) * 0.008;
}

void fragment() {
	vec3 col;
	if (COLOR.g > 0.5) {
		vec3 petal = v_rand > 0.5 ? vec3(0.97, 0.94, 0.95) : vec3(0.96, 0.62, 0.75);
		col = mix(petal * 0.85, petal, UV.y);
	} else if (COLOR.b > 0.5) {
		col = vec3(0.95, 0.75, 0.15);
	} else {
		float angle = UV.x * 6.2831;
		float r = UV.y;
		float veins = smoothstep(0.85, 1.0, abs(sin(angle * 11.0))) * smoothstep(0.1, 0.4, r);
		col = mix(pad_color, pad_old, fract(v_rand * 3.7) * 0.6);
		col *= 0.85 + 0.25 * r;
		col = mix(col, col * 1.35, veins * 0.5);
		col = mix(col, rim_color, smoothstep(0.9, 1.0, r) * 0.6);
	}
	ALBEDO = col;
	ROUGHNESS = COLOR.g > 0.5 ? 0.6 : 0.25;
	SPECULAR = 0.5;
	BACKLIGHT = col * 0.2;
}
