shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Heat shimmer above the fire pool (FirePatch): a Y-axis billboard that refracts what is behind
// it with noise rising through it; strongest in its lower middle, invisible at its edges.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.012;
instance uniform float strength = 1.0;

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
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - c;
	to_cam.y = 0.0;
	vec3 z = normalize(to_cam + vec3(1e-4, 0.0, 0.0));
	vec3 x = cross(vec3(0.0, 1.0, 0.0), z);
	vec3 world = c + x * VERTEX.x * length(MODEL_MATRIX[0].xyz) + vec3(0.0, VERTEX.y * length(MODEL_MATRIX[1].xyz), 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(1.0);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float mask = (1.0 - smoothstep(0.2, 0.5, abs(uv.x - 0.5))) * smoothstep(0.0, 0.25, uv.y) * (1.0 - smoothstep(0.5, 1.0, uv.y));
	vec2 n = vec2(noise(vec2(uv.x * 9.0, uv.y * 6.0 - TIME * 2.2)), noise(vec2(uv.x * 7.0 + 4.0, uv.y * 5.0 - TIME * 1.7))) - 0.5;
	vec2 off = n * amount * mask * strength;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = clamp(mask * strength * 4.0, 0.0, 1.0);
}
