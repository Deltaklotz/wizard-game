shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Hex-tile energy shield (Shield / HexShieldMesh). Per tile: faint glassy fill, bright hex rim,
// fresnel glow. Hits send expanding ripples across the tiles and flash the tiles they strike;
// `damage` cracks more and more tiles (white-hot fracture lines, flickering when it is close
// to breaking); `reveal` grows tiles in by their order (UV2.y); `shatter` flings every tile out
// along its normal, tumbling, and fades them. Alive: energy waves sweep through the tiles in
// reveal order (up the dome, out across the ward), single tiles glint, every tile has an inner
// hex outline, the colour shifts towards `tint` along the reveal order, and struck tiles dent in.

uniform vec3 color : source_color = vec3(0.3, 0.75, 1.0);
uniform vec3 accent : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 crack_color : source_color = vec3(1.0, 0.96, 0.85);
uniform float reveal = 99.0;
uniform float damage = 0.0;
uniform float shatter = 0.0;
// Shatter flight distance in mesh units (the dome mesh is a unit sphere).
uniform float shatter_distance = 1.0;
uniform float opacity = 1.0;
// Hit ripples: xyz in mesh space, w = age in seconds (> 3 = none).
uniform vec4 hits[6];
uniform float ripple_speed = 2.0;
uniform float ripple_width = 0.12;
uniform float hit_size = 30.0;
// Second colour along the reveal order (top of the dome / outer rings).
uniform vec3 tint : source_color = vec3(0.6, 0.55, 1.0);
// Reveal order range (dome 0..1, ward 0..rings) and the energy waves running through it.
uniform float order_max = 1.0;
uniform float wave_speed = 0.45;
// How far struck tiles dent inwards (mesh units).
uniform float dent = 0.03;

varying vec3 v_center;
varying float v_rand;
varying vec2 v_uv;
varying float v_rim;
varying float v_show;
varying float v_order;

vec3 hash3(float n) {
	return fract(sin(vec3(n, n + 1.7, n + 3.1)) * vec3(43758.5453, 22578.145, 19642.349));
}

mat3 rotation(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void vertex() {
	v_center = CUSTOM0.xyz;
	v_rand = CUSTOM0.w;
	v_uv = UV;
	v_rim = UV2.x;
	v_order = UV2.y;
	float show = clamp((reveal - UV2.y) * 4.0, 0.0, 1.0);
	v_show = show * show * (3.0 - 2.0 * show);
	// Tiles pop in with a slight overshoot.
	float pop = v_show + sin(v_show * 3.1416) * 0.15;
	vec3 local = (VERTEX - v_center) * pop;
	vec3 offset = vec3(0.0);
	if (shatter > 0.0) {
		vec3 r = hash3(v_rand * 173.0);
		float s = shatter;
		local = rotation(normalize(r - 0.5 + vec3(0.001)), s * (5.0 + r.z * 10.0)) * local * (1.0 - s * 0.5);
		vec3 fly = NORMAL * (0.6 + r.x * 1.4) + (r - 0.5) * 0.9;
		offset = (fly * s * (1.6 - s * 0.6) - vec3(0.0, s * s * 1.2, 0.0)) * shatter_distance;
	}
	// Tiles near a fresh hit are knocked inwards and spring back.
	float push = 0.0;
	for (int i = 0; i < 6; i++) {
		float age = hits[i].w;
		if (age < 1.0) {
			float d = distance(v_center, hits[i].xyz);
			push += exp(-d * d * hit_size * 0.5) * exp(-age * 7.0) * cos(age * 25.0);
		}
	}
	offset -= NORMAL * clamp(push, -1.0, 1.0) * dent;
	VERTEX = v_center + offset + local;
}

void fragment() {
	float edge = smoothstep(0.87, 0.985, v_rim);
	// Inner outline, a smaller hexagon inside each tile.
	float inner = smoothstep(0.03, 0.0, abs(v_rim - 0.62)) * 0.5;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float rip = 0.0;
	float flash = 0.0;
	for (int i = 0; i < 6; i++) {
		float age = hits[i].w;
		if (age < 3.0) {
			float d = distance(v_center, hits[i].xyz);
			rip += exp(-pow((d - age * ripple_speed) / ripple_width, 2.0)) * exp(-age * 2.2);
			flash += exp(-d * d * hit_size) * exp(-age * 6.0);
		}
	}
	// Many hits at once (rapid fire) must not add up to a white-out.
	rip = min(rip, 1.0);
	flash = min(flash, 1.0);
	// Cracks: tiles fracture one by one as damage grows (each from its own random point).
	float cracked = smoothstep(v_rand, v_rand + 0.06, damage * 1.25 - 0.05);
	vec3 h = hash3(v_rand * 59.0);
	vec2 q = v_uv - (0.5 + (h.xy - 0.5) * 0.5);
	// Jagged fracture lines of different lengths from an impact point, plus a few branches.
	float crack = 0.0;
	int count = 3 + int(h.z * 3.0);
	for (int k = 0; k < 6; k++) {
		if (k >= count) {
			break;
		}
		vec3 hk = hash3(v_rand * 31.0 + float(k) * 7.3);
		float a = (float(k) + hk.x * 0.7) * 6.2832 / float(count) + v_rand * 9.0;
		vec2 dir = vec2(cos(a), sin(a));
		float along = dot(q, dir);
		float reach = 0.3 + hk.y * 0.5;
		float jag = (sin(along * 47.0 + hk.z * 20.0) * 0.6 + sin(along * 113.0 + hk.x * 9.0) * 0.4) * 0.03 * along;
		float side = abs(dot(q, vec2(-dir.y, dir.x)) + jag);
		float w = mix(0.016, 0.004, clamp(along / reach, 0.0, 1.0));
		crack += (1.0 - smoothstep(w, w * 2.2, side)) * step(0.0, along) * (1.0 - smoothstep(reach * 0.8, reach, along));
		// A branch splitting off part way.
		float b0 = reach * (0.3 + hk.z * 0.3);
		vec2 bdir = vec2(cos(a + 0.7 - hk.y * 1.4), sin(a + 0.7 - hk.y * 1.4));
		vec2 bq = q - dir * b0;
		float balong = dot(bq, bdir);
		float bside = abs(dot(bq, vec2(-bdir.y, bdir.x)) + sin(balong * 61.0 + hk.x * 5.0) * 0.012 * balong);
		crack += (1.0 - smoothstep(0.004, 0.01, bside)) * step(0.0, balong) * (1.0 - smoothstep(0.1, 0.2, balong)) * 0.8;
	}
	crack += exp(-dot(q, q) * 300.0) * 0.8;
	crack = clamp(crack, 0.0, 1.0) * cracked;
	float critical = smoothstep(0.65, 0.95, damage);
	float flick = 1.0 - critical * cracked * 0.5 * (0.5 + 0.5 * sin(TIME * 23.0 + v_rand * 40.0));
	float shimmer = 0.06 * sin(TIME * 2.0 + v_center.y * 4.0 + v_center.x * 3.0);
	// Energy waves: two bands sweeping through the tiles in reveal order.
	float span = order_max + 0.6;
	float w1 = fract(TIME * wave_speed) * span - 0.3;
	float w2 = fract(TIME * wave_speed + 0.5) * span - 0.3;
	float o = v_order + v_rand * 0.06;
	float wave = exp(-pow((o - w1) / (0.06 * span), 2.0)) + 0.6 * exp(-pow((o - w2) / (0.04 * span), 2.0));
	// Single tiles flaring up now and then.
	float glint = pow(max(sin(TIME * (0.7 + v_rand * 0.9) + v_rand * 61.0), 0.0), 60.0);
	vec3 base = mix(color, tint, clamp(v_order / max(order_max, 0.001), 0.0, 1.0) * 0.55);

	vec3 col = base * (0.5 + fres * 0.9 + shimmer) + mix(base, accent, 0.35) * (edge * 1.5 + inner)
		+ mix(base, accent, 0.5) * (rip * 1.3 + wave * (0.5 + edge * 1.5)) + accent * glint * 1.4
		+ crack_color * crack * 2.4 + accent * flash * 1.2;
	col = mix(col, col * vec3(1.15, 0.85, 0.8), critical * cracked * 0.6);
	float alpha = (0.07 + fres * 0.28 + edge * 0.45 + inner * 0.4 + rip * 0.35 + wave * (0.12 + edge * 0.4)
		+ glint * 0.35 + crack * 0.9 + flash * 0.5) * flick;
	alpha *= v_show * opacity * (1.0 - smoothstep(0.45, 1.0, shatter));
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
