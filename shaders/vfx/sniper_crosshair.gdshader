shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Warning crosshair shown in front of a player aiming the sniper beam (seen by everyone else):
// a spinning red reticle with ticks and brackets, a charge arc filling over the minimum aim
// time, and a hot pulse once it can fire.

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.15, 1.0);
uniform float energy = 3.5;
instance uniform float charge = 0.0;
instance uniform float spin = 0.0;
instance uniform float fade = 1.0;

float line(float d, float w, float aa) { return smoothstep(w + aa, w - aa, abs(d)); }

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float aa = fwidth(r) * 1.2;
	float ang = atan(c.y, c.x);
	float a_spin = ang + spin;
	float ready = step(0.999, charge);
	float pulse = ready * (0.6 + 0.4 * sin(TIME * 18.0));

	float v = 0.0;
	// Outer ring broken into four arcs (spinning), inner solid ring.
	float arcs = step(0.25, fract(a_spin / 1.5707963 + 0.125));
	v += line(r - 0.86, 0.018, aa) * arcs;
	v += line(r - 0.55, 0.012, aa);
	// Charge arc just outside, clockwise from the top.
	float t = fract(0.25 - ang / 6.2831853);
	v += line(r - 0.94, 0.028, aa) * step(t, charge) * (0.6 + 0.4 * ready);
	// Ticks around the outer ring (spinning the other way).
	float tick_a = fract((ang - spin * 0.6) / 6.2831853 * 24.0);
	v += step(0.72, r) * step(r, 0.8) * smoothstep(0.12, 0.04, abs(tick_a - 0.5) - 0.38) * 0.8;
	// Cross hairs with a gap in the middle, and a centre dot.
	float gap = step(0.16, r) * step(r, 0.78);
	v += (line(c.x, 0.012, aa) + line(c.y, 0.012, aa)) * gap;
	v += smoothstep(0.05, 0.03, r);
	// Corner brackets that pull in as the charge fills.
	float k = mix(0.5, 0.36, charge);
	vec2 q = abs(c) - vec2(k);
	float bracket = (line(q.x, 0.012, aa) * step(-0.12, q.y) * step(q.y, 0.0)
		+ line(q.y, 0.012, aa) * step(-0.12, q.x) * step(q.x, 0.0));
	v += bracket;
	// Soft red glow behind it all.
	float glow = exp(-r * r * 3.0) * 0.12 + exp(-pow((r - 0.86) / 0.08, 2.0)) * 0.25;

	vec3 col = color.rgb * (v + glow) + vec3(1.0, 0.7, 0.6) * v * pulse * 0.6;
	ALBEDO = col * energy;
	ALPHA = clamp((v + glow) * fade * step(r, 1.0), 0.0, 1.0);
}
