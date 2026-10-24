shader_type canvas_item;
// Ornate resource bar (mana / health): a gilded capsule frame with bevel, a glassy track
// with flowing liquid, a lagging "ghost" of recent loss, a diamond gem cap on the left,
// and two fine golden filigree threads that wind around the frame while sparks run along it.
// Drawn on a ColorRect; `rect_size` is its size in pixels, `pad` the space around the capsule.

uniform vec2 rect_size = vec2(340.0, 52.0);
uniform float pad = 14.0;
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float ghost : hint_range(0.0, 1.0) = 1.0;
uniform vec4 deep : source_color = vec4(0.1, 0.18, 0.7, 1.0);
uniform vec4 bright : source_color = vec4(0.45, 0.78, 1.0, 1.0);
uniform float flash = 0.0;       // brief white-hot pulse (e.g. not enough mana)
uniform float phase = 0.0;       // offsets the animation so the bars move out of step
uniform float flow_dir = 1.0;    // direction the liquid drifts

const float M_PI = 3.14159265;
const vec3 GOLD_DARK = vec3(0.36, 0.22, 0.07);
const vec3 GOLD = vec3(0.83, 0.62, 0.26);
const vec3 GOLD_LIGHT = vec3(1.0, 0.9, 0.62);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

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
		v += noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Signed distance to a horizontal stadium (half straight length L, radius r).
float sd_stadium(vec2 p, float L, float r) {
	return length(vec2(max(abs(p.x) - L, 0.0), p.y)) - r;
}

// Position along the stadium outline, 0..1, clockwise from the top-left corner.
float perimeter(vec2 p, float L, float r) {
	float P = 4.0 * L + 2.0 * M_PI * r;
	float s;
	if (p.x > L) {
		s = 2.0 * L + (atan(p.y, p.x - L) + M_PI * 0.5) * r;
	} else if (p.x < -L) {
		float a = atan(p.y, p.x + L);
		if (a < 0.0) a += 2.0 * M_PI;
		s = 4.0 * L + M_PI * r + (a - M_PI * 0.5) * r;
	} else if (p.y < 0.0) {
		s = p.x + L;
	} else {
		s = 2.0 * L + M_PI * r + (L - p.x);
	}
	return s / P;
}

// Blend `c` over `base` with coverage `a`.
vec3 over(vec3 base, vec3 c, float a) { return mix(base, c, clamp(a, 0.0, 1.0)); }

void fragment() {
	float t = TIME + phase;
	vec2 px = UV * rect_size;
	vec2 p = px - rect_size * 0.5;
	vec2 half_size = rect_size * 0.5 - vec2(pad);
	float r = half_size.y;
	float L = half_size.x - r;
	float d = sd_stadium(p, L, r);
	float aa = 0.6;
	float s = perimeter(p, L, r);
	float P = 4.0 * L + 2.0 * M_PI * r;

	vec3 col = vec3(0.0);
	float alpha = 0.0;

	// Soft drop shadow under the frame.
	float shadow = (1.0 - smoothstep(-2.0, 7.0, sd_stadium(p - vec2(0.0, 2.5), L, r))) * 0.55;
	alpha = shadow;

	// --- Track and liquid (inside the frame) ---
	float frame_w = 3.2;
	float inner = d + frame_w;
	float inside = 1.0 - smoothstep(-aa, aa, inner);
	float ix = (p.x + half_size.x - frame_w) / (2.0 * (half_size.x - frame_w));  // 0..1 across the track
	float iy = p.y / max(r - frame_w, 1.0);                                        // -1 top .. 1 bottom
	vec3 track = mix(vec3(0.05, 0.03, 0.07), deep.rgb * 0.18, 0.5 + 0.5 * iy);
	// Faint engraved diagonal hatching on the empty glass.
	track += vec3(0.03, 0.025, 0.04) * step(0.8, fract((p.x + p.y) / 7.0));

	float wobble = sin(iy * 5.0 + t * 3.1) * 0.004 + sin(iy * 11.0 - t * 4.7) * 0.002;
	float edge = fill + wobble;
	float in_fill = 1.0 - smoothstep(edge - 0.002, edge + 0.002, ix);
	vec2 q = vec2(px.x / 26.0 - t * 0.35 * flow_dir, px.y / 14.0);
	float n = fbm(q + vec2(fbm(q * 1.7 + t * 0.2), 0.0));
	float swirl = fbm(q * 2.6 + vec2(t * 0.5 * flow_dir, -t * 0.2));
	vec3 liquid = mix(deep.rgb, bright.rgb, smoothstep(0.25, 0.85, n) * 0.75 + (0.5 - 0.5 * iy) * 0.35);
	liquid += bright.rgb * pow(swirl, 3.0) * 0.9;
	// Tiny rising sparkles in the liquid.
	vec2 bp = vec2(px.x / 9.0, px.y / 9.0 + t * 0.8);
	vec2 cell = floor(bp);
	vec2 fcell = fract(bp) - 0.5;
	float spark = step(0.9, hash(cell)) * smoothstep(0.16, 0.0, length(fcell)) * (0.5 + 0.5 * sin(t * 6.0 + hash(cell + 3.0) * 30.0));
	liquid += vec3(1.0, 0.97, 0.9) * spark * 0.6;
	// Bright meniscus at the leading edge.
	float meniscus = exp(-pow((ix - edge) * (2.0 * half_size.x) / 2.2, 2.0)) * step(0.001, fill) * step(fill, 0.999);
	vec3 ghost_col = mix(bright.rgb, vec3(1.0, 0.95, 0.85), 0.45) * 0.55;
	float in_ghost = (1.0 - smoothstep(ghost - 0.002, ghost + 0.002, ix)) * (1.0 - in_fill);
	vec3 body = track;
	body = over(body, ghost_col * (0.75 + 0.25 * sin(t * 14.0)), in_ghost);
	body = over(body, liquid, in_fill);
	body += bright.rgb * meniscus * 1.2 + vec3(1.0) * meniscus * 0.35;
	// Glass: highlight along the top, shading along the bottom.
	body += vec3(1.0) * smoothstep(-0.2, -0.95, iy) * 0.16 * smoothstep(0.0, 0.1, ix) * smoothstep(1.0, 0.9, ix);
	body *= 1.0 - smoothstep(0.3, 1.0, iy) * 0.35;
	body *= 1.0 - smoothstep(-2.5, 0.0, inner) * 0.5;   // inner shadow of the frame
	body += vec3(1.0, 0.97, 0.9) * flash * 0.5 * in_fill;
	col = over(col, body, inside);
	alpha = max(alpha, inside);

	// --- Gilded frame ---
	float band = smoothstep(aa, -aa, abs(d + frame_w * 0.5) - frame_w * 0.5 - 0.4);
	float across = clamp((d + frame_w) / frame_w, 0.0, 1.0);               // 0 inner .. 1 outer edge
	float bevel = sin(across * M_PI);
	float light_dir = 0.5 - 0.5 * clamp(p.y / r, -1.0, 1.0);               // lit from above
	vec3 gold = mix(GOLD_DARK, GOLD, bevel);
	gold = mix(gold, GOLD_LIGHT, pow(bevel, 6.0) * (0.35 + 0.65 * light_dir));
	gold *= 0.75 + 0.45 * light_dir;
	// Travelling glint on the frame.
	float glint = pow(max(0.0, sin((s * 2.0 - t * 0.25) * 2.0 * M_PI)), 60.0);
	gold += GOLD_LIGHT * glint * 0.9 * bevel;
	// Engraved notches at the quarters of the straight parts.
	float qx = fract((p.x + L) / (2.0 * L) * 4.0 + 0.5) - 0.5;
	float notch = step(abs(p.x), L * 0.99) * smoothstep(1.2, 0.3, abs(qx) * 2.0 * L / 4.0);
	gold = mix(gold, GOLD_LIGHT, notch * 0.6 * bevel);
	col = over(col, gold, band);
	alpha = max(alpha, band);
	// Fine outer hairline.
	float hair = smoothstep(0.9, 0.0, abs(d - 2.2)) * 0.8;
	col = over(col, GOLD * 0.9, hair);
	alpha = max(alpha, hair);

	// --- Filigree threads winding around the frame ---
	float k = max(floor(P / 58.0), 3.0);
	float threads = 0.0;
	for (int i = 0; i < 2; i++) {
		float ph = float(i) * M_PI;
		float w = sin(2.0 * M_PI * k * s - t * 1.7 + ph);
		float off = 1.0 + 6.0 * (0.5 + 0.5 * w);                              // swings between the frame and 7 px out
		// Threads only show on some stretches, which drift around the bar.
		float vis = smoothstep(-0.2, 0.6, sin(2.0 * M_PI * 3.0 * s + t * 0.6 + ph * 0.5));
		float line = smoothstep(0.9, 0.1, abs(d - off)) * vis;
		// When the thread dips towards the frame (w < 0) it passes behind the gold.
		line *= mix(1.0 - band, 1.0, step(0.0, w));
		threads = max(threads, line);
	}
	vec3 thread_col = mix(GOLD, GOLD_LIGHT, 0.5);
	col = over(col, thread_col, threads * 0.95);
	alpha = max(alpha, threads * 0.95);
	// Little curls: dots riding the outer crests of the threads.
	float crest = fract(s * k - t * 1.7 / (2.0 * M_PI) + 0.25);
	float crest2 = fract(s * k - t * 1.7 / (2.0 * M_PI) + 0.75);
	float seg = P / k;
	float curl = smoothstep(1.4, 0.4, length(vec2((crest - 0.5) * seg, d - 7.0)))
		* smoothstep(-0.2, 0.6, sin(2.0 * M_PI * 3.0 * s + t * 0.6));
	curl += smoothstep(1.4, 0.4, length(vec2((crest2 - 0.5) * seg, d - 7.0)))
		* smoothstep(-0.2, 0.6, sin(2.0 * M_PI * 3.0 * s + t * 0.6 + M_PI * 0.5));
	curl = clamp(curl, 0.0, 1.0);
	col = over(col, GOLD_LIGHT, curl);
	alpha = max(alpha, curl);

	// --- Sparks running along the outline, trailing light ---
	float sparks = 0.0;
	for (int j = 0; j < 3; j++) {
		float fj = float(j);
		float dir = j == 1 ? -1.0 : 1.0;
		float head = fract(t * (0.06 + 0.02 * fj) * dir + fj * 0.37 + phase * 0.1);
		float behind = j == 1 ? fract(s - head) : fract(head - s);
		float trail = exp(-behind * P / 26.0);
		float wave = 3.5 + 2.5 * sin(2.0 * M_PI * k * s - t * 1.7 + fj);
		float near_path = exp(-pow((d - wave) / 0.9, 2.0));
		float bd = min(behind, 1.0 - behind) * P;
		float head_glow = exp(-pow(bd / 2.5, 2.0)) * exp(-pow((d - wave) / 3.0, 2.0));
		sparks += trail * near_path * 0.8 + head_glow * 1.6;
	}
	vec3 spark_col = mix(GOLD_LIGHT, bright.rgb, 0.3);
	col += spark_col * sparks;
	alpha = max(alpha, clamp(sparks, 0.0, 1.0));

	// --- Diamond gem cap on the left end ---
	vec2 g = p - vec2(-half_size.x + 1.0, 0.0);
	float gr = r + 5.0;
	float gd = (abs(g.x) + abs(g.y) - gr) * 0.7071;                        // diamond SDF
	float gem_frame = smoothstep(aa, -aa, gd);
	float gem_in = smoothstep(aa, -aa, gd + 2.6);
	vec3 gem = mix(deep.rgb, bright.rgb, 0.35);
	// Facets: four quadrants shaded differently, a table in the middle.
	gem *= g.x < 0.0 ? (g.y < 0.0 ? 1.3 : 0.7) : (g.y < 0.0 ? 1.0 : 0.55);
	float table = smoothstep(aa, -aa, (abs(g.x) + abs(g.y)) - gr * 0.45);
	gem = mix(gem, mix(bright.rgb, vec3(1.0), 0.25), table * 0.6);
	gem += bright.rgb * (0.25 + 0.25 * sin(t * 2.2)) * max(0.0, 1.0 - length(g) / gr);
	gem += vec3(1.0) * pow(max(0.0, 1.0 - length(g - vec2(-gr * 0.25, -gr * 0.3)) / 3.0), 2.0);
	gem += vec3(1.0, 0.96, 0.85) * flash * 0.6;
	vec3 gem_gold = mix(GOLD_DARK, GOLD_LIGHT, clamp(0.5 - g.y / gr * 0.6 - g.x / gr * 0.2, 0.0, 1.0));
	col = over(col, gem_gold, gem_frame);
	col = over(col, gem, gem_in);
	alpha = max(alpha, gem_frame);
	// Four-point sparkle over the gem.
	float tw = pow(0.5 + 0.5 * sin(t * 1.3 + 1.0), 8.0);
	vec2 sg = g - vec2(gr * 0.2, -gr * 0.35);
	float star = (exp(-abs(sg.x) * 1.2) * exp(-abs(sg.y) * 0.25) + exp(-abs(sg.y) * 1.2) * exp(-abs(sg.x) * 0.25)) * tw;
	col += vec3(1.0, 0.97, 0.88) * star;
	alpha = max(alpha, clamp(star, 0.0, 1.0));

	COLOR = vec4(col, alpha);
}
