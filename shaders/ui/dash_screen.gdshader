shader_type canvas_item;
// Full-screen dash effect: radial motion blur towards the dash focus point, chromatic
// fringes and a violet-blue vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 focus = vec2(0.5);
uniform vec4 tint : source_color = vec4(0.45, 0.55, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.8, 0.55, 1.0, 1.0);
uniform float aspect = 1.777;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	vec2 da = vec2(d.x * aspect, d.y);
	float r = length(da);
	float k = intensity;
	// Blur grows away from the focus; the centre stays sharp.
	float amount = k * 0.065 * smoothstep(0.08, 0.7, r);
	vec3 acc = vec3(0.0);
	const int N = 10;
	for (int i = 0; i < N; i++) {
		float t = float(i) / float(N - 1);
		vec2 o = d * amount * t;
		acc.r += texture(screen_tex, uv - o * 1.12).r;
		acc.g += texture(screen_tex, uv - o).g;
		acc.b += texture(screen_tex, uv - o * 0.88).b;
	}
	vec3 col = acc / float(N);

	// Coloured vignette.
	float vig = smoothstep(0.35, 1.05, r);
	col = mix(col, col * 0.55 + tint.rgb * 0.18, vig * k * 0.8);
	col += accent.rgb * pow(vig, 3.0) * k * 0.25;
	COLOR = vec4(col, 1.0);
}
