// Shared procedural parchment used by the static pages and the flipping leaf.

uniform vec3 paper_color : source_color = vec3(0.95, 0.87, 0.70);
uniform vec3 aged_color : source_color = vec3(0.66, 0.48, 0.28);

float gp_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(gp_hash(i), gp_hash(i + vec2(1.0, 0.0)), u.x),
			mix(gp_hash(i + vec2(0.0, 1.0)), gp_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float gp_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * gp_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// uv.x = 0 at the gutter, 1 at the fore edge. seed makes every page face unique.
vec3 parchment(vec2 uv, float seed) {
	vec2 o = vec2(seed * 3.17, seed * 5.71);
	float n = gp_fbm(uv * vec2(6.0, 8.5) + o);
	float fine = gp_noise((uv + o) * vec2(190.0, 270.0));
	vec2 e = min(uv, 1.0 - uv);
	float edge = 1.0 - smoothstep(0.0, 0.1, min(e.x, e.y));
	float stain = smoothstep(0.58, 0.82, gp_fbm(uv * 2.6 + o * 1.7));
	float age = clamp(edge * 0.75 + (n - 0.5) * 0.4 + stain * 0.3, 0.0, 1.0);
	vec3 c = mix(paper_color, aged_color, age);
	// Pages darken into the gutter where light can't reach.
	c *= mix(0.45, 1.0, smoothstep(0.0, 0.14, uv.x));
	return c * (0.93 + 0.07 * fine);
}

// Direct light on the pages (call from light()). Plain Lambert, but the light reaching the
// paper is softly compressed: facing away from the sun, the near-white pages caught it head-on
// at about twice the glow threshold, bloomed and washed out the ink. Dim light is nearly
// unchanged; the brightest the paper gets stays readable. light_color is LIGHT_COLOR (energy × π).
vec3 page_diffuse(vec3 n, vec3 l, vec3 light_color, float atten) {
	vec3 d = light_color / PI * atten * max(dot(n, l), 0.0);
	return d / (1.0 + d * 0.7);
}

// Arcane circle behind the spell symbol (the rune-ring look of the spell effects): double outer
// ring with node dots, a band of rune ticks, a hexagram and inner rings. Returns ink coverage
// 0..1. In page pixels (360×510, centred at 180,255); `angle` turns it (the cooldown spin), the
// hexagram counter-turns a little.
float gp_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float arcane_circle(vec2 uv, float angle) {
	vec2 p = (uv - vec2(0.5)) * vec2(360.0, 510.0);
	float r = length(p);
	const float R = 142.0;
	if (r > R + 6.0) {
		return 0.0;
	}
	float aa = max(fwidth(r), 0.35);
	float ang = atan(p.y, p.x) - angle;
	float m = 0.0;
	// Rings (width in px).
	m = max(m, 1.0 - smoothstep(1.3, 1.3 + aa, abs(r - R)));
	m = max(m, 1.0 - smoothstep(0.6, 0.6 + aa, abs(r - (R - 7.0))));
	m = max(m, 1.0 - smoothstep(0.6, 0.6 + aa, abs(r - R * 0.76)));
	m = max(m, 1.0 - smoothstep(0.9, 0.9 + aa, abs(r - R * 0.7)));
	m = max(m, 1.0 - smoothstep(0.6, 0.6 + aa, abs(r - R * 0.3)));
	// Eight nodes on the outer ring – they make the turning easy to see.
	float node_a = (floor(ang / TAU * 8.0) + 0.5) / 8.0 * TAU;
	vec2 node = vec2(cos(node_a + angle), sin(node_a + angle)) * (R - 3.5);
	m = max(m, 1.0 - smoothstep(3.6, 3.6 + aa, length(p - node)));
	// Rune band between 0.76 R and R - 7: radial ticks of varying length, a few with a crossbar.
	if (r > R * 0.76 && r < R - 7.0) {
		float seg = ang / TAU * 36.0;
		float id = floor(seg);
		float f = (fract(seg) - 0.5) * (TAU * r / 36.0);
		float len = mix(0.35, 1.0, gp_hash(vec2(id, 3.0)));
		float t = (r - R * 0.76) / (R - 7.0 - R * 0.76);
		float tick = (1.0 - smoothstep(0.8, 0.8 + aa, abs(f))) * step(t, len) * step(0.2, gp_hash(vec2(id, 9.0)));
		float bar = (1.0 - smoothstep(0.6, 0.6 + aa, abs(t - 0.5) * 20.0)) * step(abs(f), 4.0) * step(0.7, gp_hash(vec2(id, 5.0)));
		m = max(m, max(tick, bar));
	}
	// Hexagram in the inner circle.
	float rs = R * 0.7;
	for (int k = 0; k < 6; k++) {
		float t0 = float(k) * 1.0471976 - angle * 0.4;
		vec2 a0 = vec2(cos(t0), sin(t0)) * rs;
		vec2 a1 = vec2(cos(t0 + 2.0943951), sin(t0 + 2.0943951)) * rs;
		m = max(m, 1.0 - smoothstep(0.7, 0.7 + aa, gp_seg(p, a0, a1)));
	}
	return m;
}
