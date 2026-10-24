shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Thick billboard puff for the Smoke Bomb cloud and the Money Rain cloud (particles; fade by
// COLOR.a, COLOR.rgb tints). Lit as a soft ball by the sun (global sun_direction), soft where it
// meets the ground (depth fade) and faded right in front of the camera (the HUD fogs the screen
// instead while the camera is inside a smoke cloud).

uniform vec3 tint : source_color = vec3(0.66, 0.64, 0.72);
uniform vec3 shadow_tint : source_color = vec3(0.3, 0.29, 0.36);
uniform float density = 0.92;
uniform float softness = 1.2;
uniform float near_fade = 1.2;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform vec3 sun_direction;

varying float v_seed;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a = TIME * 0.15 + v_seed * 6.28;
	vec2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * c;
	float n = noise(r * 2.0 + v_seed * 11.0) * 0.6 + noise(r * 4.5 - v_seed * 3.0) * 0.4;
	float len = length(c) + (n - 0.5) * 0.55;
	float blob = 1.0 - smoothstep(0.3, 1.0, len);
	// Soft ball normal in view space -> sun lighting.
	vec3 nv = normalize(vec3(c.x, -c.y, sqrt(max(0.0, 1.0 - min(dot(c, c), 1.0))) + 0.3));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	float lit = clamp(dot(nw, normalize(sun_direction)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(shadow_tint, tint, lit * (0.75 + 0.5 * n));
	ALBEDO = col * COLOR.rgb;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -view.z / view.w;
	float frag_z = -VERTEX.z;
	float soft = clamp((scene_z - frag_z) / softness, 0.0, 1.0);
	float near = smoothstep(near_fade * 0.3, near_fade, frag_z);
	ALPHA = clamp(blob * density * COLOR.a * soft * near, 0.0, 1.0);
}
