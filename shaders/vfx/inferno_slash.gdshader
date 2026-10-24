shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Pale rose crescent slashes whirling around the Infernal Torrent (InfernoBeam, a MultiMesh of
// one arc). The arc is a centre line around the unit circle (a stretch of helix); its NORMAL
// holds the line's tangent and UV.y the side (0 / 1). The vertex shader spreads each side
// across the line as seen from the camera, so the crescent shows full width from any angle:
// down the beam they read as C shapes, from the side as hooked swooshes. The width profile is
// a crescent - thick near the head, a long sharp tail - with hooked barbs on the outer edge.
// INSTANCE_CUSTOM: x = age 0..1, y = seed, z = strength.

#include "res://shaders/vfx/inferno_common.gdshaderinc"

uniform float width = 0.2;
uniform float opacity = 0.55;
uniform float energy = 1.0;
uniform vec2 near_fade = vec2(1.2, 5.0);

varying float v_age;
varying float v_seed;
varying float v_strength;
varying float v_side;
varying vec3 v_world;

float profile(float x, float side, float seed) {
	// Crescent: grows quickly from a sharp head, long taper to the tail.
	float body = pow(clamp(x / 0.18, 0.0, 1.0), 0.7) * pow(1.0 - x, 1.4);
	// Hooked barbs on the outer side.
	float barbs = 0.0;
	if (side > 0.0) {
		for (int i = 0; i < 3; i++) {
			float at = 0.3 + 0.2 * float(i) + 0.08 * (inf_hash2(vec2(seed * 31.0, float(i))) - 0.5);
			float k = (x - at) / 0.06;
			// Sawtooth-like barb: rises slowly, ends abruptly (a hook).
			barbs += (k > -1.0 && k < 0.0) ? (1.0 + k) * (1.0 + k) * 0.9 * (1.0 - x) : 0.0;
		}
	}
	return body * (side > 0.0 ? 1.0 : 0.55) + barbs;
}

void vertex() {
	v_age = INSTANCE_CUSTOM.x;
	v_seed = INSTANCE_CUSTOM.y;
	v_strength = INSTANCE_CUSTOM.z;
	float side = UV.y * 2.0 - 1.0;
	v_side = side;
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 view = normalize(cam - VERTEX);
	vec3 across = cross(normalize(NORMAL), view);
	if (dot(across, VERTEX) < 0.0) {
		across = -across;  // the barbed side faces away from the beam
	}
	across = normalize(across);
	// Grows in, then thins away.
	float life = smoothstep(0.0, 0.12, v_age) * (1.0 - smoothstep(0.55, 1.0, v_age) * 0.7);
	float w = profile(UV.x, side, v_seed) * width * life;
	VERTEX += across * side * w;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = UV.x;
	// The tail frays as the slash ages.
	float fray = inf_noise2(vec2(x * 18.0 + v_seed * 40.0, v_side * 2.0));
	float tail = 1.0 - smoothstep(0.55 - 0.45 * v_age, 0.95 - 0.4 * v_age, x + (fray - 0.5) * 0.25);
	float fade = (1.0 - smoothstep(0.6, 1.0, v_age)) * smoothstep(0.0, 0.08, v_age) * v_strength;
	fade *= smoothstep(near_fade.x, near_fade.y, distance(v_world, CAMERA_POSITION_WORLD));
	// A brighter, sharper inner edge towards the beam.
	float rim = smoothstep(-0.55, -0.95, v_side);
	vec3 col = mix(INF_ROSE, vec3(1.0, 0.9, 0.93), rim * 0.6) * energy;
	ALBEDO = col;
	ALPHA = clamp(step(0.5, tail) * opacity * (1.0 + rim * 0.4) * fade, 0.0, 1.0);
}
