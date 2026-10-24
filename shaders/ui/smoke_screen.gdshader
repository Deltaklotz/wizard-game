shader_type canvas_item;
// Inside a smoke cloud (Hud): the view drowns in drifting grey smoke - blurred, desaturated and
// covered by churning fog that thins a little now and then. intensity 0..1 (density at the eye).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
uniform vec3 tint : source_color = vec3(0.56, 0.55, 0.61);

// Sine-free hash: stays random at large coordinates.
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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = vec2(uv.x * aspect, uv.y) * 2.5;
	float n = fbm(p + vec2(TIME * 0.12, -TIME * 0.05) + fbm(p * 0.7 - TIME * 0.08) * 1.5);
	vec3 scene = textureLod(screen_tex, uv, 3.0 * intensity).rgb;
	float grey = dot(scene, vec3(0.3, 0.59, 0.11));
	scene = mix(scene, vec3(grey), intensity * 0.6);
	float fog = clamp(intensity * (0.72 + 0.4 * n), 0.0, 0.97);
	vec3 smoke = tint * (0.75 + 0.45 * n);
	COLOR = vec4(mix(scene, smoke, fog), 1.0);
}
