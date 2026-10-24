shader_type spatial;
render_mode cull_disabled;
// Bounceshroom (Bounceshroom.gd): COLOR.r = part (0 stem, 1 cap, 2 gills underneath). Red cap
// with cream spots (3D cell pattern on the local position), pale fibrous stem, glowing gills.
// squash (instance): > 0 flattens and widens the cap (the bounce), < 0 stretches it; glow
// flashes the spots and gills.

uniform vec3 cap_color : source_color = vec3(0.85, 0.12, 0.2);
uniform vec3 cap_dark : source_color = vec3(0.45, 0.04, 0.12);
uniform vec3 spot_color : source_color = vec3(1.0, 0.95, 0.84);
uniform vec3 stem_color : source_color = vec3(0.93, 0.87, 0.76);
uniform vec3 glow_color : source_color = vec3(0.45, 0.9, 1.0);
uniform float top = 1.35;
instance uniform float squash = 0.0;
instance uniform float glow = 0.0;

varying vec3 v_local;
varying float v_part;

vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float spots(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float sp = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash3(i + g + 17.0);
				vec3 d = g + o * 0.6 + 0.2 - f;
				float r = mix(0.2, 0.36, o.x);
				sp = max(sp, (1.0 - smoothstep(r - 0.05, r, length(d))) * step(0.3, o.y));
			}
		}
	}
	return sp;
}

void vertex() {
	v_local = VERTEX;
	v_part = COLOR.r;
	float k = smoothstep(0.3, top, VERTEX.y);
	VERTEX.y *= 1.0 - squash * 0.32 * k;
	VERTEX.xz *= 1.0 + squash * 0.22 * k;
}

void fragment() {
	vec3 emit = vec3(0.0);
	if (v_part < 0.5) {
		float fib = 0.5 + 0.5 * sin(atan(v_local.x, v_local.z) * 40.0 + v_local.y * 3.0);
		ALBEDO = stem_color * (0.85 + 0.15 * fib) * mix(0.7, 1.0, smoothstep(0.0, 0.3, v_local.y));
		ROUGHNESS = 0.8;
	} else if (v_part < 1.5) {
		float rim = smoothstep(0.6, 1.5, length(v_local.xz));
		float sp = spots(v_local * 2.4);
		vec3 base = mix(cap_color, cap_dark, rim * 0.7);
		ALBEDO = mix(base, spot_color, sp);
		ROUGHNESS = mix(0.4, 0.7, sp);
		SPECULAR = 0.45;
		emit = spot_color * sp * (0.08 + glow * 1.5) + cap_color * glow * 0.4;
	} else {
		float r = length(v_local.xz);
		float gills = 0.5 + 0.5 * sin(atan(v_local.x, v_local.z) * 70.0);
		ALBEDO = mix(vec3(0.9, 0.82, 0.72), vec3(0.7, 0.6, 0.55), gills * 0.5);
		ROUGHNESS = 0.9;
		emit = glow_color * (0.5 + gills * 0.5) * smoothstep(0.3, 1.4, r) * (0.6 + glow * 2.0);
	}
	EMISSION = emit;
}
