shader_type canvas_item;
// Arcane crosshair (Hud): a bright centre dot, a ring of three arcs turning slowly in the open
// spell's colour with a soft glow, and four small diamonds pointing in. Everything has a dark
// outline so it reads on sky and snow. On a cast the ring kicks outwards and spins faster.
// Lengths are in "design pixels" (1080p); `px_scale` maps them to the screen.

uniform vec4 tint : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float spin = 0.0;
uniform float pulse = 0.0;
uniform float px_scale = 1.0;
uniform float size_px = 72.0;

float cover(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

// Rhombus with half-diagonals h (x across, y along), centred at c, long axis along `dir`.
float diamond(vec2 p, vec2 c, vec2 dir, vec2 h) {
	vec2 q = p - c;
	vec2 l = vec2(dot(q, vec2(-dir.y, dir.x)), dot(q, dir));
	return (abs(l.x) / h.x + abs(l.y) / h.y - 1.0) * min(h.x, h.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * size_px / px_scale;
	float r = length(p);
	float aa = max(fwidth(r), 0.05) * 0.9;
	float R = 8.5 + pulse * 3.5;

	// Ring in three arcs with gaps.
	float a = fract((atan(p.y, p.x) - spin) / TAU * 3.0);
	float arcs = smoothstep(0.08, 0.16, a) * smoothstep(0.08, 0.16, 1.0 - a);
	float d_ring = abs(r - R) - 0.6;
	float ring = cover(d_ring, aa) * arcs;
	float ring_o = cover(d_ring - 1.1, aa) * arcs;

	float d_dot = r - 1.5;
	float diamonds = 0.0;
	float diamonds_o = 0.0;
	for (int k = 0; k < 4; k++) {
		float t = float(k) * 1.5707963;
		vec2 dir = vec2(cos(t), sin(t));
		float d = diamond(p, dir * (R + 6.5), dir, vec2(1.5, 3.3));
		diamonds = max(diamonds, cover(d, aa));
		diamonds_o = max(diamonds_o, cover(d - 1.1, aa));
	}
	float dot_c = cover(d_dot, aa);
	float outline = max(max(ring_o, diamonds_o), cover(d_dot - 1.1, aa));

	vec3 ring_col = mix(tint.rgb, vec3(1.0), 0.3);
	vec3 accent = mix(vec3(1.0, 0.96, 0.86), tint.rgb, 0.25);
	float glow = exp(-pow((r - R) / 2.6, 2.0)) * arcs * (0.35 + 0.4 * pulse) + exp(-r * r / 6.0) * 0.25;

	vec3 col = vec3(0.0);
	float alpha = outline * 0.5;
	col = mix(col, tint.rgb, glow);
	alpha = max(alpha, glow * 0.8);
	col = mix(col, ring_col, ring);
	col = mix(col, accent, diamonds);
	col = mix(col, vec3(1.0), dot_c);
	alpha = max(alpha, max(max(ring, diamonds), dot_c));
	COLOR = vec4(col, alpha * COLOR.a);
}
