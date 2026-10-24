shader_type particles;
// Glowing matter spiralling into the black hole (BlackHole), in the emitter's local frame
// (Y = disk normal). Each particle starts on a ring near the disk's outer edge (or, for
// `debris`, anywhere on a large shell), circles with Keplerian speed and sinks inwards ever
// faster, heating from red to white, and vanishes at the horizon.

uniform float rs = 2.0;
uniform float start_radius = 14.0;
uniform float thickness = 0.6;
uniform float spin = 1.0;
// Debris mode: falls in from a shell of this radius instead of orbiting in the disk.
uniform bool debris = false;
uniform float shell = 40.0;
uniform vec4 cold : source_color = vec4(1.0, 0.35, 0.12, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float size = 0.18;

float rand(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 9973u + RANDOM_SEED;
	if (debris) {
		float z = rand(s) * 2.0 - 1.0;
		float a = rand(s) * 6.2832;
		float q = sqrt(1.0 - z * z);
		vec3 dir = vec3(q * cos(a), z * 0.6, q * sin(a));
		CUSTOM.xyz = dir * shell * (0.7 + 0.3 * rand(s));
		CUSTOM.w = 0.0;
	} else {
		CUSTOM.x = rand(s) * 6.2832;
		CUSTOM.y = start_radius * (0.7 + 0.45 * rand(s));
		CUSTOM.z = (rand(s) - 0.5) * thickness;
		CUSTOM.w = 0.0;
	}
	COLOR = cold;
	TRANSFORM = mat4(1.0);
}

void process() {
	vec3 pos;
	float heat;
	if (debris) {
		vec3 p = CUSTOM.xyz;
		float r = max(length(p), 0.001);
		CUSTOM.w += DELTA * (2.0 + 80.0 * rs / r);
		p -= p / r * CUSTOM.w * DELTA;
		// A little swirl as it nears.
		p += cross(vec3(0.0, 1.0, 0.0), p) / r * spin * 3.0 * rs / r * DELTA * 4.0;
		CUSTOM.xyz = p;
		pos = p;
		heat = clamp(1.0 - (length(p) - rs) / (shell * 0.5), 0.0, 1.0);
		if (length(p) < rs * 1.05) {
			ACTIVE = false;
		}
	} else {
		float r = CUSTOM.y;
		float omega = spin * 2.2 * pow(r / (rs * 2.6), -1.5);
		CUSTOM.x += omega * DELTA;
		CUSTOM.y = r - DELTA * (0.3 + 6.0 * pow(rs / r, 2.0)) * rs;
		CUSTOM.z *= exp(-DELTA * 0.6);
		pos = vec3(cos(CUSTOM.x) * r, CUSTOM.z, sin(CUSTOM.x) * r);
		heat = clamp(1.0 - (r - rs * 2.0) / (start_radius - rs * 2.0), 0.0, 1.0);
		if (r < rs * 1.15) {
			ACTIVE = false;
		}
	}
	float s = size * (0.6 + 0.8 * heat);
	TRANSFORM = mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(pos, 1.0));
	COLOR = mix(cold, hot, heat);
	COLOR.rgb *= 1.0 + heat * 2.0;
	COLOR.a = 1.0;
}
