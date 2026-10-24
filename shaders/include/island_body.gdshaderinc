// Body of island.gdshader / island_lite.gdshader (#define LITE: performance mode).

// Floating island body. Object-space triplanar mapping (islands bob, textures must not swim).
// Vertex COLOR: r = top surface, g = depth fraction towards the underside tip.

#include "res://shaders/include/triplanar.gdshaderinc"
#include "res://shaders/include/stylized_light.gdshaderinc"

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float grass_tiling = 0.6;
uniform float rock_tiling = 0.11;
uniform vec3 glow_color : source_color = vec3(0.5, 0.35, 1.0);
uniform float glow_strength = 2.0;
// Per-island variation.
instance uniform vec3 rock_tint = vec3(1.0);
instance uniform float strata_seed = 0.0;

varying vec3 v_obj;
varying vec3 v_obj_n;
varying vec4 v_col;
varying vec3 v_wpos;

void vertex() {
	v_obj = VERTEX;
	v_obj_n = NORMAL;
	v_col = COLOR;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(v_obj_n);
	vec3 macro = texture(macro_noise, v_obj.xz * 0.01 + strata_seed).rgb;
	vec3 bw = triplanar_weights(n, 5.0);
	vec3 rp = v_obj * rock_tiling + vec3(strata_seed * 13.0);

	// Two rock scales so both huge and tiny islands read as stone, not as one cracked plate.
#ifdef LITE
	// Performance mode: one rock scale, albedo only (no normal maps anywhere below).
	vec4 rock = triplanar_sample(rock_albedo, rp * 1.5, bw);
	vec3 rock_n = n;
#else
	vec4 rock = mix(triplanar_sample(rock_albedo, rp, bw), triplanar_sample(rock_albedo, rp * 2.7 + 5.0, bw), 0.45);
	vec3 rock_n = normalize(mix(triplanar_normal(rock_normal, rp, n, bw), triplanar_normal(rock_normal, rp * 2.7 + 5.0, n, bw), 0.5));
#endif
	// Sedimentary strata in the cliffs and underside.
	float strata = sin(v_obj.y * 0.9 + macro.r * 4.0 + strata_seed * 7.0) * 0.5 + 0.5;
	float strata2 = sin(v_obj.y * 2.7 + macro.g * 3.0) * 0.5 + 0.5;
	rock.rgb *= rock_tint * mix(vec3(0.82, 0.78, 0.74), vec3(1.08, 1.02, 0.95), strata) * (0.9 + 0.15 * strata2);
	// Underside gets darker and slightly cooler towards the tip.
	rock.rgb *= mix(1.0, 0.55, smoothstep(0.1, 1.0, v_col.g));
	rock.rgb = mix(rock.rgb, rock.rgb * vec3(0.85, 0.88, 1.0), v_col.g);

#ifdef LITE
	vec4 moss = vec4(0.25, 0.32, 0.12, 1.0);
	if (n.y > 0.0) {
		moss = triplanar_sample(moss_albedo, rp * 3.0, bw);
	}
	vec3 moss_n = n;
#else
	vec4 moss = triplanar_sample(moss_albedo, rp * 3.0, bw);
	vec3 moss_n = triplanar_normal(moss_normal, rp * 3.0, n, bw);
#endif
	float moss_w = smoothstep(0.25, 0.7, n.y + (macro.b - 0.5) * 0.5 + (rock.a - 0.5) * 0.4) * (1.0 - v_col.g) * 0.85;

	vec2 gp = v_obj.xz * grass_tiling;
	vec4 grass = texture(grass_albedo, gp);
	grass.rgb *= mix(vec3(0.85, 0.95, 0.75), vec3(1.1, 1.02, 0.8), macro.r);
	vec4 dirt = texture(dirt_albedo, gp * 0.8);
#ifdef LITE
	vec3 grass_tn = vec3(0.0, 0.0, 1.0);
	vec3 dirt_tn = vec3(0.0, 0.0, 1.0);
#else
	vec3 grass_tn = unpack_normal(texture(grass_normal, gp));
	vec3 dirt_tn = unpack_normal(texture(dirt_normal, gp * 0.8));
#endif

	float top = smoothstep(0.3, 0.9, v_col.r);
	float flat_w = smoothstep(0.62, 0.82, n.y + (grass.a - 0.5) * 0.3 + (macro.g - 0.5) * 0.15);
	float grass_w = top * flat_w;
	float dirt_w = top * (1.0 - flat_w) * smoothstep(0.35, 0.6, n.y);

	vec3 rock_mix_n = normalize(mix(rock_n, moss_n, moss_w));
	vec3 albedo = mix(rock.rgb, moss.rgb, moss_w);
	vec3 wn = rock_mix_n;
	albedo = mix(albedo, dirt.rgb, dirt_w);
	wn = normalize(mix(wn, planar_normal_y(dirt_tn, n), dirt_w));
	albedo = mix(albedo, grass.rgb, grass_w);
	wn = normalize(mix(wn, planar_normal_y(grass_tn, n), grass_w));

	// Magic seeping out of the cracks near the bottom.
	float vein = smoothstep(0.34, 0.12, rock.a) * smoothstep(0.55, 1.0, v_col.g);
	EMISSION = glow_color * vein * glow_strength * (0.7 + 0.3 * sin(TIME * 1.3 + v_obj.y * 0.3));

	ALBEDO = albedo;
	ROUGHNESS = mix(0.88, 0.94, grass_w);
	AO = mix(1.0, 0.7, v_col.g);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(wn, 0.0))).xyz);
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.3, 0.0, vec3(0.0), 0.3);
	SPECULAR_LIGHT += stylized_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, ROUGHNESS, 0.06);
}
