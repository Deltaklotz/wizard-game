// Shared by terrain.gdshader and the grass shaders so that grass sits exactly on the
// displaced ground and only grows where the ground material is grass.

uniform sampler2D heightmap : filter_linear, repeat_disable;
// R deposit, G water flow, B erosion, A concavity.
uniform sampler2D control_map : filter_linear_mipmap, repeat_disable;
// Bedrock outcrop mask from the terrain pipeline.
uniform sampler2D rock_map : filter_linear, repeat_disable;
// R soil bumps, G fractured stone, B micro roughness (linear heights).
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 terrain_origin;
uniform float terrain_res = 1025.0;
uniform float cell_size = 1.0;

// Close-range displacement around the player, faded out with distance.
uniform float detail_fade_start = 35.0;
uniform float detail_fade_end = 75.0;
uniform float soil_detail = 0.38;
uniform float rock_detail = 0.75;
uniform float snow_height = 215.0;
uniform float snow_fade = 30.0;
// Paved area (start site): x, z, radius, blend width. No close-range displacement
// inside, so the ground stays under the paving; grass skips it too.
uniform vec4 flat_zone = vec4(0.0, 0.0, -1.0, 1.0);

// Set every frame by Terrain.gd. Shadow passes use it too, so the displaced
// geometry is identical in every pass (unlike CAMERA_POSITION_WORLD).
global uniform vec3 player_position;

vec2 terrain_uv(vec2 xz) {
	return ((xz - terrain_origin) / cell_size + 0.5) / terrain_res;
}

float terrain_base_height(vec2 xz) {
	return textureLod(heightmap, terrain_uv(xz), 0.0).r;
}

float terrain_rock(vec2 xz) {
	return textureLod(rock_map, terrain_uv(xz), 0.0).r;
}

float detail_fade(vec2 xz) {
	float f = 1.0 - smoothstep(detail_fade_start, detail_fade_end, distance(xz, player_position.xz));
	if (flat_zone.z > 0.0) {
		f *= smoothstep(flat_zone.z, flat_zone.z + flat_zone.w, distance(xz, flat_zone.xy));
	}
	return f;
}

float detail_height(vec2 xz, float rock) {
	vec3 a = textureLod(detail_noise, xz * 0.09, 0.0).rgb;
	vec3 b = textureLod(detail_noise, xz * 0.31 + vec2(0.37, 0.71), 0.0).rgb;
	float soil = (a.r - 0.5) + (b.r - 0.5) * 0.45 + (b.b - 0.5) * 0.15;
	float stone = (a.g - 0.4) + (b.g - 0.4) * 0.5 + (b.b - 0.5) * 0.1;
	return mix(soil * soil_detail, stone * rock_detail, smoothstep(0.3, 0.7, rock));
}

float terrain_height(vec2 xz) {
	float h = terrain_base_height(xz);
	float f = detail_fade(xz);
	if (f > 0.0) {
		h += detail_height(xz, terrain_rock(xz)) * f;
	}
	return h;
}

// Normal of the 1 m heightmap only (cheap; used for placement decisions).
vec3 terrain_base_normal(vec2 xz) {
	float e = cell_size;
	vec2 g = vec2(terrain_base_height(xz + vec2(e, 0.0)) - terrain_base_height(xz - vec2(e, 0.0)),
			terrain_base_height(xz + vec2(0.0, e)) - terrain_base_height(xz - vec2(0.0, e))) / (2.0 * e);
	return normalize(vec3(-g.x, 1.0, -g.y));
}

// Normal from the heightmap (1 m scale) plus the faded close-range detail.
vec3 terrain_normal(vec2 xz) {
	float e = cell_size;
	vec2 g = vec2(terrain_base_height(xz + vec2(e, 0.0)) - terrain_base_height(xz - vec2(e, 0.0)),
			terrain_base_height(xz + vec2(0.0, e)) - terrain_base_height(xz - vec2(0.0, e))) / (2.0 * e);
	float f = detail_fade(xz);
	if (f > 0.0) {
		float r = terrain_rock(xz);
		float d = 0.25;
		g += vec2(detail_height(xz + vec2(d, 0.0), r) - detail_height(xz - vec2(d, 0.0), r),
				detail_height(xz + vec2(0.0, d), r) - detail_height(xz - vec2(0.0, d), r)) / (2.0 * d) * f;
	}
	return normalize(vec3(-g.x, 1.0, -g.y));
}

// Material weights shared by terrain texturing and grass placement.
// Rock is decided sharply: steep ground, or the steeper parts (risers) of outcrop zones.
// Flat ledges inside outcrops stay soft ground with gravel and moss.
void terrain_weights(float height, vec3 n, vec4 ctl, float rock, vec3 macro, vec3 macro2,
		out float grass_w, out float dirt_w, out float moss_w, out float rock_w, out float snow_w) {
	float slope = 1.0 - n.y;
	float slope_noise = (macro2.r - 0.5) * 0.06 + (macro.g - 0.5) * 0.05;
	float rock_geo = smoothstep(0.31, 0.35, slope + slope_noise + ctl.b * 0.04);
	float rock_zone = smoothstep(0.45, 0.6, rock) * smoothstep(0.09, 0.13, slope + slope_noise * 0.5);
	rock_w = max(rock_geo, rock_zone);
	snow_w = smoothstep(snow_height - snow_fade, snow_height + snow_fade, height + (macro.r - 0.5) * 50.0)
			* (1.0 - smoothstep(0.45, 0.7, slope)) * (1.0 - rock_w);
	float scree = smoothstep(0.12, 0.45, rock) * (1.0 - rock_w);
	dirt_w = smoothstep(0.45, 0.85, ctl.r + (macro2.g - 0.5) * 0.35) * 0.8
			+ smoothstep(0.68, 0.85, ctl.g) * 0.7
			+ smoothstep(0.2, 0.31, slope) * 0.45
			+ scree * 0.5;
	moss_w = smoothstep(0.55, 0.75, ctl.a) * smoothstep(0.4, 0.7, ctl.g) * 0.8
			+ smoothstep(0.62, 0.8, macro.b) * 0.3
			+ smoothstep(0.4, 0.75, rock) * (1.0 - rock_w) * 0.35;
	dirt_w = clamp(dirt_w, 0.0, 1.0) * (1.0 - rock_w) * (1.0 - snow_w);
	moss_w = clamp(moss_w, 0.0, 1.0) * (1.0 - rock_w) * (1.0 - snow_w) * (1.0 - dirt_w);
	grass_w = max(1.0 - rock_w - snow_w - dirt_w - moss_w, 0.0);
}
