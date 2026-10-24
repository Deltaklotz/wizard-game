shader_type canvas_item;

// Title screen backdrop: a violet night sky with twinkling stars and drifting nebula,
// a slowly turning magic circle behind the title, layered mountain silhouettes with
// floating islands above them, valley mist and rising motes.

uniform vec2 resolution = vec2(1280.0, 720.0);
uniform vec2 circle_center = vec2(0.5, 0.3);
uniform vec3 rune_color : source_color = vec3(0.95, 0.75, 0.4);

// Sine-free hash: stays smooth for large inputs (sin-based hashes turned blocky).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float line_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float magic_circle(vec2 p, float t) {
	float r = length(p);
	float ang = atan(p.y, p.x);
	float px = 1.5 / resolution.y;
	float g = 0.0;
	g += smoothstep(px * 2.0, 0.0, abs(r - 0.33));
	g += smoothstep(px * 2.0, 0.0, abs(r - 0.305)) * 0.8;
	g += smoothstep(px * 2.0, 0.0, abs(r - 0.21)) * 0.7;
	g += smoothstep(px * 1.5, 0.0, abs(r - 0.12)) * 0.5;
	// Rune ticks between the outer rings, turning against the circle.
	float ra = ang + t * 0.6;
	float cell = floor(ra / 6.2831 * 40.0);
	float f = fract(ra / 6.2831 * 40.0);
	float rune = step(0.25, f) * step(f, 0.25 + 0.5 * hash(vec2(cell, 3.0)));
	g += rune * step(0.312, r) * step(r, 0.323) * 0.9;
	// Hexagram.
	float star = 1e3;
	for (int k = 0; k < 6; k++) {
		float a0 = t + float(k) * 2.0944 + (k >= 3 ? 1.0472 : 0.0);
		float a1 = a0 + 2.0944;
		star = min(star, line_dist(p, vec2(cos(a0), sin(a0)) * 0.21, vec2(cos(a1), sin(a1)) * 0.21));
	}
	g += smoothstep(px * 2.0, 0.0, star) * 0.7;
	return g;
}

float ridge(float x, float seed, float height, float rough) {
	return height + (fbm(vec2(x * rough, seed)) - 0.5) * 0.35 + (noise(vec2(x * rough * 6.0, seed + 4.0)) - 0.5) * 0.03;
}

void fragment() {
	vec2 uv = UV;
	float aspect = resolution.x / resolution.y;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME;

	// Sky.
	vec3 col = mix(vec3(0.16, 0.09, 0.22), vec3(0.025, 0.02, 0.07), smoothstep(0.85, 0.0, uv.y));
	float neb = fbm(p * 2.2 + vec2(t * 0.01, 0.0));
	col += vec3(0.28, 0.12, 0.38) * pow(neb, 3.0) * 0.9;
	col += vec3(0.08, 0.18, 0.35) * pow(fbm(p * 3.1 - vec2(t * 0.008, 4.0)), 4.0) * 1.2;
	// Stars.
	vec2 sg = p * 180.0;
	vec2 cell = floor(sg);
	float h = hash(cell);
	if (h > 0.985) {
		vec2 sp = vec2(hash(cell + 1.3), hash(cell + 2.7));
		float d = length(fract(sg) - sp);
		float tw = 0.6 + 0.4 * sin(t * (1.0 + h * 3.0) + h * 40.0);
		col += vec3(0.95, 0.9, 1.0) * smoothstep(0.12, 0.0, d) * tw * (1.0 - uv.y * 0.8);
	}

	// Magic circle behind the title.
	vec2 cc = vec2(circle_center.x * aspect, circle_center.y);
	float mc = magic_circle(p - cc, t * 0.05);
	col += rune_color * mc * 0.35;
	col += rune_color * 0.05 * smoothstep(0.45, 0.0, length(p - cc));

	// Floating islands far away.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 ic = vec2((0.18 + fi * 0.33) * aspect + sin(t * 0.1 + fi) * 0.01, 0.52 - fi * 0.04 + sin(t * 0.3 + fi * 2.0) * 0.008);
		vec2 q = (p - ic) / vec2(0.09 - fi * 0.015, 0.05);
		float top = step(-0.25 + (noise(vec2(q.x * 4.0, fi)) - 0.5) * 0.25, q.y);
		float under = step(q.y, 0.2 + (1.0 - q.x * q.x) * 1.2 + (noise(vec2(q.x * 8.0, fi + 9.0)) - 0.5) * 0.3);
		float body = top * under * step(abs(q.x), 1.0 - max(q.y, 0.0) * 0.3);
		col = mix(col, vec3(0.07, 0.05, 0.1), body * 0.85);
	}

	// Mountain layers, each lighter with distance, with mist between them.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float y = ridge(p.x + fi * 3.1, fi * 7.0, 0.63 + fi * 0.11, 1.4 + fi * 0.6);
		vec3 layer = mix(vec3(0.13, 0.09, 0.19), vec3(0.03, 0.02, 0.05), fi / 2.0);
		float m = smoothstep(y, y + 0.002, uv.y);
		col = mix(col, layer, m);
		float mist = smoothstep(y + 0.12, y, uv.y) * smoothstep(y - 0.06, y + 0.02, uv.y);
		col += vec3(0.25, 0.18, 0.32) * mist * 0.12 * (fbm(vec2(p.x * 3.0 - t * 0.02, fi)) + 0.3);
	}

	// Rising motes.
	for (int i = 0; i < 24; i++) {
		float fi = float(i);
		float speed = 0.02 + hash(vec2(fi, 1.0)) * 0.03;
		vec2 mp = vec2(hash(vec2(fi, 2.0)) * aspect + sin(t * 0.4 + fi) * 0.02, 1.1 - fract(t * speed + hash(vec2(fi, 3.0))) * 1.2);
		float d = length(p - mp);
		float flick = 0.6 + 0.4 * sin(t * 3.0 + fi * 1.7);
		col += rune_color * smoothstep(0.006, 0.0, d) * flick * 0.8 + rune_color * smoothstep(0.03, 0.0, d) * 0.08;
	}

	// Vignette.
	col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.3, 2.5);
	COLOR = vec4(col, 1.0);
}
