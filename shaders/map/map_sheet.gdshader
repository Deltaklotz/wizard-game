shader_type spatial;
render_mode unshaded, cull_disabled;

// The map sheet: relief lifted out of the paper, and a roll-up / unroll animation.
// The paper is a PlaneMesh (UV y increases towards +Z, i.e. map north is -Z).

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Relief over the map frame only (map units 0..1). Negative values press into the paper.
uniform sampler2D relief_tex : filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.1, 0.06, 0.9, 0.94);
uniform float progress = 1.0;
uniform float relief_amount = 1.0;
uniform float relief_scale = 0.85;
uniform float paper_w = 11.0;
uniform float paper_d = 10.0;
uniform float roll_radius = 0.32;
uniform vec3 light_dir = vec3(-0.55, 0.75, -0.35);

varying vec3 v_normal;
varying float v_relief;

float relief(vec2 uv) {
	vec2 m = (uv - map_rect.xy) / (map_rect.zw - map_rect.xy);
	if (m.x < 0.0 || m.y < 0.0 || m.x > 1.0 || m.y > 1.0) {
		return 0.0;
	}
	return texture(relief_tex, m).r;
}

void vertex() {
	float roll_x = -paper_w * 0.5 + progress * paper_w;
	float s = VERTEX.x - roll_x;
	float k = relief_scale * relief_amount * smoothstep(0.0, 0.8, -s);
	float h = relief(UV) * k;
	float e = 0.0025;
	float dx = (relief(UV + vec2(e, 0.0)) - relief(UV - vec2(e, 0.0))) * k / (2.0 * e * paper_w);
	float dz = (relief(UV + vec2(0.0, e)) - relief(UV - vec2(0.0, e))) * k / (2.0 * e * paper_d);
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	vec3 p = vec3(VERTEX.x, h, VERTEX.z);
	if (s > 0.0) {
		// Wound part: a tightening spiral resting on the table.
		float ang = s / roll_radius;
		float r = max(roll_radius - 0.018 * ang / 6.2831, 0.03);
		p.x = roll_x + r * sin(ang);
		p.y = roll_radius - r * cos(ang);
		n = vec3(-sin(ang), cos(ang), 0.0);
	}
	VERTEX = p;
	v_normal = n;
	// Valleys pressed into the paper are shaded like raised ground.
	v_relief = abs(h);
}

void fragment() {
	vec4 tex = texture(paper_tex, UV);
	if (tex.a < 0.5) {
		discard;
	}
	vec3 n = FRONT_FACING ? v_normal : -v_normal;
	float lam = clamp(dot(normalize(n), normalize(light_dir)), 0.0, 1.0);
	vec3 paper = FRONT_FACING ? tex.rgb : tex.rgb * vec3(0.93, 0.88, 0.8);
	float raised = smoothstep(0.0, 0.06, v_relief);
	ALBEDO = paper * mix(0.9 + 0.14 * lam, 0.5 + 0.65 * lam, raised);
}
