shader_type spatial;
render_mode cull_back, shadows_disabled;
// Crystal parts of the arcane minigun (MinigunRig): dark violet glass with an energy glow that
// runs from blue to purple, streams down the barrels as the wheel spins, and turns hot pink-white
// with heat; flickers while venting an overheat. glow_base: how much the part glows by itself.

uniform vec3 color : source_color = vec3(0.62, 0.3, 1.0);
uniform vec3 accent : source_color = vec3(0.32, 0.6, 1.0);
uniform vec3 hot : source_color = vec3(1.0, 0.42, 0.78);
uniform float glow_base = 1.0;
instance uniform float heat = 0.0;
instance uniform float spin = 0.0;
instance uniform float vent = 0.0;
instance uniform float fade = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// Energy pulses running along the part (UV.y), faster with spin.
	float flow = 0.5 + 0.5 * sin(UV.y * 18.0 - TIME * (6.0 + spin * 40.0));
	vec3 energy = mix(accent, color, UV.y * 0.7 + flow * 0.3);
	energy = mix(energy, hot, smoothstep(0.35, 1.0, heat));
	energy = mix(energy, vec3(1.0, 0.9, 1.0), smoothstep(0.85, 1.0, heat) * 0.5);
	float flicker = vent > 0.0 ? 0.55 + 0.45 * sin(TIME * 37.0) * sin(TIME * 13.0) : 1.0;
	// Thin bright veins over dark glass, plus the rim.
	float vein = smoothstep(0.82, 0.97, flow) + smoothstep(0.9, 1.0, sin(UV.x * 37.7)) * 0.6;
	float glow = glow_base * (0.25 + vein * (0.6 + 1.6 * spin) + 1.4 * heat) * flicker;
	ALBEDO = vec3(0.05, 0.025, 0.09) + energy * 0.06;
	METALLIC = 0.3;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = energy * (glow + fres * 1.6) * fade;
}
