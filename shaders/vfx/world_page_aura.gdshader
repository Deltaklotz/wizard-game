shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Rarity aura of a spell page lying in the world (WorldItem), so its worth shows from afar. Drawn
// on a camera-facing billboard `margin` units larger than the page on every side. It does not
// turn with the page, and it is pushed `push_back` metres away from the camera (rescaled so its
// size on screen stays the same), so it always sits behind the turning page and never cuts
// through it.
//   rarity 0 Arcane (blue): soft breathing glow and a sheen running round the border.
//   1 Eldritch (purple): + a second counter-running sheen and drifting sparkles.
//   2 Celestial (gold): + slowly turning sun rays and brighter sparkles – it shines.
//   3 Primordial (black): a pulsing corona of black fire with violet-white seams licking outwards,
//     a dark aura swallowing the light around the page, a blinding thin "event horizon" line
//     hugging it, three sparks orbiting it with trails, embers drifting up.
// The light radiates from a narrow capsule core (card_size, much thinner than the page) that hides
// behind the page whichever way it turns, so there are no hard frame lines that could float around
// a turned page – only soft light, rays, sparkles and flames coming from behind it.
// Units: card_size / margin in "card pixels" (page = 58 x 82), UV covers the whole quad.

uniform int rarity = 0;
uniform vec4 color : source_color = vec4(0.35, 0.62, 1.0, 1.0);
uniform vec2 card_size = vec2(54.0, 76.0);
uniform float margin = 18.0;
uniform float selected = 0.0;
uniform float hover = 0.0;
uniform bool overlay = false;
uniform float seed = 0.0;
// Brightness multiplier (above 1 so the coloured auras bloom).
uniform float energy = 1.8;
// Metres the billboard sits behind the page centre, seen from the camera (> the page's half
// diagonal, so the page can turn freely in front of it).
uniform float push_back = 0.45;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_center = center - CAMERA_POSITION_WORLD;
	float dist = max(length(to_center), 0.01);
	vec3 dir = to_center / dist;
	float grow = (dist + push_back) / dist;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + dir * push_back + (right * VERTEX.x + up * VERTEX.y) * grow;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

// Signed distance (px) to the card's rounded rectangle.
float card_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 aura(vec2 uv) {
	vec2 full = card_size + 2.0 * margin;
	vec2 p = (uv - 0.5) * full;
	float d = card_sdf(p, card_size * 0.5, card_size.x * 0.5);
	// Angle round the card, normalised by its shape (0..1).
	float ang = atan(p.y / card_size.y, p.x / card_size.x) / 6.2832 + 0.5;
	float t = TIME + seed * 7.0;

	if (rarity < 0) {
		// Empty slot: faint outline.
		float line = smoothstep(1.4, 0.4, abs(d)) * (0.25 + 0.35 * selected);
		return vec4(vec3(0.85, 0.78, 0.62), line);
	}

	if (rarity < 3) {
		if (overlay) {
			return vec4(0.0);
		}
		vec3 c = color.rgb;
		float boost = 1.0 + 0.6 * hover + 0.5 * selected;
		float out_d = max(d, 0.0);
		float breathe = 0.8 + 0.2 * sin(t * 2.2);
		float glow = exp(-out_d / (margin * (0.3 + 0.05 * float(rarity)))) * breathe;
		float border = 0.0;
		float sheen = pow(0.5 + 0.5 * cos((ang - t * 0.22) * 6.2832), 8.0) * exp(-out_d / (margin * 0.4)) * 0.6;
		if (rarity >= 1) {
			sheen += pow(0.5 + 0.5 * cos((ang + t * 0.15 + 0.5) * 6.2832), 10.0) * exp(-out_d / (margin * 0.35)) * 0.5;
		}
		float rays = 0.0;
		if (rarity >= 2) {
			float ra = atan(p.y, p.x);
			rays = pow(0.5 + 0.5 * sin(ra * 12.0 + t * 0.4), 6.0) * exp(-out_d / (margin * 0.45)) * step(0.0, d) * 0.6;
		}
		float spark = 0.0;
		if (rarity >= 1) {
			vec2 cell = floor((p + vec2(0.0, t * 9.0)) / 7.0);
			float h = hash(cell + seed);
			vec2 f = fract((p + vec2(0.0, t * 9.0)) / 7.0) - 0.5;
			spark = step(0.94 - 0.03 * float(rarity), h) * exp(-dot(f, f) * 40.0) * step(0.0, d) * exp(-out_d / (margin * 0.45))
				* (0.5 + 0.5 * sin(t * 6.0 + h * 30.0));
		}
		float a = clamp(glow * 0.75 + border * 0.9 + sheen + rays + spark, 0.0, 1.0) * boost;
		vec3 col = mix(c, vec3(1.0), clamp(sheen * 0.6 + border * 0.25 + spark * 0.7, 0.0, 1.0));
		return vec4(col * (1.0 + 0.4 * selected), clamp(a, 0.0, 1.0));
	}

	// --- Primordial ---
	vec3 violet = vec3(0.62, 0.36, 1.0);
	vec3 white_hot = vec3(0.95, 0.88, 1.0);
	if (overlay) {
		// On top of the card: darkness creeping in from its edges and void smoke swirling over it.
		if (d > 0.0) {
			return vec4(0.0);
		}
		float inside = -d;
		vec2 q = p / card_size.y;
		float r = length(q);
		float swirl = atan(q.y, q.x) + r * 6.0 - t * 0.6;
		float smoke = fbm(vec2(cos(swirl), sin(swirl)) * 2.5 + r * 3.0 + vec2(t * 0.1, 0.0));
		float creep = smoothstep(12.0, 0.0, inside + 4.0 * fbm(vec2(ang * 18.0, t * 0.5)));
		float a = clamp(creep * 0.85 + smoothstep(0.55, 0.8, smoke) * 0.35, 0.0, 0.92);
		vec3 col = mix(vec3(0.0), violet * 0.35, smoothstep(0.6, 0.9, smoke));
		// Crackles of violet light over the page.
		float crack = smoothstep(0.03, 0.0, abs(fbm(q * 9.0 + vec2(0.0, t * 0.3)) - 0.5)) * step(0.7, noise(vec2(t * 2.0, seed)));
		col += white_hot * crack * 0.8;
		a = max(a, crack * 0.7);
		return vec4(col, a);
	}
	float out_d = max(d, 0.0);
	float h = out_d / margin;
	// Black fire: tongues rising out of the border. Noise stretched along the perimeter and
	// scrolling outwards, so it forms flickering flames rather than blobs.
	vec2 fp = vec2(ang * 46.0, h * 1.4 - t * 1.9);
	fp.x += 0.8 * sin(fp.y * 1.7 + t * 1.3 + ang * 20.0);
	float fire = fbm(fp) * 0.75 + 0.45 * noise(vec2(ang * 120.0, h * 3.0 - t * 3.2));
	// Taller towards the top (fire rises), fading out well before the edge of the aura.
	float up = clamp(-p.y / card_size.y + 0.5, 0.0, 1.0);
	// The whole corona breathes: swelling and shrinking like a slow, heavy pulse.
	float beat = 0.5 + 0.5 * sin(t * 2.2);
	beat = beat * beat;
	float body = fire * 1.25 - h * (1.25 - 0.4 * up - 0.3 * beat) - 0.18;
	body *= 1.0 - smoothstep(0.6, 0.95, h);
	float flame = smoothstep(0.0, 0.18, body);
	float seam = smoothstep(0.0, 0.05, body) * (1.0 - smoothstep(0.05, 0.16, body));
	// Dark aura swallowing the light around it.
	float aura = exp(-out_d / (margin * 0.45)) * 0.8;
	// Event horizon: blinding thin line hugging the card, pulsing.
	float horizon = 0.0;
	// Three sparks orbiting the card with trails.
	float sparks = 0.0;
	for (int k = 0; k < 3; k++) {
		float pos = fract(t * (0.18 + 0.05 * float(k)) + float(k) / 3.0);
		float da = fract(pos - ang + 1.0);
		float trail = exp(-da * 30.0) * step(0.0, da);
		sparks += trail * exp(-pow((d - margin * 0.55) / 2.5, 2.0)) * (k == 1 ? 0.8 : 1.0);
	}
	float a = max(max(aura, flame), max(horizon, sparks));
	vec3 col = vec3(0.0);
	col = mix(col, violet * 1.8, seam);
	// Embers drifting up out of the fire.
	vec2 ec = (p + vec2(0.0, t * 16.0)) / 6.0;
	float eh = hash(floor(ec) + seed * 13.0);
	vec2 ef = fract(ec) - 0.5;
	float ember = step(0.93, eh) * exp(-dot(ef, ef) * 30.0) * step(0.0, d) * (1.0 - smoothstep(0.3, 1.0, h));
	col = mix(col, violet * 2.0, ember);
	a = max(a, ember);
	col = mix(col, white_hot * 1.6, clamp(horizon + sparks, 0.0, 1.0));
	col *= 1.0 + 0.4 * hover + 0.3 * selected;
	return vec4(col, clamp(a, 0.0, 1.0));
}

void fragment() {
	vec4 c = aura(UV);
	// Fade out well before the edges of the plane, so its outline never shows.
	vec2 e = min(UV, 1.0 - UV);
	float fade = smoothstep(0.0, 0.18, min(e.x, e.y));
	ALBEDO = c.rgb * energy;
	ALPHA = c.a * fade;
}
