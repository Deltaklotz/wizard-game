// Stylized "AAA" lighting shared by the world's materials (call from their light()):
// soft wrapped diffuse with a warm band at the terminator, translucency for leaves and
// grass when the sun is behind them, a sun-coloured rim on silhouettes, a soft
// Blinn-Phong highlight, and moving cloud shadows. Not physically based - tuned for
// saturated colours: warm sunlit sides against cool, sky-lit shadows.

// Cloud layer shared with the sky shader (set by Atmosphere.gd):
// cloud_params = (wind offset x, wind offset z, weather scale 1/m, coverage).
global uniform sampler2D cloud_weather : filter_linear, repeat_enable;
global uniform vec4 cloud_params;
// Unit vector towards the sun.
global uniform vec3 sun_direction;

const float CLOUD_SHADOW_HEIGHT = 2200.0;
const vec3 TERMINATOR_WARM = vec3(1.0, 0.62, 0.38);

// 1 = full sun, lower under a cloud. Projects the point up to the cloud layer along the sun.
float cloud_shadow(vec3 wp) {
	vec3 s = normalize(sun_direction);
	if (s.y < 0.05 || cloud_params.z <= 0.0) {
		return 1.0;
	}
	vec2 p = wp.xz + s.xz * (CLOUD_SHADOW_HEIGHT - wp.y) / s.y;
	float w = textureLod(cloud_weather, (p + cloud_params.xy) * cloud_params.z, 0.0).r;
	float cov = clamp(cloud_params.w + (w - 0.5) * 0.9, 0.0, 1.0);
	return 1.0 - smoothstep(0.45, 0.75, cov) * 0.55;
}

// Diffuse part. `wrap` softens the falloff (0 = Lambert), `translucency` lets light through
// thin surfaces (tinted by `trans_color`), `rim` adds a lit edge on silhouettes.
vec3 stylized_diffuse(vec3 n, vec3 l, vec3 v, vec3 light_color, float atten, float wrap,
		float translucency, vec3 trans_color, float rim) {
	float ndl = dot(n, l);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float lit = smoothstep(0.0, 1.0, w);
	// Light "bleeding" into the surface where it turns away from the sun.
	float band = w * (1.0 - w) * 4.0 * (1.0 - smoothstep(0.6, 1.0, w));
	vec3 d = light_color * atten * (vec3(lit) + TERMINATOR_WARM * band * 0.22);
	if (translucency > 0.0) {
		float back = pow(clamp(dot(v, -l), 0.0, 1.0), 3.0) * 0.75 + clamp(-ndl, 0.0, 1.0) * 0.25;
		d += light_color * atten * trans_color * back * translucency;
	}
	if (rim > 0.0) {
		float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
		// Strongest when the sun is beside or behind the surface.
		float side = clamp(0.35 - dot(v, l) * 0.65, 0.0, 1.0);
		d += light_color * atten * fres * side * rim;
	}
	return d / PI;
}

vec3 stylized_specular(vec3 n, vec3 l, vec3 v, vec3 light_color, float atten, float roughness, float strength) {
	vec3 h = normalize(l + v);
	float gloss = mix(160.0, 6.0, clamp(roughness, 0.0, 1.0));
	float s = pow(max(dot(n, h), 0.0), gloss) * (gloss + 8.0) / (8.0 * PI);
	return light_color * atten * s * strength * clamp(dot(n, l) * 4.0, 0.0, 1.0);
}
