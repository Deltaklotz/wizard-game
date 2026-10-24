// Shared rock material: triplanar stone with moss on upward faces.
// Define ORBIT before including to get the levitating-rock animation, which reads
// per-instance orbit parameters from INSTANCE_CUSTOM:
//   x = orbit radius, y = phase (radians), z = angular speed, w = height offset.

#include "res://shaders/include/triplanar.gdshaderinc"
#include "res://shaders/include/stylized_light.gdshaderinc"

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tiling = 0.6;
uniform float moss_amount = 0.6;
uniform vec3 tint : source_color = vec3(1.0);

#ifdef ORBIT
// Tilt of the orbit plane and a glow for the magic veins, set per island.
instance uniform vec3 orbit_up = vec3(0.0, 1.0, 0.0);
instance uniform float bob_amount = 0.6;
// Shared world clock (Net.world_time): the orbits are identical on every client and match the
// rocks' colliders (FloatingIsland.orbiter_transform).
global uniform float world_time;
uniform vec3 glow_color : source_color = vec3(0.55, 0.4, 1.0);
uniform float glow_strength = 1.5;
#endif

varying vec3 v_tex_pos;
varying vec3 v_tex_normal;
varying float v_rand;
varying float v_ao;
varying vec3 v_wpos;
#ifdef ORBIT
varying vec3 v_spin_axis;
varying float v_spin;
#endif

vec3 rotate_axis(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	v_ao = COLOR.r;
#ifdef ORBIT
	// world_vertex_coords: VERTEX/NORMAL are already in world space. The instance
	// origin is the island (orbit) center; the instance basis holds scale/rotation.
	vec3 center = MODEL_MATRIX[3].xyz;
	vec4 c = INSTANCE_CUSTOM;
	vec3 local = VERTEX - center;
	v_tex_pos = local;
	v_tex_normal = NORMAL;
	v_rand = fract(c.y * 0.1591 + c.x * 0.37);
	vec3 spin_axis = normalize(vec3(sin(c.y * 3.1), 1.0, cos(c.y * 1.7)));
	float spin = world_time * (0.15 + v_rand * 0.4) + c.y;
	v_spin_axis = spin_axis;
	v_spin = spin;
	local = rotate_axis(local, spin_axis, spin);
	vec3 n = rotate_axis(NORMAL, spin_axis, spin);
	float ang = c.y + world_time * c.z;
	vec3 orbit = vec3(cos(ang) * c.x, c.w + sin(world_time * 0.6 + c.y * 2.3) * bob_amount, sin(ang) * c.x);
	// Tilt the orbit plane so its normal is orbit_up.
	vec3 up = normalize(orbit_up);
	vec3 axis = cross(vec3(0.0, 1.0, 0.0), up);
	float s = length(axis);
	if (s > 1e-4) {
		orbit = rotate_axis(orbit, axis / s, asin(clamp(s, 0.0, 1.0)));
	}
	VERTEX = center + orbit + local;
	NORMAL = n;
	v_wpos = VERTEX;
#else
	v_tex_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tex_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_rand = hash13(floor(MODEL_MATRIX[3].xyz * 3.0));
	v_wpos = v_tex_pos;
#endif
}

void fragment() {
	vec3 n = normalize(v_tex_normal);
	vec3 p = v_tex_pos * tiling + vec3(v_rand * 17.0);
	vec3 bw = triplanar_weights(n, 4.0);
	vec4 rock = triplanar_sample(rock_albedo, p, bw);
#ifdef LITE
	// Performance mode: albedo only, and moss only on faces that can carry it.
	vec3 rn = n;
	vec3 mn = n;
	vec4 moss = vec4(0.25, 0.32, 0.12, 1.0);
	if (n.y > -0.2) {
		moss = triplanar_sample(moss_albedo, p * 1.5, bw);
	}
#else
	vec3 rn = triplanar_normal(rock_normal, p, n, bw);
	vec4 moss = triplanar_sample(moss_albedo, p * 1.5, bw);
	vec3 mn = triplanar_normal(moss_normal, p * 1.5, n, bw);
#endif
	float moss_w = smoothstep(0.35, 0.8, n.y + (rock.a - 0.5) * 0.6 + (v_rand - 0.5) * 0.4) * moss_amount;
	vec3 albedo = mix(rock.rgb * tint * mix(0.85, 1.1, v_rand), moss.rgb, moss_w);
	vec3 wn = normalize(mix(rn, mn, moss_w));
	albedo *= v_ao;
#ifdef ORBIT
	// Faint glowing veins in the cracks.
	float vein = smoothstep(0.32, 0.12, rock.a) * (1.0 - moss_w);
	EMISSION = glow_color * vein * glow_strength * (0.6 + 0.4 * sin(TIME * 1.7 + v_rand * 20.0));
	// The detail normal was computed in the rock's rest pose; apply the spin.
	wn = rotate_axis(wn, v_spin_axis, v_spin);
#endif
	ALBEDO = albedo;
	ROUGHNESS = mix(0.85, 0.95, moss_w);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

void light() {
	float atten = ATTENUATION * (LIGHT_IS_DIRECTIONAL ? cloud_shadow(v_wpos) : 1.0);
	DIFFUSE_LIGHT += stylized_diffuse(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, 0.25, 0.0, vec3(0.0), 0.3);
	SPECULAR_LIGHT += stylized_specular(NORMAL, LIGHT, VIEW, LIGHT_COLOR, atten, ROUGHNESS, 0.08);
}
