shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Ground cover on the floating islands (IslandGrass): MultiMesh clumps scattered on the island
// tops on the CPU (the terrain grass is placed from the terrain heightmap, which islands don't
// have). Coloured like the island's grass ground (same texture in island object space + macro
// tint), with the terrain grass's wind, player push and distance fade.
// INSTANCE_CUSTOM: xy = island-local XZ of the root, z = random, w = shade.

#include "res://shaders/include/stylized_light.gdshaderinc"

global uniform vec3 player_position;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float grass_tiling = 0.6;
uniform float fade_start = 22.0;
uniform float fade_end = 30.0;
uniform float density = 1.0;
uniform float wind_strength = 0.18;
// 0 grass, 1 flowers (petal colours from a palette).
uniform int kind = 0;
uniform vec3 tip_tint : source_color = vec3(1.4, 1.35, 0.9);
instance uniform float strata_seed = 0.0;
// The island's up axis in world space (islands are tilted a little).
instance uniform vec3 island_up = vec3(0.0, 1.0, 0.0);

varying vec3 v_tint;
varying float v_t;
varying vec4 v_col;
varying float v_rand;
varying vec3 v_wpos;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - root;
	vec4 c = INSTANCE_CUSTOM;
	float d = distance(root, CAMERA_POSITION_WORLD);
	float s = 1.0 - smoothstep(fade_start, fade_end, d);
	if (s <= 0.0 || c.z > density) {
		VERTEX = root - island_up * 1000.0;
		v_tint = vec3(0.0);
		v_t = 0.0;
		v_col = vec4(0.0);
		v_rand = 0.0;
		v_wpos = VERTEX;
	} else {
		local *= s;
		float bend = UV.y * UV.y;
		float gust = sin(TIME * 1.1 + root.x * 0.08 + root.z * 0.05) * 0.5 + 0.5;
		vec2 wind = vec2(sin(TIME * 1.7 + root.x * 0.35 + root.z * 0.2), cos(TIME * 1.4 + root.z * 0.3)) * (0.4 + gust);
		vec3 away = root - player_position;
		away -= island_up * dot(away, island_up);
		float pd = length(away);
		vec3 push = pd > 0.001 && abs(dot(root - player_position, island_up)) < 2.0
			? away / pd * (1.0 - smoothstep(0.3, 1.1, pd)) * 0.6 : vec3(0.0);
		float up_amount = max(dot(local, island_up), 0.0);
		local += (vec3(wind.x, 0.0, wind.y) * wind_strength + push) * bend * up_amount * 2.0;
		local -= island_up * up_amount * dot(push, push) * 0.5 * bend;
		VERTEX = root + local;
		NORMAL = normalize(mix(island_up, NORMAL, 0.25));

		vec3 macro = textureLod(macro_noise, c.xy * 0.01 + strata_seed, 0.0).rgb;
		vec3 ground = textureLod(grass_albedo, c.xy * grass_tiling, 3.0).rgb;
		ground *= mix(vec3(0.85, 0.95, 0.75), vec3(1.1, 1.02, 0.8), macro.r);
		v_tint = ground * (0.85 + 0.3 * c.w);
		v_t = UV.y;
		v_col = COLOR;
		v_rand = c.z;
		v_wpos = VERTEX;
	}
}

vec3 petal_color(float r) {
	if (r < 0.3) return vec3(0.95, 0.95, 0.9);
	if (r < 0.5) return vec3(0.98, 0.82, 0.2);
	if (r < 0.68) return vec3(0.62, 0.35, 0.85);
	if (r < 0.84) return vec3(0.35, 0.5, 0.95);
	return vec3(0.95, 0.45, 0.6);
}

void fragment() {
	vec3 col = mix(v_tint * 0.7, v_tint * tip_tint, smoothstep(0.0, 1.0, v_t));
	col *= 0.8 + 0.4 * v_col.r;
	if (v_col.b > 0.5) {
		col = kind == 1 ? vec3(0.85, 0.6, 0.12) : vec3(0.62, 0.52, 0.32) * (0.8 + 0.4 * v_col.r);
	} else if (v_col.g > 0.5) {
		col = petal_color(fract(v_rand * 7.13));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.06;
	AO = mix(0.5, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.5;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.55, 0.85, vec3(1.25, 1.15, 0.5), 0.0);
}
