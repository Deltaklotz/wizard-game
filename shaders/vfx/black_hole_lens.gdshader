shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Simple black hole, part 1 (BlackHole with "Fancy black hole" off): a camera-facing quad
// through the hole's centre (QuadMesh 2×2, scaled here to `lens_radius` horizon radii). Instead
// of tracing rays it bends the background with the thin-lens equation of a point mass,
//     source = b − E² / b      (b = distance from the centre in the quad's plane)
// with one screen read per pixel: an Einstein ring at E, the far side mirrored inside it, the
// bending eased out towards the quad's edge. On top: the shadow (black inside 2.6 rs), the
// photon ring, and the disk's faint secondary image – a thin band hugging the underside of the
// shadow. The disk itself, including its far side lensed up over the shadow, is a separate mesh
// (black_hole_disk.gdshader) drawn over this.

#include "res://shaders/vfx/bh_lite_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Horizon radius (m) and the quad's half size (in horizon radii).
uniform float rs = 2.0;
uniform float lens_radius = 11.0;
uniform float einstein = 4.6;
uniform float shadow_radius = 2.6;
uniform float ring_energy = 2.0;
// Screen-plane direction (quad x/y) of the disk's "up" side: the halo is thick on that side.
uniform vec2 disk_up = vec2(0.0, 1.0);
// 0..1: formation/collapse – fades the whole effect against the plain scene.
uniform float presence = 1.0;

varying vec2 v_q;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.xy *= lens_radius * rs;
	v_q = VERTEX.xy / rs;
}

vec3 lensed(vec2 q, vec2 screen_uv, vec3 center, mat4 inv_view, mat4 view, mat4 proj) {
	float b = length(q);
	vec2 dir = q / max(b, 1e-4);
	float w = 1.0 - smoothstep(lens_radius * 0.4, lens_radius, b);
	float src = b - einstein * einstein / max(b, shadow_radius * 0.9) * w;
	vec3 world = center + (inv_view[0].xyz * dir.x + inv_view[1].xyz * dir.y) * src * rs;
	vec4 clip = proj * view * vec4(world, 1.0);
	vec2 uv = clip.xy / max(clip.w, 1e-4) * 0.5 + 0.5;
	return textureLod(screen_tex, clamp(uv, vec2(0.002), vec2(0.998)), 0.0).rgb;
}

void fragment() {
	float b = length(v_q);
	if (b > lens_radius) {
		discard;
	}
	vec2 dir = v_q / max(b, 1e-4);
	vec3 bg = lensed(v_q, SCREEN_UV, NODE_POSITION_WORLD, INV_VIEW_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX);

	// Secondary image of the far disk: a thin band under the shadow, fading out towards the
	// sides where the disk itself passes in front.
	float up = dot(dir, normalize(disk_up));
	float thick = 0.05 + 0.55 * pow(max(-up, 0.0), 1.5);
	float u = (b - shadow_radius * 1.03) / thick;
	float band = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.45, 1.0, u));
	vec3 halo = vec3(0.0);
	float halo_a = 0.0;
	if (band > 0.0) {
		// Along the arc the angle runs round the shadow; across it the disk's radius.
		float ang = atan(dir.y, dir.x) * (up > 0.0 ? 1.0 : -1.0);
		vec2 m = bhl_flow(ang, 2.6 + u * 9.0, 2.6, 5.0);
		vec3 col = bhl_color(u * 0.6);
		band *= smoothstep(0.1, 0.5, -up);
		halo = col * disk_energy * (m.y * 2.0 + m.x * 0.3) * band;
		halo_a = clamp(m.x * 0.7 + m.y * 0.3, 0.0, 1.0) * band;
	}
	float shadow = 1.0 - smoothstep(shadow_radius * 0.96, shadow_radius * 1.02, b);
	float ring = exp(-pow((b - shadow_radius * 1.04) / 0.07, 2.0));
	vec3 col = bg * (1.0 - shadow) * (1.0 - halo_a * disk_strength) + (halo + disk_hot * ring_energy * ring) * disk_strength;
	vec3 plain = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	ALBEDO = mix(plain, col, presence);
	ALPHA = 1.0;
}
