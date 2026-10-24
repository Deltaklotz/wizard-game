shader_type canvas_item;
// Infernal Torrent (Hud): hard-edged black smoke with indigo patches and burning red rims
// curling in from the screen edges, a heat shimmer and a crimson grade. intensity 0..1:
// 1 while caught inside someone's torrent (the caster's own view gets none). `focus` = where the beam
// goes on screen (the smoke streams away from the edges towards it).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
uniform vec2 focus = vec2(0.5, 0.5);

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
	return v / 0.9375;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float k = intensity;
	vec2 c = (uv - focus) * vec2(aspect, 1.0);
	float rad = length(c);
	float ang = atan(c.y, c.x);
	// Distance to the nearest screen edge (aspect-corrected).
	float edge = min(min(uv.x, 1.0 - uv.x) * aspect, min(uv.y, 1.0 - uv.y));
	vec2 ring = vec2(cos(ang), sin(ang));
	// Smoke streams inwards along the radius, swirling slowly.
	float t = TIME;
	float n = fbm(ring * 2.2 + vec2(rad * 3.0 + t * 1.8, -rad * 2.0 - t * 1.1));
	n += 0.35 * (noise(ring * 7.0 + vec2(rad * 9.0 + t * 3.0, t * 0.8)) - 0.5);
	float reach = 0.04 + 0.26 * k;
	float body = n * 1.1 - edge / max(reach, 0.001);
	float w = max(fwidth(body), 0.003);
	float smoke = smoothstep(0.32 - w, 0.32 + w, body);
	float rim = smoothstep(0.27 - w, 0.27 + w, body) - smoke;
	float patch = step(0.62, noise(ring * 3.0 + vec2(rad * 4.0 - t * 0.9, 5.0)));
	vec3 smoke_col = mix(vec3(0.012, 0.005, 0.01), vec3(0.035, 0.018, 0.2), patch);
	// Heat shimmer, strongest near the smoke.
	vec2 wob = vec2(noise(uv * 18.0 + vec2(0.0, -t * 3.0)), noise(uv * 18.0 + vec2(7.0, -t * 3.3))) - 0.5;
	float shimmer = k * (0.003 + 0.008 * smoothstep(0.0, 0.3, body + 0.3));
	vec3 scene = texture(screen_tex, uv + wob * shimmer).rgb;
	// Crimson grade towards the edges.
	float vign = smoothstep(0.15, 0.9, rad);
	scene = mix(scene, scene * vec3(1.15, 0.45, 0.5) + vec3(0.12, 0.0, 0.01) * vign, k * (0.25 + 0.45 * vign));
	vec3 col = mix(scene, smoke_col, smoke);
	col = mix(col, vec3(1.0, 0.04, 0.07) * 1.1, rim * 0.9);
	COLOR = vec4(col, 1.0);
}
