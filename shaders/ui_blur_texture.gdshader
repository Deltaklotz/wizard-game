shader_type canvas_item;

// Blurred, tinted still of the game (captured when the map opens).
uniform float blur = 3.5;
uniform vec4 tint : source_color = vec4(0.06, 0.04, 0.03, 0.45);

void fragment() {
	vec3 c = textureLod(TEXTURE, UV, blur).rgb;
	vec2 d = UV - 0.5;
	COLOR = vec4(mix(c, tint.rgb, tint.a) * (1.0 - dot(d, d) * 0.9), 1.0);
}
