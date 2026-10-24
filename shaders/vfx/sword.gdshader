shader_type spatial;
// Giant sword of the Sword Wall spell (SwordModel). part: 0 = blade, 1 = gold, 2 = gems.
//   Blade: pearly white with brushed streaks along its length and a faint iridescent sheen at
//   grazing angles, a gold-inlaid fuller with runes that glow, and gold filigree near the base.
//   Gold: polished, slightly mottled. Gems: deep turquoise with an inner glow.
// Instance uniforms: dissolve (0..1, noise-eaten with a glowing edge when the wall expires),
// glow (rune/edge glow after impact).

uniform int part = 0;
uniform vec3 pearl : source_color = vec3(0.8, 0.79, 0.77);
uniform vec3 grime : source_color = vec3(0.32, 0.27, 0.2);
// Blade v (0 = base, 1 = tip) at ground level: SwordWall.VISIBLE_BLADE / SwordModel.BLADE_LEN.
uniform float ground_v = 0.292;
uniform vec3 gold : source_color = vec3(1.0, 0.7, 0.26);
uniform vec3 gem : source_color = vec3(0.06, 0.62, 0.55);
uniform vec3 rune : source_color = vec3(1.0, 0.82, 0.42);
instance uniform float dissolve = 0.0;
instance uniform float glow = 0.0;

varying vec3 v_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Dissolve: noise threshold rising from 0 to past 1, with a hot edge.
	float n = noise(v_local * 0.8) * 0.6 + noise(v_local * 3.3) * 0.4;
	float cut = dissolve * 1.15 - 0.05;
	if (dissolve > 0.0 && n < cut) {
		discard;
	}
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.07, n - cut) : 0.0;

	vec3 emission = vec3(0.0);
	if (part == 0) {
		float u = UV.x * 2.0 - 1.0;
		float v = UV.y;
		float au = abs(u);
		float fuller = (1.0 - smoothstep(0.09, 0.12, au)) * (1.0 - smoothstep(0.74, 0.8, v));
		// Filigree: wavy gold lines curling either side of the fuller near the base.
		float wave = abs(sin(v * 70.0 + 2.6 * sin(au * 16.0 + v * 9.0)));
		float fili = (1.0 - smoothstep(0.06, 0.16, wave)) * smoothstep(0.13, 0.17, au)
			* (1.0 - smoothstep(0.32 + 0.12 * sin(v * 40.0), 0.42 + 0.12 * sin(v * 40.0), au))
			* (1.0 - smoothstep(0.12, 0.2, v));
		float inlay = max(fuller, fili);
		float streak = noise(vec3(v_local.x * 3.0, v_local.y * 0.15, v_local.z * 3.0));
		// Polished edge bevel brighter than the brushed flats.
		float bevel = smoothstep(0.76, 0.84, au);
		vec3 base = pearl * (0.86 + 0.14 * streak) * mix(0.92, 1.12, bevel);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 irid = 0.5 + 0.5 * cos(6.2831 * (fres * 1.3 + v * 0.8 + au * 0.6 + vec3(0.0, 0.33, 0.67)));
		base = mix(base, base * (0.7 + 0.6 * irid), 0.25 + 0.35 * fres);
		// Earth thrown onto the blade where it bit into the ground.
		float dirt = smoothstep(ground_v - 0.06, ground_v, v) * (0.55 + 0.45 * noise(v_local * vec3(2.0, 6.0, 2.0)));
		base = mix(base, grime, dirt * 0.8);
		ALBEDO = mix(base, gold, inlay * (1.0 - dirt * 0.7));
		METALLIC = mix(mix(0.45, 0.65, bevel), 1.0, inlay) * (1.0 - dirt);
		ROUGHNESS = mix(mix(0.2 + 0.08 * streak, 0.08, bevel), 0.3, inlay) + dirt * 0.6;
		// Runes in the fuller: short glowing dashes that breathe.
		float cell = floor(v * 55.0);
		float r = step(0.45, fract(sin(cell * 91.7) * 4375.5)) * step(0.15, fract(v * 55.0)) * step(fract(v * 55.0), 0.85);
		float runes = fuller * r * (1.0 - smoothstep(0.03, 0.06, au));
		emission += rune * runes * (0.25 + 0.15 * sin(TIME * 2.0 + cell) + glow * 2.0);
	} else if (part == 1) {
		float mottle = noise(v_local * 6.0);
		ALBEDO = gold * (0.82 + 0.18 * mottle);
		METALLIC = 1.0;
		ROUGHNESS = 0.24 + 0.12 * mottle;
		emission += gold * glow * 0.15;
	} else {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		ALBEDO = gem * 0.5;
		METALLIC = 0.3;
		ROUGHNESS = 0.05;
		emission += gem * (0.6 + 0.5 * fres + 0.2 * sin(TIME * 3.0));
	}
	EMISSION = emission + rune * edge * 4.0;
}
