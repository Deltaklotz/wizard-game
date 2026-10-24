shader_type canvas_item;
// Sniper scope overlay: a round lens (slight barrel distortion and chromatic fringe at its
// rim) inside a dark housing with an engraved rune ring, a fine crimson reticle, and a charge
// arc that fills over the minimum aim time and turns gold when the beam can fire.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;   // scope raised (0..1)
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float released = 0.0;                        // cast released: waiting to fire
uniform float fire_flash = 0.0;
uniform float aspect = 1.777;
uniform vec4 reticle : source_color = vec4(1.0, 0.2, 0.22, 1.0);
uniform vec4 gold : source_color = vec4(1.0, 0.82, 0.45, 1.0);

float band(float d, float w, float aa) { return smoothstep(w + aa, w - aa, abs(d)); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float R = mix(0.75, 0.44, smoothstep(0.0, 1.0, amount));   // lens closes in as it is raised
	float aa = SCREEN_PIXEL_SIZE.y * 1.5;

	// Lens: barrel distortion and chromatic fringe towards the rim.
	float rim = pow(clamp(r / R, 0.0, 1.0), 4.0);
	vec2 dir = (uv - 0.5);
	vec2 luv = 0.5 + dir * (1.0 - 0.06 * rim);
	vec3 scene;
	scene.r = texture(screen_tex, 0.5 + (luv - 0.5) * (1.0 + 0.012 * rim)).r;
	scene.g = texture(screen_tex, luv).g;
	scene.b = texture(screen_tex, 0.5 + (luv - 0.5) * (1.0 - 0.012 * rim)).b;
	scene *= 1.0 - 0.35 * rim;                                  // lens vignette

	// Housing outside the lens: near black with an engraved rune ring and faint radial lines.
	float inside = smoothstep(R + aa * 2.0, R - aa * 2.0, r);
	vec3 housing = vec3(0.018, 0.012, 0.02);
	float ring_r = R + 0.035;
	float runes = step(0.5, fract(ang / 6.2831853 * 60.0 + TIME * 0.05)) * band(r - ring_r, 0.008, aa);
	housing += reticle.rgb * 0.08 * runes;
	housing += gold.rgb * 0.12 * band(r - (R + 0.006), 0.004, aa);
	housing *= 1.0 - smoothstep(R, R + 0.5, r) * 0.6;

	// Reticle.
	float v = 0.0;
	float gap = 0.018;
	v += band(p.y, 0.0012, aa) * step(gap, abs(p.x)) * step(abs(p.x), R * 0.92);
	v += band(p.x, 0.0012, aa) * step(gap, abs(p.y)) * step(abs(p.y), R * 0.92);
	// Mil dots along the lines.
	for (int i = 1; i < 6; i++) {
		float d = float(i) * R * 0.15;
		v += smoothstep(0.0042, 0.0028, length(vec2(abs(p.x) - d, p.y)));
		v += smoothstep(0.0042, 0.0028, length(vec2(p.x, abs(p.y) - d)));
	}
	// Thicker posts from the rim.
	v += band(p.y, 0.004, aa) * step(R * 0.7, abs(p.x));
	v += band(p.x, 0.004, aa) * step(R * 0.7, p.y);
	v += smoothstep(0.004, 0.0025, r);
	// Inner rotating arcane ring.
	float spin = TIME * 0.4;
	float seg = step(0.3, fract((ang + spin) / 6.2831853 * 12.0));
	v += band(r - R * 0.3, 0.0015, aa) * seg * 0.6;

	// Charge arc just inside the rim, clockwise from the top.
	float t = fract(atan(p.x, -p.y) / 6.2831853);
	float ready = step(0.999, charge);
	float arc = band(r - R * 0.965, 0.006, aa) * step(t, charge);
	vec3 arc_col = mix(reticle.rgb, gold.rgb, ready) * (1.0 + ready * 0.5 * sin(TIME * 16.0));
	float track = band(r - R * 0.965, 0.006, aa) * 0.15;

	vec3 col = scene;
	col = mix(col, reticle.rgb * 1.3, clamp(v, 0.0, 1.0) * 0.9);
	col += arc_col * arc + reticle.rgb * track;
	// Waiting to fire: the reticle glows hotter.
	col += reticle.rgb * released * (1.0 - ready) * 0.08 * inside;
	col += vec3(1.0, 0.8, 0.7) * fire_flash * 0.15 * inside;
	col = mix(housing, col, inside);

	vec3 base = texture(screen_tex, uv).rgb;
	COLOR = vec4(mix(base, col, amount), 1.0);
}
