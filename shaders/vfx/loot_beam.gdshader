shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Light pillar above a dropped spell page (WorldItem), so its rarity shows from far away. A
// Y-axis billboard quad: soft column in the rarity colour, brightest at the bottom, fading
// upwards, with bands drifting up it. Primordial: a dark violet column with thin white seams
// pulsing. Grows a little brighter with distance so it stays visible.

uniform vec3 color : source_color = vec3(0.35, 0.62, 1.0);
uniform bool primordial = false;
uniform float energy = 1.4;
// Metres the pillar sits behind the page, seen from the camera (horizontally), rescaled so its
// width on screen stays the same – it never passes through the turning page.
uniform float push_back = 0.5;

varying float v_dist;

void vertex() {
	// Y-axis billboard.
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - c;
	to_cam.y = 0.0;
	float flat_dist = max(length(to_cam), 0.01);
	vec3 z = to_cam / flat_dist;
	vec3 x = cross(vec3(0.0, 1.0, 0.0), z);
	float grow = (flat_dist + push_back) / flat_dist;
	c -= z * push_back;
	VERTEX = c + x * VERTEX.x * length(MODEL_MATRIX[0].xyz) * grow + vec3(0.0, VERTEX.y * length(MODEL_MATRIX[1].xyz), 0.0);
	v_dist = length(CAMERA_POSITION_WORLD - c);
	MODELVIEW_MATRIX = VIEW_MATRIX;
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float h = 1.0 - UV.y;  // 0 bottom, 1 top
	float column = exp(-x * x * 9.0) * pow(1.0 - h, 1.6) * smoothstep(0.0, 0.04, h);
	float core = exp(-x * x * 80.0) * pow(1.0 - h, 2.5);
	float bands = 0.75 + 0.25 * sin(h * 30.0 - TIME * 3.0);
	float far = clamp(v_dist / 25.0, 0.4, 1.6);
	vec3 col;
	if (primordial) {
		float pulse = 0.6 + 0.4 * sin(TIME * 2.2);
		col = vec3(0.32, 0.12, 0.6) * column * bands * pulse + vec3(0.9, 0.8, 1.0) * core * pulse;
	} else {
		col = color * column * bands + mix(color, vec3(1.0), 0.6) * core;
	}
	ALBEDO = col * energy * far;
}
