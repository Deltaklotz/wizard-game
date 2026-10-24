shader_type spatial;
render_mode cull_back;

// Distant mountain ring outside the playable map. Cheap: large-scale texturing only,
// the fog does most of the work.

#include "res://shaders/include/triplanar.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float snow_height = 330.0;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(v_normal);
	vec3 macro = texture(macro_noise, v_world.xz * 0.0015).rgb;
	vec3 bw = triplanar_weights(n, 4.0);
	vec3 rock = triplanar_sample(rock_albedo, v_world * 0.02, bw).rgb * mix(0.8, 1.1, macro.g);
	vec3 grass = texture(grass_albedo, v_world.xz * 0.05).rgb * vec3(0.75, 0.85, 0.7);
	vec3 snow = texture(snow_albedo, v_world.xz * 0.02).rgb;
	float slope = 1.0 - n.y;
	float rock_w = smoothstep(0.18, 0.32, slope + (macro.r - 0.5) * 0.15);
	float snow_w = smoothstep(snow_height - 30.0, snow_height + 30.0, v_world.y + (macro.b - 0.5) * 80.0) * (1.0 - smoothstep(0.4, 0.65, slope));
	vec3 c = mix(grass, rock, rock_w);
	c = mix(c, snow, snow_w);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
