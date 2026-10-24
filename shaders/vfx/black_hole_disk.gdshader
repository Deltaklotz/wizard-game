shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_premul_alpha;
// Simple black hole, part 2: the accretion disk as a flat plane (PlaneMesh in the node's XZ,
// node scaled to the horizon radius, so local units are horizon radii; oriented per viewer by
// BlackHole like the fancy one). Dark absorbing gas lit by bright filaments, premultiplied
// alpha. The far half is lensed in the vertex shader: each vertex behind the centre moves to
// its primary image, θ = (β + √(β² + 4E²)) / 2 in the plane facing the viewer, so the far
// side of the disk bends up over the shadow (and down under it) in one piece with the rest –
// the Interstellar arc. (Needs the subdivided PlaneMesh BlackHole builds.)

#include "res://shaders/vfx/bh_lite_common.gdshaderinc"

uniform float disk_inner = 2.6;
uniform float disk_outer = 22.0;
// Einstein radius for the disk's light (horizon radii; smaller than the background's, so the
// arc hugs the shadow) and where the bending has faded out.
uniform float disk_einstein = 3.3;
uniform float lens_radius = 11.0;
// Pulls the lensed arc in by arc_pull / θ (horizon radii), so the disk's inner edge seen behind
// the hole (θ ≈ 3.6 from the weak-field formula) lands on the photon ring at ~2.7.
uniform float arc_pull = 3.3;
// Fades out where it passes this close to the viewer (m), like the fancy disk.
uniform float near_fade_start = 8.0;
uniform float near_fade_end = 32.0;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 c = NODE_POSITION_WORLD;
	float rs_m = length(MODEL_MATRIX[0].xyz);
	vec3 to_c = c - CAMERA_POSITION_WORLD;
	float dist = max(length(to_c), 0.01);
	vec3 v = to_c / dist;
	vec3 d = w - c;
	float depth = dot(d, v);
	if (depth > 0.0) {
		// Behind the hole: move to the primary image. Angles are measured as seen from the
		// camera (in horizon radii at the centre's distance), so a vertex further back is
		// pushed proportionally further out.
		vec3 q = d - v * depth;
		float persp = (dist + depth) / dist;
		float beta = length(q) / (rs_m * persp);
		float theta = 0.5 * (beta + sqrt(beta * beta + 4.0 * disk_einstein * disk_einstein));
		// The weak-field formula leaves a gap of lensed sky between the shadow and the arc;
		// near the hole light bends harder, so pull the arc's inner edge in to the photon ring
		// (the shift dies off as 1/θ, keeping the mapping monotonic).
		theta -= arc_pull / theta;
		// Bending fades out with distance (as on the lens quad) and eases in just behind the
		// centre, so the near and far halves stay joined at the sides.
		float k = (1.0 - smoothstep(lens_radius * 0.4, lens_radius, beta)) * smoothstep(0.0, 1.5 * rs_m, depth);
		float b = mix(beta, theta, k);
		vec3 dir = length(q) > 1e-4 ? normalize(q) : vec3(0.0);
		w = c + v * depth + dir * b * rs_m * persp;
	}
	v_world = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	float r = length(v_local.xz);
	if (r < disk_inner * 0.85 || r > disk_outer) {
		discard;
	}
	vec3 cam = CAMERA_POSITION_WORLD;

	float u = clamp((r - disk_inner) / (disk_outer - disk_inner), 0.0, 1.0);
	float ang = atan(v_local.z, v_local.x);
	vec2 m = bhl_flow(ang, r, disk_inner, 0.0);
	float extent = smoothstep(0.0, 0.04, u + 0.02) * (1.0 - smoothstep(0.4, 1.0, u))
		* smoothstep(disk_inner * 0.85, disk_inner * 1.02, r);
	float heat = 0.5 + 1.2 * (1.0 - u) * (1.0 - u);
	// One layer stands in for the fancy disk's five, so it is a little brighter and denser.
	vec3 light = bhl_color(u) * disk_energy * heat * (m.y * 2.8 + m.x * 0.35) * extent;
	float opacity = clamp(m.x * 0.9 + m.y * 0.35, 0.0, 1.0) * extent;
	float k = disk_strength * smoothstep(near_fade_start, near_fade_end, distance(v_world, cam));
	ALBEDO = light * k;
	ALPHA = opacity * k;
}
