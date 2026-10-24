shader_type canvas_item;
// Black hole proximity (Hud): chromatic aberration creeping in from the screen edges like
// flailing roots. The roots are only a soft mask (0..1) for where and how strongly the colour
// split is applied – no tint, no outlines. ROOTS strands grow inwards from points spread around
// the border: very wide at the edge, tapering to a point, wiggling along their length, swaying
// over time and forking once; plus a soft band all round the edge. Everything reaches further
// the stronger `intensity` (0..1, how close the hole is) gets; roots on the hole's side of the
// screen reach a little further.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
// Where the hole is on screen (may be off screen).
uniform vec2 focus = vec2(0.5, 0.5);

// Strands round the border (16; 6 with "Fancy black hole" off).
uniform int roots = 16;

float h1(float n) {
	return fract(sin(n * 127.1 + 3.7) * 43758.5453);
}

// Point on the screen border (centred coords) at perimeter fraction s (0..1).
vec2 border_point(float s, vec2 hs) {
	float per = 4.0 * (hs.x + hs.y);
	float l = fract(s) * per;
	if (l < 2.0 * hs.x) {
		return vec2(-hs.x + l, -hs.y);
	}
	l -= 2.0 * hs.x;
	if (l < 2.0 * hs.y) {
		return vec2(hs.x, -hs.y + l);
	}
	l -= 2.0 * hs.y;
	if (l < 2.0 * hs.x) {
		return vec2(hs.x - l, hs.y);
	}
	l -= 2.0 * hs.x;
	return vec2(-hs.x, hs.y - l);
}

// Soft coverage of one strand from `base` along `dir` (0..1): wide near the screen edge,
// tapering to a point, feathered across its whole width and towards its tip.
float strand(vec2 p, vec2 base, vec2 dir, float len, float width, float seed, float t) {
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 q = p - base;
	float along = dot(q, dir);
	if (len <= 0.0 || along > len) {
		return 0.0;
	}
	float u = clamp(along / len, 0.0, 1.0);
	// Wiggle grows towards the tip; the whole strand sways.
	float wig = sin(along * (18.0 + seed * 14.0) + t * (1.6 + seed) + seed * 40.0) * 0.022 * (0.3 + u)
		+ sin(along * 41.0 - t * 2.3 + seed * 13.0) * 0.008 * u
		+ sin(t * 0.8 + seed * 9.0) * 0.06 * u * u;
	float side = abs(dot(q, perp) - wig);
	// Root flare: several times wider where it leaves the edge.
	float w = width * (0.35 * pow(1.0 - u, 0.7) + 2.6 * pow(1.0 - u, 3.0));
	float m = 1.0 - smoothstep(0.0, w, side);
	m = m * m * (3.0 - 2.0 * m);
	return m * (1.0 - smoothstep(0.6, 1.0, u));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 hs = vec2(aspect * 0.5, 0.5);
	vec2 q = hs - abs(p);
	float d = min(q.x, q.y);
	float t = TIME;
	float k = intensity;
	vec2 fp = (focus - 0.5) * vec2(aspect, 1.0);

	// Soft band all round the edge.
	float mask = (1.0 - smoothstep(0.0, 0.03 + 0.07 * k, d)) * smoothstep(0.0, 0.05, k);
	for (int i = 0; i < roots; i++) {
		float fi = float(i);
		float s = (fi + 0.5 + (h1(fi) - 0.5) * 0.6) / float(roots);
		vec2 base = border_point(s, hs) * 1.02;
		vec2 to_center = normalize(-base);
		float ang = (h1(fi + 7.0) - 0.5) * 0.8 + sin(t * 0.6 + fi * 1.7) * 0.12;
		vec2 dir = vec2(cos(ang) * to_center.x - sin(ang) * to_center.y, sin(ang) * to_center.x + cos(ang) * to_center.y);
		// Roots on the hole's side of the screen reach further.
		float toward = clamp(dot(normalize(base), normalize(fp + 1e-4)), 0.0, 1.0);
		float len = k * (0.14 + 0.4 * h1(fi + 3.0)) * (1.0 + 0.4 * toward) * (0.92 + 0.08 * sin(t * 1.9 + fi));
		float width = (0.022 + 0.03 * h1(fi + 5.0)) * (0.6 + 0.8 * k);
		mask = max(mask, strand(p, base, dir, len, width, h1(fi + 11.0), t));
		// One fork splitting off part way along.
		float fu = 0.3 + 0.35 * h1(fi + 13.0);
		float fang = (h1(fi + 17.0) > 0.5 ? 0.55 : -0.55);
		vec2 fdir = vec2(cos(fang) * dir.x - sin(fang) * dir.y, sin(fang) * dir.x + cos(fang) * dir.y);
		mask = max(mask, strand(p, base + dir * len * fu, fdir, len * (1.0 - fu) * 0.75,
			width * (1.0 - fu) * 0.5, h1(fi + 19.0), t));
	}

	if (mask <= 0.002) {
		COLOR = vec4(texture(screen_tex, uv).rgb, 1.0);
	} else {
		// The colour split eases in with the mask.
		vec2 dir_uv = -normalize(p + 1e-4) / vec2(aspect, 1.0);
		float split = mask * 0.045 * (0.5 + k);
		vec2 wobble = vec2(sin(t * 3.0 + p.x * 40.0), cos(t * 2.4 + p.y * 33.0)) * 0.003 * k * mask;
		float r = texture(screen_tex, uv + dir_uv * split + wobble).r;
		float g = texture(screen_tex, uv + wobble * 0.5).g;
		float b = texture(screen_tex, uv - dir_uv * split + wobble).b;
		COLOR = vec4(r, g, b, 1.0);
	}
}
