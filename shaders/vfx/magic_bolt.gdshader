shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, world_vertex_coords;
// Arcane minigun orb (MagicBolt). One mesh with two quads, placed here in world space:
//   COLOR.r = 0: camera-facing orb – white-hot centre, blue core, purple halo, with two-tone
//                arms swirling around it.
//   COLOR.r = 1: streak behind the orb along -dir, turned to face the camera around its axis,
//                tapering and shifting from blue to purple, with a twisting band.

uniform vec3 color : source_color = vec3(0.62, 0.3, 1.0);
uniform vec3 accent : source_color = vec3(0.32, 0.6, 1.0);
uniform float energy = 2.6;
instance uniform vec3 dir = vec3(0.0, 0.0, -1.0);
instance uniform float size = 0.34;
instance uniform float tail = 3.0;
instance uniform float seed = 0.0;

varying float v_kind;
varying vec2 v_uv;

void vertex() {
	vec3 head = MODEL_MATRIX[3].xyz;
	vec2 q = UV - 0.5;
	v_kind = COLOR.r;
	v_uv = UV;
	if (COLOR.r < 0.5) {
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		VERTEX = head + (right * q.x - up * q.y) * size;
	} else {
		vec3 d = normalize(dir);
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - head);
		vec3 side = cross(d, to_cam);
		float s = length(side);
		side = s > 0.0001 ? side / s : INV_VIEW_MATRIX[0].xyz;
		// UV.y: 0 at the orb, 1 at the end of the tail.
		VERTEX = head + side * q.x * size * 0.55 - d * UV.y * tail;
	}
}

void fragment() {
	vec3 col;
	if (v_kind < 0.5) {
		vec2 c = v_uv * 2.0 - 1.0;
		float r = length(c);
		float a = atan(c.y, c.x);
		float halo = exp(-r * r * 3.5) * (1.0 - smoothstep(0.85, 1.0, r));
		float core = exp(-r * r * 22.0);
		float hot = exp(-r * r * 70.0);
		// Two arms spiralling around the core, one blue, one purple.
		float arm = 0.5 + 0.5 * sin(a * 2.0 + r * 9.0 - TIME * 26.0 + seed * 6.28);
		float arms = smoothstep(0.55, 0.95, arm) * smoothstep(0.15, 0.4, r) * (1.0 - smoothstep(0.55, 0.9, r));
		vec3 swirl = mix(accent, color, step(0.0, sin(a + r * 4.5 - TIME * 13.0 + seed * 6.28)));
		col = color * halo * 0.7 + swirl * arms * 1.2 + accent * core * 1.4 + vec3(1.0, 0.95, 1.0) * hot * 2.0;
	} else {
		float t = v_uv.y;
		float x = v_uv.x * 2.0 - 1.0;
		float width = mix(0.55, 0.05, t);
		float body = exp(-pow(x / width, 2.0) * 2.5) * pow(1.0 - t, 1.6) * smoothstep(0.0, 0.08, t);
		float twist = 0.5 + 0.5 * sin(t * 26.0 - TIME * 30.0 + x * 3.0 + seed * 6.28);
		vec3 c = mix(accent, color, clamp(t * 1.6 + (twist - 0.5) * 0.6, 0.0, 1.0));
		col = c * body * (0.6 + 0.5 * twist) + vec3(0.9, 0.9, 1.0) * body * exp(-x * x * 40.0) * (1.0 - t) * 0.6;
	}
	ALBEDO = col * energy;
}
