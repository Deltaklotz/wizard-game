shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Sniper beam, drawn as three nested cylinders (local Y = along the beam, -0.5..0.5, radius 1):
//   layer 0: white-hot core, layer 1: crimson glow with travelling pulses,
//   layer 2: two energy strands spiralling around the beam.
// `intensity` (0..1) is animated by SniperFx; `length_m` keeps patterns in metres.

uniform int layer = 0;
uniform vec4 color : source_color = vec4(1.0, 0.15, 0.2, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.55, 0.35, 1.0);
uniform float length_m = 100.0;
uniform float intensity = 1.0;
uniform float energy = 4.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float nv = abs(dot(NORMAL, VIEW));
	float along = (lp.y + 0.5) * length_m;               // metres from the caster
	// Soft start at the muzzle, so the cylinder end doesn't show.
	float ends = smoothstep(0.0, 0.6, along) * smoothstep(0.0, 0.4, length_m - along);
	vec3 col;
	float a;
	if (layer == 0) {
		a = pow(nv, 1.5);
		col = mix(accent.rgb, vec3(1.0), pow(nv, 4.0)) * 2.0;
	} else if (layer == 1) {
		float pulse = 0.65 + 0.35 * sin(along * 0.9 - TIME * 55.0);
		a = pow(nv, 2.5) * 0.7 * pulse;
		col = mix(color.rgb, accent.rgb, 0.25);
	} else {
		float ang = atan(lp.z, lp.x) / 6.2831853;
		float s1 = fract(ang + along * 0.35 - TIME * 7.0);
		float s2 = fract(ang + 0.5 + along * 0.35 - TIME * 7.0);
		float w = 0.06;
		float strand = smoothstep(w, 0.0, abs(s1 - 0.5)) + smoothstep(w, 0.0, abs(s2 - 0.5));
		// Strands flicker in segments along the beam.
		float seg = 0.55 + 0.45 * sin(along * 0.23 + TIME * 13.0);
		a = strand * seg * (0.35 + 0.65 * nv);
		col = mix(accent.rgb, color.rgb, 0.4);
	}
	ALBEDO = col * energy * intensity;
	ALPHA = clamp(a * ends * intensity, 0.0, 1.0);
}
