shader_type canvas_item;
// Burning (Hud): flames licking up from the bottom of the screen and in from its sides, a warm
// flickering glow at the edges, and a faint heat shimmer. intensity 0..1.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;

// Sine-free hash: stays random at large coordinates (the sin() hash turned blocky there).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Flames rising from one edge: `along` runs along the edge, `depth` = distance from it.
// Returns (flame mask, heat).
vec2 flames(float along, float depth, float reach, float t, float seed) {
	float f = fbm(vec2(along * 9.0 + seed, depth * 5.0 - t * 2.6));
	f += 0.3 * noise(vec2(along * 26.0 - seed, depth * 12.0 - t * 4.2));
	float d = depth / reach;
	float mask = smoothstep(0.0, 0.18, f * 1.15 - d);
	float heat = smoothstep(0.3, 0.95, f * 1.15 - d * 0.75);
	return vec2(mask, heat);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float k = intensity;
	float bottom = 1.0 - uv.y;
	float left = uv.x * aspect;
	float right = (1.0 - uv.x) * aspect;
	// Tall flames from the bottom, lower ones creeping up the sides (fading towards the top).
	vec2 b = flames(uv.x * aspect, bottom, 0.06 + 0.22 * k, t, 0.0);
	float side_fade = smoothstep(0.0, 0.7, uv.y);
	vec2 l = flames(uv.y, left, (0.03 + 0.1 * k) * side_fade, t * 0.9, 17.0);
	vec2 r = flames(uv.y, right, (0.03 + 0.1 * k) * side_fade, t * 0.95, 41.0);
	float mask = max(b.x, max(l.x, r.x));
	float heat = max(b.y, max(l.y, r.y));
	float near_edge = min(bottom, min(left, right) * 1.5);
	// Heat shimmer close to the flames.
	vec2 shimmer = vec2(noise(vec2(uv.x * 40.0, uv.y * 40.0 - t * 6.0)) - 0.5, 0.0) * 0.005 * k
		* (1.0 - smoothstep(0.0, 0.3, near_edge));
	vec3 base = texture(screen_tex, uv + shimmer).rgb;
	vec3 fire = mix(vec3(0.7, 0.1, 0.02), vec3(1.0, 0.5, 0.08), heat);
	fire = mix(fire, vec3(1.0, 0.85, 0.5), smoothstep(0.7, 1.0, heat));
	float flicker = 0.85 + 0.15 * sin(t * 13.0) * sin(t * 7.1);
	float glow = exp(-near_edge * 6.0) * 0.3 * k * flicker;
	vec3 col = mix(base, fire * 1.2, clamp(mask * k, 0.0, 0.85));
	col += vec3(1.0, 0.42, 0.08) * glow;
	COLOR = vec4(col, 1.0);
}
