shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Expanding arcane ring on a quad (dash departure / arrival).
//   runes = true: a ground circle with an inner band of rune ticks and a slowly turning star.
//   runes = false: a thin shockwave ring (placed upright, facing the dash direction).

uniform vec4 color : source_color = vec4(0.55, 0.7, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.85, 0.55, 1.0, 1.0);
uniform bool runes = true;
uniform float energy = 2.5;
instance uniform float progress = 0.0;
instance uniform float spin = 0.0;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float ang = atan(c.y, c.x) + spin;
	float p = clamp(progress, 0.0, 1.0);
	float grow = 1.0 - pow(1.0 - p, 3.0);
	float fade = pow(1.0 - p, 1.6);
	float aa = fwidth(r) * 1.5;
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (runes) {
		float R = mix(0.55, 0.92, grow);
		// Outer double ring.
		float ring = smoothstep(0.018 + aa, 0.018 - aa, abs(r - R)) + 0.6 * smoothstep(0.008 + aa, 0.008 - aa, abs(r - R * 0.93));
		// Rune band: short strokes of varying length between two thin rings.
		float seg = ang / 6.2831853 * 28.0;
		float id = floor(seg);
		float f = fract(seg);
		float band_in = R * 0.74;
		float band_out = R * 0.86;
		float len = mix(0.3, 1.0, hash(id + 3.0));
		float inside = step(band_in, r) * step(r, mix(band_in, band_out, len));
		float stroke = inside * smoothstep(0.42, 0.3, abs(f - 0.5)) * step(0.25, hash(id));
		float bands = smoothstep(0.006 + aa, 0.006 - aa, abs(r - band_in)) + smoothstep(0.006 + aa, 0.006 - aa, abs(r - band_out));
		// Six-pointed star inscribed in the inner circle.
		float star = 0.0;
		float rs = R * 0.7;
		for (int k = 0; k < 6; k++) {
			float t = float(k) * 1.0471976 - spin * 2.0;
			vec2 a0 = vec2(cos(t), sin(t)) * rs;
			vec2 a1 = vec2(cos(t + 2.0943951), sin(t + 2.0943951)) * rs;
			vec2 pa = c - a0;
			vec2 ba = a1 - a0;
			float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
			star = max(star, smoothstep(0.009 + aa, 0.0, length(pa - ba * h)));
		}
		float glow = exp(-pow((r - R) / 0.08, 2.0)) * 0.35;
		float inner = smoothstep(R, 0.0, r) * 0.08;
		col = color.rgb * (ring + glow + inner) + accent.rgb * (stroke * 0.9 + bands * 0.6 + star * 0.55);
		a = fade * step(r, 1.0);
	} else {
		float R = mix(0.12, 0.95, grow);
		float w = mix(0.1, 0.025, p);
		float ring = exp(-pow((r - R) / w, 2.0));
		// Broken into flickering arcs.
		float arcs = 0.55 + 0.45 * sin(ang * 7.0 + p * 9.0);
		col = mix(color.rgb, accent.rgb, 0.5 + 0.5 * sin(ang * 3.0)) * ring * arcs + color.rgb * exp(-pow((r - R) / (w * 0.25), 2.0));
		a = fade;
	}
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
