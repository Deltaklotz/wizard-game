shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Ground cover placed entirely on the GPU. The MultiMesh is a fixed grid that the
// script snaps to the player; each grid point hashes its *world* cell, so blades never
// swim when the grid moves. Position, height, density and fade come from the same
// terrain data and material weights as the ground shader.

#include "res://shaders/include/terrain_common.gdshaderinc"
#include "res://shaders/include/stylized_light.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float grass_tiling = 0.6;

uniform float spacing = 0.3;
uniform float seed_offset = 0.0;
// Visible between hole_end and fade_start, fading in/out around them.
uniform float hole_start = -2.0;
uniform float hole_end = -1.0;
uniform float fade_start = 15.0;
uniform float fade_end = 20.0;
uniform float density = 1.0;
// Clumping: only where a noise field exceeds the threshold.
uniform float patch_freq = 0.05;
uniform float patch_threshold = -1.0;
uniform float scale_min = 0.7;
uniform float scale_max = 1.2;
uniform float wind_strength = 0.18;
// 0 grass, 1 flowers (petal colors from a palette).
uniform int kind = 0;
uniform vec3 tip_tint : source_color = vec3(1.4, 1.35, 0.9);
// Lake: xy = center XZ, z = radius (incl. shore), w = water level.
uniform vec4 lake_params = vec4(0.0, 0.0, 0.0, -100000.0);

varying vec3 v_tint;
varying float v_t;
varying vec4 v_col;
varying float v_rand;
varying vec3 v_wpos;

vec4 hash4(vec2 p) {
	vec4 q = vec4(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)), dot(p, vec2(419.2, 371.9)), dot(p, vec2(97.3, 45.1)));
	return fract(sin(q) * 43758.5453);
}

void vertex() {
	vec3 grid_point = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - grid_point;
	vec2 cell = floor(grid_point.xz / spacing + 0.5);
	vec4 h = hash4(cell + seed_offset);
	vec2 root = (cell + (h.xy - 0.5) * 0.95) * spacing;

	float d = distance(root, player_position.xz);
	float s = (1.0 - smoothstep(fade_start, fade_end, d)) * smoothstep(hole_start, hole_end, d);
	float patch_n = textureLod(macro_noise, root * patch_freq + seed_offset * 0.013, 0.0).g;
	float patch_w = smoothstep(patch_threshold, patch_threshold + 0.12, patch_n);
	// Cheap rejections first so culled instances skip the terrain sampling below.
	if (s <= 0.0 || h.z > patch_w * density) {
		VERTEX = vec3(root.x, -1000.0, root.y);
		v_tint = vec3(0.0);
		v_t = 0.0;
		v_col = vec4(0.0);
		v_rand = 0.0;
		v_wpos = VERTEX;
	} else {
	float gh = terrain_height(root);
	vec3 n = terrain_base_normal(root);
	vec2 uv = terrain_uv(root);
	vec3 macro = textureLod(macro_noise, root * 0.0035, 0.0).rgb;
	vec3 macro2 = textureLod(macro_noise, root * 0.021, 0.0).rgb;
	float grass_w;
	float dirt_w;
	float moss_w;
	float rock_w;
	float snow_w;
	terrain_weights(gh, n, textureLod(control_map, uv, 0.0), textureLod(rock_map, uv, 0.0).r, macro, macro2,
			grass_w, dirt_w, moss_w, rock_w, snow_w);
	if (h.z > smoothstep(0.35, 0.8, grass_w) * patch_w * density) {
		s = 0.0;
	}
	if (distance(root, lake_params.xy) < lake_params.z && gh < lake_params.w + 0.15) {
		s = 0.0;
	}
	if (distance(root, flat_zone.xy) < flat_zone.z + 0.3) {
		s = 0.0;
	}
	s *= mix(scale_min, scale_max, h.w) * mix(0.6, 1.0, grass_w);

	float yaw = h.x * 6.2831 + h.y * 17.0;
	float cy = cos(yaw);
	float sy = sin(yaw);
	local = vec3(local.x * cy - local.z * sy, local.y, local.x * sy + local.z * cy) * s;

	// Wind gusts travelling across the field, stronger near the tips.
	float bend = UV.y * UV.y;
	float gust = sin(TIME * 1.1 + root.x * 0.08 + root.y * 0.05) * 0.5 + 0.5;
	vec2 wind = vec2(sin(TIME * 1.7 + root.x * 0.35 + root.y * 0.2), cos(TIME * 1.4 + root.y * 0.3)) * (0.4 + gust);
	// Blades part around the player.
	vec2 away = root - player_position.xz;
	float pd = length(away);
	vec2 push = pd > 0.001 ? away / pd * (1.0 - smoothstep(0.3, 1.1, pd)) * 0.6 : vec2(0.0);
	local.xz += (wind * wind_strength + push) * bend * max(local.y, 0.0) * 2.0;
	local.y *= 1.0 - dot(push, push) * 0.5 * bend;

	VERTEX = vec3(root.x, gh, root.y) + local;
	// Mostly the ground normal: grass is lit like the surface it covers.
	NORMAL = normalize(mix(n, NORMAL, 0.25));

	vec3 ground = textureLod(grass_albedo, root * grass_tiling, 3.0).rgb;
	ground *= mix(vec3(0.82, 0.92, 0.72), vec3(1.12, 1.02, 0.78), macro.r);
	ground *= 0.85 + 0.3 * macro2.g;
	v_tint = ground;
	v_t = UV.y;
	v_col = COLOR;
	v_rand = h.z;
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
		// Flower centers / seed heads.
		col = kind == 1 ? vec3(0.85, 0.6, 0.12) : vec3(0.62, 0.52, 0.32) * (0.8 + 0.4 * v_col.r);
	} else if (v_col.g > 0.5) {
		col = petal_color(fract(v_rand * 7.13));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.06;
	AO = mix(0.5, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.5;
	BACKLIGHT = col * 0.35;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.55, 0.85, vec3(1.25, 1.15, 0.5), 0.0);
}
