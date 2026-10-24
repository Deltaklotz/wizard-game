shader_type canvas_item;
// Spectral chain grab flash (Hud): when a chain grabs, a thin ring of chain links snaps in
// along the screen border with a narrow yellow-green ghost glow and a light wave rushing
// inwards, all gone within a third of a second (intensity 1 -> 0).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
uniform vec3 color : source_color = vec3(0.72, 1.0, 0.32);
uniform vec3 accent : source_color = vec3(1.0, 0.93, 0.42);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Links along a line: `along` runs along the border, `across` = distance from the chain's
// centre line. Alternating face-on rings and edge-on bars, interlocking.
float links(float along, float across, float pitch) {
	float best = 0.0;
	float s = along / pitch;
	for (int k = -1; k <= 1; k++) {
		float cell = floor(s) + float(k);
		vec2 lp = vec2((s - cell - 0.5) * pitch, across + (hash(vec2(cell, 3.0)) - 0.5) * 0.003);
		float v;
		if (mod(cell, 2.0) < 1.0) {
			float r = length(lp / vec2(pitch * 0.72, 0.015));
			v = smoothstep(0.3, 0.05, abs(r - 1.0) * 1.6);
		} else {
			float r = length(lp / vec2(pitch * 0.72, 0.0045));
			v = smoothstep(1.15, 0.7, r);
		}
		best = max(best, v);
	}
	return best;
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 q = vec2(aspect * 0.5, 0.5) - abs(p);
	float d = min(q.x, q.y);
	bool side = q.x < q.y;
	float along = side ? p.y : p.x;

	// Narrow ghost glow hugging the border.
	float n = noise(vec2(along * 9.0 + TIME * 2.0, d * 20.0 - TIME * 4.0));
	float glow = exp(-d * 34.0) * (0.4 + 0.8 * n);
	// Thin wave rushing inwards as the flash fades.
	float wave = exp(-abs(d - (1.0 - intensity) * 0.1) * 120.0) * intensity;

	// The links snap in from the very edge and rattle along it while fading.
	float inset = mix(0.0, 0.03, smoothstep(1.0, 0.8, intensity));
	float l = links(along + (1.0 - intensity) * 0.06 * (side ? 1.0 : -1.0), d - inset, 0.05);
	l *= smoothstep(0.0, 0.04, abs(q.x - q.y));  // edges meet at the corners

	float link_a = l * clamp(intensity * 1.4, 0.0, 1.0);
	float glow_a = glow * intensity * intensity * 0.6 + wave * 0.4;
	vec3 col = mix(color, accent, clamp(l * 0.7 + wave * 0.5, 0.0, 1.0));
	COLOR = vec4(col, clamp(max(link_a * 0.9, glow_a), 0.0, 0.85));
}
