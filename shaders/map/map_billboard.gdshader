shader_type spatial;
render_mode unshaded, cull_disabled;

// Upright billboards for the map's trees (MultiMesh). Each quad turns about the vertical
// axis only, so trees always stand straight. INSTANCE_CUSTOM.x = icon index in the atlas.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float icons = 3.0;
// 0..1 while the relief rises out of the paper.
uniform float relief_amount = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz) * min(1.0, relief_amount * 1.3);
	origin.y *= relief_amount;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(to_cam + vec3(0.0001, 0.0, 0.0))));
	vec3 world = origin + right * VERTEX.x * s * 0.8 + vec3(0.0, VERTEX.y * s, 0.0);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	UV.x = (UV.x + floor(INSTANCE_CUSTOM.x + 0.5)) / icons;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) {
		discard;
	}
	ALBEDO = t.rgb;
}
