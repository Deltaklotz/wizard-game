shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
// Black hole (BlackHole), drawn on the inside faces of a sphere of radius `influence` around it
// so it works from outside and from within. Every pixel traces its light ray backwards through
// the hole's gravity using the Schwarzschild null-geodesic equation in Newtonian form
//     d²x/ds² = -1.5 · rs · h² · x / r⁵      (h = |x × dir|, conserved)
// which gives the correct shadow (~2.6 rs), photon ring (1.5 rs) and Einstein ring. Rays that
// fall below the horizon are black; rays that cross the accretion disk pick up its light and are
// dimmed by its dark gas (front to back, so the lensed far side of the disk arcs over and under
// the shadow; the disk is DISK_LAYERS flared, lumpy layers for a sense of volume); rays that escape
// show the scene behind, read from the screen at the bent direction. Scene depth is respected:
// geometry in front of the hole hides it, geometry inside the sphere is lensed.
// The bending is physical close to the hole (shadow, photon ring, the lensed far side of the
// disk) and fades out towards the edge of the sphere (lens_fade), so the surroundings are
// only gently warped. The disk is oriented per viewer (BlackHole sets disk_normal from the
// local camera): always seen from slightly above and tilted, the classic cinematic angle.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float rs = 2.0;
uniform float influence = 30.0;
uniform vec3 disk_normal = vec3(0.0, 1.0, 0.0);
// Disk radii in horizon radii, its brightness (0 = not formed yet) and spin speed.
uniform float disk_inner = 2.6;
uniform float disk_outer = 20.0;
// Bending fades out from this many horizon radii to the edge of the sphere.
uniform float lens_fade = 3.0;
// The disk fades out where it passes this close to the viewer (m), so its near side never
// fills the screen when standing close to or under the hole.
uniform float near_fade_start = 8.0;
uniform float near_fade_end = 32.0;
uniform float disk_strength = 1.0;
uniform float disk_spin = 1.0;
uniform vec3 disk_hot : source_color = vec3(1.0, 0.93, 0.8);
uniform vec3 disk_warm : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 disk_cool : source_color = vec3(0.75, 0.22, 0.12);
uniform float disk_energy = 3.0;
uniform float ring_energy = 2.0;
// 0..1: formation/collapse – fades the whole effect against the plain scene.
uniform float presence = 1.0;
uniform int max_steps = 120;
const int DISK_LAYERS = 5;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Disk matter at polar angle a, radius r (horizon radii): soft dusty body with dark lanes.
float disk_body(float a, float r, float seed) {
	float lr = log(r);
	float body = fbm(vec3(cos(a) * 2.5, sin(a) * 2.5, lr * 9.0 + seed));
	float lanes = smoothstep(0.2, 0.6, fbm(vec3(cos(a) * 4.0, sin(a) * 4.0, lr * 22.0 + seed * 2.0)));
	return clamp(0.25 + 1.2 * body * lanes, 0.0, 1.5);
}

// Thin glowing filaments wound along the orbit: ridged noise, stretched along the angle.
float disk_streaks(float a, float r, float seed) {
	float lr = log(r);
	float n1 = noise(vec3(cos(a) * 3.0, sin(a) * 3.0, lr * 70.0 + seed));
	float n2 = noise(vec3(cos(a) * 7.0, sin(a) * 7.0, lr * 150.0 + seed * 1.7));
	float r1 = pow(1.0 - abs(n1 * 2.0 - 1.0), 10.0);
	float r2 = pow(1.0 - abs(n2 * 2.0 - 1.0), 14.0) * 0.7;
	// Streaks come and go along their length.
	float gate = smoothstep(0.35, 0.75, noise(vec3(cos(a) * 1.5, sin(a) * 1.5, lr * 12.0 + seed * 3.0)));
	return (r1 + r2) * (0.35 + 0.65 * gate);
}

// One layer of the disk where a ray crosses it: emitted light (rgb) + opacity (a). The disk is
// dark, light-absorbing gas lit by bright filaments; `weight` = this layer's share of the
// disk's thickness (the middle layer is densest).
vec4 disk_sample(vec3 hit, vec3 ray_dir, vec3 n, vec3 t1, vec3 t2, float seed, float weight) {
	float r = length(hit - n * dot(hit, n)) / rs;
	if (r < disk_inner * 0.85 || r > disk_outer) {
		return vec4(0.0);
	}
	float u = clamp((r - disk_inner) / (disk_outer - disk_inner), 0.0, 1.0);
	float ang = atan(dot(hit, t2), dot(hit, t1));
	// Keplerian shear: inner parts turn faster. Two copies of the pattern advect on staggered
	// cycles and cross-fade, so it keeps visibly streaming round without winding up into rings.
	float omega = disk_spin * 2.4 * pow(r / disk_inner, -1.5);
	float period = 2.6;
	float c1 = fract(TIME / period);
	float c2 = fract(TIME / period + 0.5);
	float w1 = 1.0 - abs(c1 * 2.0 - 1.0);
	float a1 = ang - omega * c1 * period;
	float a2 = ang - omega * c2 * period;
	float body = mix(disk_body(a2, r, seed + 17.0), disk_body(a1, r, seed), w1);
	float streaks = mix(disk_streaks(a2, r, seed + 17.0), disk_streaks(a1, r, seed), w1);
	float extent = smoothstep(0.0, 0.04, u + 0.02) * (1.0 - smoothstep(0.45, 1.0, u))
		* smoothstep(disk_inner * 0.85, disk_inner * 1.02, r);
	// Temperature falls outwards: white-hot -> gold -> deep red.
	vec3 col = mix(disk_hot, disk_warm, smoothstep(0.0, 0.3, u));
	col = mix(col, disk_cool, smoothstep(0.3, 1.0, u));
	// Relativistic beaming, kept subtle (as in Interstellar) so both sides of the disk show.
	vec3 vel = normalize(cross(n, hit));
	float beam = pow(max(1.0 + 0.22 * dot(vel, -ray_dir) * sqrt(disk_inner / r), 0.05), 3.0);
	float redshift = sqrt(max(1.0 - 1.0 / r, 0.05));
	float heat = (0.5 + 1.2 * (1.0 - u) * (1.0 - u)) * beam * redshift;
	vec3 light = col * disk_energy * heat * (streaks * 2.2 + body * 0.18) * extent;
	// Dense, dark gas: darkens what lies behind.
	float opacity = clamp(body * 0.75 + streaks * 0.3, 0.0, 1.0) * extent * weight;
	return vec4(light * weight, opacity) * disk_strength;
}

// Height of disk layer s (-1..1) above the mid-plane at p: the disk flares outwards and puffs
// up and down in lumps.
float layer_height(vec3 p, vec3 n, vec3 t1, vec3 t2, float s) {
	vec3 flat_p = p - n * dot(p, n);
	float r = length(flat_p) / rs;
	float a = atan(dot(p, t2), dot(p, t1));
	float lump = 0.7 + 0.6 * noise(vec3(cos(a) * 3.0, sin(a) * 3.0, log(max(r, 0.1)) * 4.0 + s * 3.0));
	return s * rs * (0.12 + 0.05 * r) * lump;
}

vec2 project(vec3 world, mat4 view, mat4 proj, out float behind) {
	vec4 clip = proj * view * vec4(world, 1.0);
	behind = clip.w <= 0.0 ? 1.0 : 0.0;
	vec2 ndc = clip.xy / max(abs(clip.w), 1e-4);
	return ndc * 0.5 + 0.5;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 frag = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(frag - cam);
	vec3 center = NODE_POSITION_WORLD;
	vec3 oc = cam - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - influence * influence;
	float h = b * b - c;
	if (h < 0.0) {
		discard;
	}
	h = sqrt(h);
	float t_in = max(-b - h, 0.0);
	float t_out = -b + h;
	if (t_out <= 0.0) {
		discard;
	}
	// Distance to the scene surface along the straight view ray.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vpos.xyz /= vpos.w;
	float scene_dist = length(vpos.xyz);
	if (scene_dist < t_in) {
		discard;
	}

	vec3 n = normalize(disk_normal);
	vec3 t1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	t1 = normalize(cross(t1, n));
	vec3 t2 = cross(n, t1);

	vec3 p = oc + rd * t_in;
	vec3 dir = rd;
	float travelled = t_in;
	vec3 hx = cross(p, dir);
	float h2 = dot(hx, hx);
	vec3 acc = vec3(0.0);
	float alpha = 0.0;
	float glow = 0.0;
	bool captured = false;
	bool hit_scene = false;
	float min_r = 1e9;
	for (int i = 0; i < max_steps; i++) {
		float r = length(p);
		min_r = min(min_r, r);
		if (r < rs) {
			captured = true;
			break;
		}
		if (r > influence * 1.001 && dot(p, dir) > 0.0) {
			break;
		}
		float step_len = clamp(0.09 * (r - rs * 0.9), rs * 0.02, rs * 1.5);
		vec3 accel = -1.5 * rs * h2 * p / pow(r, 5.0);
		accel *= 1.0 - smoothstep(lens_fade * rs, influence, r);
		vec3 np = p + dir * step_len;
		dir = normalize(dir + accel * step_len);
		// Disk: several stacked, flared, lumpy layers, so it has thickness and parallax. Each
		// crossing is composited front to back.
		if (alpha < 0.99 && min(length(p), length(np)) < disk_outer * rs * 1.1) {
			for (int k = 0; k < DISK_LAYERS; k++) {
				float sk = float(k) / float(DISK_LAYERS - 1) * 2.0 - 1.0;
				float y0 = dot(p, n) - layer_height(p, n, t1, t2, sk);
				float y1 = dot(np, n) - layer_height(np, n, t1, t2, sk);
				if (y0 * y1 < 0.0) {
					vec3 hit = mix(p, np, y0 / (y0 - y1));
					float weight = (1.0 - 0.6 * abs(sk))
						* smoothstep(near_fade_start, near_fade_end, length(hit - oc));
					vec4 d = disk_sample(hit, dir, n, t1, t2, float(k) * 31.7, weight);
					acc += (1.0 - alpha) * d.rgb;
					alpha += (1.0 - alpha) * d.a;
				}
			}
		}
		// Photon ring: light skimming the photon sphere at 1.5 rs.
		glow += exp(-pow((r - 1.5 * rs) / (0.12 * rs), 2.0)) * step_len / rs;
		p = np;
		travelled += step_len;
		if (travelled > scene_dist) {
			hit_scene = true;
			break;
		}
	}

	vec3 bg = vec3(0.0);
	if (!captured) {
		float behind;
		vec3 world = hit_scene ? center + p : center + p + dir * 2000.0;
		vec2 uv = project(world, VIEW_MATRIX, PROJECTION_MATRIX, behind);
		if (behind > 0.5) {
			uv = 1.0 - uv;
		}
		// Full resolution only: the blurred mip levels come out dark where alpha-cut foliage is.
		bg = textureLod(screen_tex, clamp(uv, vec2(0.002), vec2(0.998)), 0.0).rgb;
	}
	vec3 ring = disk_hot * ring_energy * clamp(glow, 0.0, 3.0) * disk_strength;
	vec3 col = acc + (1.0 - alpha) * (bg + ring * (captured ? 0.0 : 1.0));
	vec3 plain = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	ALBEDO = mix(plain, col, presence);
	ALPHA = 1.0;
}
