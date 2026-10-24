// Body of the terrain shader, shared by terrain.gdshader (full) and terrain_lite.gdshader
// (#define LITE: performance mode for weak GPUs – materials are only sampled where they
// show, one tiling scale, no rock/dirt/moss/snow normal maps and no close-range detail
// normals: ~12 texture reads per pixel instead of ~40).

// Terrain: flat grid chunks displaced on the GPU from the heightmap, plus close-range
// detail displacement around the player. Materials are chosen per pixel from the
// surface normal, height, the erosion control map and the bedrock outcrop map.

#include "res://shaders/include/triplanar.gdshaderinc"
#include "res://shaders/include/terrain_common.gdshaderinc"
#include "res://shaders/include/stylized_light.gdshaderinc"

uniform float skirt_depth = 4.0;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float grass_tiling = 0.6;
uniform float dirt_tiling = 0.4;
uniform float rock_tiling = 0.12;
uniform float snow_tiling = 0.15;
uniform float moss_tiling = 0.45;

varying vec3 v_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// UV.x marks the skirt ring that hides cracks between LOD levels.
	VERTEX.y = terrain_height(wp.xz) - UV.x * skirt_depth;
	// No vertex normal: the fragment shader computes the full-detail normal itself,
	// and skipping it keeps depth/shadow passes cheap.
	v_world = vec3(wp.x, VERTEX.y, wp.z);
}

// Height-aware blend: the material whose texture "sticks out" wins at transitions.
vec4 height_blend(vec4 w, vec4 h) {
	vec4 v = w + h * 0.35;
	float m = max(max(v.x, v.y), max(v.z, v.w)) - 0.1;
	vec4 b = max(v - m, vec4(0.0)) * step(0.001, w);
	return b / max(dot(b, vec4(1.0)), 1e-4);
}

void fragment() {
	vec2 huv = terrain_uv(v_world.xz);
#ifdef LITE
	vec3 n = terrain_base_normal(v_world.xz);
#else
	vec3 n = terrain_normal(v_world.xz);
#endif
	vec4 ctl = texture(control_map, huv);
	float rock_m = texture(rock_map, huv).r;
	vec3 macro = texture(macro_noise, v_world.xz * 0.0035).rgb;
	vec3 macro2 = texture(macro_noise, v_world.xz * 0.021).rgb;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float far = smoothstep(40.0, 250.0, dist);

	float grass_w;
	float dirt_w;
	float moss_w;
	float rock_w;
	float snow_w;
	terrain_weights(v_world.y, n, ctl, rock_m, macro, macro2, grass_w, dirt_w, moss_w, rock_w, snow_w);

	vec2 p = v_world.xz;
#ifdef LITE
	vec4 grass = texture(grass_albedo, p * grass_tiling);
	vec3 grass_n = unpack_normal(texture(grass_normal, p * grass_tiling));
#else
	// Planar samples for the flat materials, with a second, rotated scale to break tiling.
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float scale_mix = smoothstep(0.35, 0.65, macro2.b);
	vec4 g1 = texture(grass_albedo, p * grass_tiling);
	vec4 g2 = texture(grass_albedo, rot * p * grass_tiling * 0.43);
	vec4 grass = mix(g1, g2, scale_mix * 0.6 + far * 0.4);
	vec3 grass_n = mix(unpack_normal(texture(grass_normal, p * grass_tiling)),
			unpack_normal(texture(grass_normal, rot * p * grass_tiling * 0.43)), scale_mix * 0.6 + far * 0.4);
#endif
	// Lush vs dry meadows.
	grass.rgb *= mix(vec3(0.82, 0.92, 0.72), vec3(1.12, 1.02, 0.78), macro.r);
	grass.rgb *= 0.85 + 0.3 * macro2.g;
	float luma = dot(grass.rgb, vec3(0.3, 0.59, 0.11));
	grass.rgb = mix(vec3(luma), grass.rgb, 1.12);

#ifdef LITE
	// Only what shows: whole stretches of ground skip most of these reads.
	const vec3 FLAT_N = vec3(0.0, 0.0, 1.0);
	vec4 dirt = vec4(0.4, 0.33, 0.25, 0.5);
	vec3 dirt_n = FLAT_N;
	if (dirt_w > 0.003) {
		dirt = texture(dirt_albedo, p * dirt_tiling);
	}
	vec4 moss = vec4(0.25, 0.32, 0.12, 0.5);
	vec3 moss_n = FLAT_N;
	if (moss_w > 0.003) {
		moss = texture(moss_albedo, p * moss_tiling);
	}
	vec4 snow = vec4(0.9, 0.92, 0.95, 0.5);
	vec3 snow_n = FLAT_N;
	if (snow_w > 0.003) {
		snow = texture(snow_albedo, p * snow_tiling);
	}
	vec4 rock = vec4(0.45, 0.43, 0.4, 0.5);
	vec3 rock_wn = n;
	if (rock_w > 0.003) {
		vec3 bw = triplanar_weights(n, 6.0);
		rock = triplanar_sample(rock_albedo, v_world * rock_tiling * 1.6, bw);
	}
	rock.rgb *= mix(vec3(0.95, 0.92, 0.88), vec3(1.05, 1.0, 0.95), macro.g);
	rock.rgb *= mix(0.78, 1.05, macro2.r);
#else
	vec4 dirt = texture(dirt_albedo, p * dirt_tiling);
	vec3 dirt_n = unpack_normal(texture(dirt_normal, p * dirt_tiling));
	vec4 moss = texture(moss_albedo, p * moss_tiling);
	vec3 moss_n = unpack_normal(texture(moss_normal, p * moss_tiling));
	vec4 snow = texture(snow_albedo, p * snow_tiling);
	vec3 snow_n = unpack_normal(texture(snow_normal, p * snow_tiling));

	// Rock at two scales so outcrops don't read as one big cracked plate.
	vec3 bw = triplanar_weights(n, 6.0);
	vec3 rp = v_world * rock_tiling;
	vec4 rock = mix(triplanar_sample(rock_albedo, rp, bw), triplanar_sample(rock_albedo, rp * 3.1 + 7.0, bw), 0.4);
	vec3 rock_wn = normalize(mix(triplanar_normal(rock_normal, rp, n, bw), triplanar_normal(rock_normal, rp * 3.1 + 7.0, n, bw), 0.5));
	rock.rgb *= mix(vec3(0.95, 0.92, 0.88), vec3(1.05, 1.0, 0.95), macro.g);
	// Crevices of the displaced stone get darker.
	float stone_detail = texture(detail_noise, p * 0.09).g;
	rock.rgb *= mix(0.7, 1.08, smoothstep(0.15, 0.7, stone_detail));
#endif

	// Blend in two groups: flat materials first, then rock/snow via heights.
	vec4 wts = height_blend(vec4(grass_w, dirt_w, moss_w, rock_w + snow_w), vec4(grass.a, dirt.a, moss.a, rock.a));
	float rock_part = wts.w * (rock_w / max(rock_w + snow_w, 1e-4));
	float snow_part = wts.w - rock_part;

	// Gravel around outcrops is greyer than regular soil.
	dirt.rgb = mix(dirt.rgb, dirt.rgb * vec3(0.95, 0.97, 1.02) + 0.03, smoothstep(0.1, 0.4, rock_m));

	vec3 albedo = grass.rgb * wts.x + dirt.rgb * wts.y + moss.rgb * wts.z + rock.rgb * rock_part + snow.rgb * snow_part;
	vec3 flat_tn = grass_n * wts.x + dirt_n * wts.y + moss_n * wts.z + snow_n * snow_part;
	vec3 flat_wn = planar_normal_y(flat_tn, n);
	vec3 wn = normalize(flat_wn * (1.0 - rock_part) + rock_wn * rock_part);

	// Water channels are darker and a bit glossier.
	float wet = smoothstep(0.6, 0.85, ctl.g) * (1.0 - rock_w) * (1.0 - snow_w);
	albedo *= 1.0 - wet * 0.3;
	float cavity = ctl.a;
	albedo *= mix(1.08, 0.82, smoothstep(0.35, 0.8, cavity));

	ALBEDO = albedo;
	// Soil, grass and moss are fully matte (sky reflections at grazing angles made them look
	// like plastic); rock and snow keep a little sheen, wet mud a faint one.
	ROUGHNESS = clamp(wts.x + wts.y + wts.z + 0.88 * rock_part + 0.6 * snow_part - wet * 0.18, 0.4, 1.0);
	SPECULAR = 0.08 + 0.22 * (rock_part + snow_part) + wet * 0.12;
	AO = mix(1.0, 0.65, smoothstep(0.5, 0.9, cavity));
	AO_LIGHT_AFFECT = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_world) : 1.0);
	// No rim on the ground: you see it at grazing angles almost everywhere, so a rim
	// turns into a sheen over the whole landscape.
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.3, 0.0, vec3(0.0), 0.0);
	SPECULAR_LIGHT += stylized_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, ROUGHNESS, 0.015);
}
