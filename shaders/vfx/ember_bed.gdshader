shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Burning ground under the fire pool (FirePatch), on a mesh draped over the terrain: charcoal-
// black with a web of glowing cracks (Voronoi borders) and hot spots that flicker and drift,
// a ragged burning edge. strength (0..1) dims it as the fire dies. UV = disc coords (0..1).

uniform float strength = 1.0;
uniform float energy = 3.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.3));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// (F2 - F1, cell random) of a Voronoi pattern.
vec2 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash2(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash(i + g);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), id);
}

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = v_world.xz;
	float r = length(UV * 2.0 - 1.0);
	float edge_n = noise(w * 1.3) * 0.35 + noise(w * 4.0) * 0.15;
	float edge = 1.0 - smoothstep(0.55, 1.0, r + edge_n - 0.15);
	vec2 v = voronoi(w * 1.6);
	vec2 v2 = voronoi(w * 4.5 + 3.1);
	float t = TIME;
	float flick = 0.6 + 0.4 * noise(w * 2.0 + vec2(t * 1.3, -t * 0.9));
	float cracks = (1.0 - smoothstep(0.0, 0.09, v.x)) + 0.5 * (1.0 - smoothstep(0.0, 0.05, v2.x));
	float spots = smoothstep(0.55, 0.9, noise(w * 1.1 + vec2(0.0, t * 0.25)) * (0.7 + 0.6 * v.y));
	float heat = clamp((cracks * 0.8 + spots) * flick, 0.0, 1.5) * strength * (0.6 + 0.4 * (1.0 - r));
	vec3 charcoal = vec3(0.03, 0.025, 0.022) * (0.7 + 0.6 * noise(w * 8.0));
	vec3 glow = mix(vec3(0.6, 0.06, 0.01), vec3(1.0, 0.45, 0.05), clamp(heat, 0.0, 1.0));
	glow = mix(glow, vec3(1.0, 0.85, 0.45), smoothstep(1.0, 1.4, heat));
	ALBEDO = charcoal + glow * heat * energy;
	ALPHA = edge * clamp(0.75 + heat, 0.0, 1.0) * clamp(strength * 3.0, 0.0, 1.0);
}
