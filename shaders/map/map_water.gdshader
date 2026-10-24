shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// Ink-drawn lake on the map: ripple rings drifting in from the shore and short wavy
// strokes sliding across the open water. COLOR.r = 0 at the shore, 1 at the centre.

uniform vec3 water_color : source_color = vec3(0.66, 0.7, 0.65);
uniform vec3 ink : source_color = vec3(0.18, 0.12, 0.08);
uniform float opacity = 0.88;

varying float v_shore;
varying vec2 v_p;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	v_shore = COLOR.r;
	v_p = VERTEX.xz;
}

void fragment() {
	vec3 col = water_color * (0.92 + 0.1 * v_shore);
	float rr = v_shore * 9.0 - TIME * 0.35;
	float ring = abs(fract(rr) - 0.5);
	float rw = fwidth(rr) * 1.3;
	float rings = (1.0 - smoothstep(0.05, 0.05 + rw, ring)) * (1.0 - smoothstep(0.08, 0.4, v_shore));
	vec2 q = v_p * vec2(5.0, 9.0) + vec2(TIME * 0.25, 0.0);
	float row = floor(q.y);
	float wave = abs(fract(q.y + 0.18 * sin(q.x * 3.0 + TIME * 1.4 + row)) - 0.5);
	float ww = fwidth(q.y) * 1.3;
	float dash = step(0.62, h1(row * 7.1 + floor(q.x * 0.6 + h1(row) * 5.0)));
	float strokes = (1.0 - smoothstep(0.04, 0.04 + ww, wave)) * dash * smoothstep(0.3, 0.55, v_shore);
	ALBEDO = mix(col, ink, max(rings * 0.55, strokes * 0.5));
	ALPHA = opacity;
}
