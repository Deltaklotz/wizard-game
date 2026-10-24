shader_type canvas_item;

// Blurred, tinted copy of the game behind the pause menu.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 3.0;
uniform vec4 tint : source_color = vec4(0.05, 0.03, 0.08, 0.55);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	vec2 d = SCREEN_UV - 0.5;
	float vignette = 1.0 - dot(d, d) * 0.9;
	COLOR = vec4(mix(c, tint.rgb, tint.a) * vignette, 1.0);
}
