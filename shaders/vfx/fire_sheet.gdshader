shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// One sheet of the fire pool (FirePatch): a Y-axis billboard showing a procedural flame –
// domain-warped fbm scrolling upwards, shaped wide at the root and torn into tongues higher up,
// coloured by temperature (dark red smoky edges -> orange -> yellow -> white-hot core) in HDR so
// the glow blooms. Soft where it meets the ground (depth fade). instance uniforms: seed,
// strength (0..1: the fire catching / dying – flames shrink and thin out).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float energy = 3.2;
uniform float speed = 1.1;
uniform float soft_depth = 0.6;
instance uniform float seed = 0.0;
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

vec3 blackbody(float t) {
	vec3 c = mix(vec3(0.0), vec3(0.45, 0.04, 0.01), smoothstep(0.0, 0.2, t));
	c = mix(c, vec3(1.0, 0.28, 0.02), smoothstep(0.2, 0.45, t));
	c = mix(c, vec3(1.0, 0.62, 0.12), smoothstep(0.45, 0.7, t));
	c = mix(c, vec3(1.0, 0.88, 0.5), smoothstep(0.7, 0.88, t));
	c = mix(c, vec3(1.0, 0.97, 0.9), smoothstep(0.88, 1.0, t));
	return c;
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
	vec2 uv = vec2(UV.x, 1.0 - UV.y);  // y: 0 at the root, 1 at the top
	float s = max(strength, 0.001);
	float h = uv.y / mix(0.35, 1.0, s);  // a weak fire is lower
	float t = TIME * speed + seed * 37.0;
	vec2 q = vec2(uv.x * 3.0 + seed * 13.0, uv.y * 2.2 - t);
	vec2 warp = vec2(fbm(q * 0.8 + vec2(0.0, t * 0.35)), fbm(q * 0.8 + vec2(5.2, 1.3) - vec2(0.0, t * 0.2)));
	float n = fbm(q * 1.4 + (warp - 0.5) * 2.4);
	float x = (uv.x - 0.5) * 2.0;
	x += (warp.x - 0.5) * 0.7 * h;  // the flame sways and licks sideways
	// Dense only at the root; higher up the noise has to beat a rising threshold, so the
	// fire tears into separate tongues that thin out and vanish.
	float width = mix(0.9, 0.35, clamp(h, 0.0, 1.0));
	float xs = 1.0 - smoothstep(0.15 * width, width, abs(x));
	float temp = clamp((n - 0.22 - h * 0.62) * 2.4 * xs, 0.0, 1.0) * mix(0.6, 1.0, s);
	// Soft where it meets the ground / geometry.
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float scene_z = -sp.z / sp.w;
	float soft = clamp((scene_z + VERTEX.z) / soft_depth, 0.0, 1.0);
	float alpha = smoothstep(0.02, 0.22, temp) * soft * smoothstep(0.0, 0.05, uv.y + 0.02);
	// Mid temperatures stay saturated orange; only the hottest cores bloom towards white.
	ALBEDO = blackbody(temp) * mix(1.0, energy, temp * temp);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
