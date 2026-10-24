shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

// Lake surface: animated wave normals, depth-based colour and absorption, refraction of
// the lake bed, sky reflections via the environment, and foam along the shoreline.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 shallow_color : source_color = vec3(0.32, 0.46, 0.36);
uniform vec3 deep_color : source_color = vec3(0.03, 0.1, 0.12);
// How quickly light is absorbed with depth (per meter).
uniform float absorption = 0.55;
uniform float murk = 0.35;
uniform float wave_strength = 0.35;
uniform float refraction = 0.035;
uniform float foam_width = 0.15;
uniform vec2 wind_dir = vec2(0.8, 0.35);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 unpack_xy(vec4 t) {
	return t.xy * 2.0 - 1.0;
}

float scene_depth(vec2 uv, vec3 vertex_view, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	return -v.z - (-vertex_view.z);
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 wind = normalize(wind_dir);
	vec2 n1 = unpack_xy(texture(wave_normal, p * 0.07 + wind * TIME * 0.018));
	vec2 n2 = unpack_xy(texture(wave_normal, p * 0.19 - vec2(wind.y, -wind.x) * TIME * 0.025));
	vec2 n3 = unpack_xy(texture(wave_normal, p * 0.5 + wind * TIME * 0.04));
	vec2 slope = (n1 * 0.55 + n2 * 0.35 + n3 * 0.2) * wave_strength;
	vec3 wn = normalize(vec3(slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Water thickness along the view ray, then refract where it's safe to.
	float thickness = scene_depth(SCREEN_UV, VERTEX, INV_PROJECTION_MATRIX);
	vec2 ruv = SCREEN_UV + slope * refraction * clamp(thickness, 0.0, 2.0);
	float r_thickness = scene_depth(ruv, VERTEX, INV_PROJECTION_MATRIX);
	if (r_thickness < 0.0) {
		ruv = SCREEN_UV;
		r_thickness = thickness;
	}
	vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
	float transmit = exp(-max(r_thickness, 0.0) * absorption);
	vec3 water = mix(shallow_color, deep_color, 1.0 - exp(-max(r_thickness, 0.0) * murk));
	vec3 col = mix(water, bed * mix(vec3(1.0), shallow_color * 2.0, 0.35), transmit);

	// Foam hugging the shore, broken up by the wave pattern.
	float edge = 1.0 - smoothstep(0.0, foam_width, thickness);
	float foam = edge * smoothstep(0.1, 0.6, n1.x * 0.5 + n3.y * 0.5 + 0.5 + sin(TIME * 1.3 + thickness * 18.0) * 0.2);

	foam *= 0.25;
	ALBEDO = vec3(0.85) * foam;
	EMISSION = col * (1.0 - foam);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// Soft contact with the shore.
	ALPHA = smoothstep(0.0, 0.08, thickness);
}
