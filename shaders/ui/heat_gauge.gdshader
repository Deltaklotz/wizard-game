shader_type canvas_item;
// Heat gauge of the arcane minigun (Hud), drawn around the crosshair on a square rect:
// a segmented arc on the right fills from the bottom with heat, shading from blue through
// purple to hot pink and white; a thin arc on the left shows the barrel spin. Overheated:
// the arc flashes pink-red and drains with the remaining vent time.

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float spin : hint_range(0.0, 1.0) = 0.0;
uniform float overheated : hint_range(0.0, 1.0) = 0.0;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform vec3 cold : source_color = vec3(0.32, 0.6, 1.0);
uniform vec3 warm : source_color = vec3(0.62, 0.3, 1.0);
uniform vec3 hot : source_color = vec3(1.0, 0.42, 0.78);

const float HALF_ARC = 0.85;
const float SEGMENTS = 20.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	vec4 outc = vec4(0.0);

	// Right arc: angle 0 = right, +y = down; t = 0 at the bottom, 1 at the top.
	float a = atan(p.y, p.x);
	float t = (HALF_ARC - a) / (2.0 * HALF_ARC);
	float band = smoothstep(0.76 - aa, 0.76 + aa, r) * (1.0 - smoothstep(0.94 - aa, 0.94 + aa, r));
	float in_arc = step(0.0, t) * step(t, 1.0) * step(0.0, p.x);
	float seg = fract(t * SEGMENTS);
	float gap = smoothstep(0.0, 0.08, seg) * (1.0 - smoothstep(0.86, 0.94, seg));
	float cell = (floor(t * SEGMENTS) + 0.5) / SEGMENTS;
	float filled = step(cell, heat);
	vec3 c = mix(cold, warm, smoothstep(0.0, 0.5, cell));
	c = mix(c, hot, smoothstep(0.5, 0.85, cell));
	c = mix(c, vec3(1.0, 0.95, 1.0), smoothstep(0.9, 1.0, cell));
	float flash = 0.6 + 0.4 * sin(TIME * 18.0);
	if (overheated > 0.5) {
		c = mix(hot, vec3(1.0, 0.25, 0.35), 0.5) * (0.8 + 0.4 * flash);
	}
	float lit = band * in_arc * gap;
	// Dark backing behind the arc so it reads on bright ground and sky.
	float back = smoothstep(0.71 - aa, 0.71 + aa, r) * (1.0 - smoothstep(0.99 - aa, 0.99 + aa, r)) * in_arc;
	outc = vec4(0.03, 0.01, 0.06, 0.45 * back);
	// Empty segments faintly, filled ones bright.
	outc = mix(outc, vec4(c * (filled > 0.5 ? 1.6 : 0.5), filled > 0.5 ? 1.0 : 0.5), lit);
	// Thin frame lines around the arc.
	float frame = (smoothstep(0.012 + aa, 0.012 - aa, abs(r - 0.75)) + smoothstep(0.012 + aa, 0.012 - aa, abs(r - 0.95)))
		* in_arc;
	outc = mix(outc, vec4(c * 0.8, 0.55), frame * (1.0 - lit));

	// Left arc: barrel spin.
	float al = atan(p.y, -p.x);
	float tl = (HALF_ARC - al) / (2.0 * HALF_ARC);
	float left = step(0.0, tl) * step(tl, 1.0) * step(p.x, 0.0)
		* smoothstep(0.022 + aa, 0.022 - aa, abs(r - 0.84));
	float spun = step(tl, spin);
	outc = mix(outc, vec4(mix(cold, warm, tl) * (spun > 0.5 ? 1.6 : 0.5), spun > 0.5 ? 0.95 : 0.35), left);

	outc.a *= presence;
	COLOR = outc;
}
