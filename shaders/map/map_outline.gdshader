shader_type spatial;
render_mode unshaded, cull_front;

// Inverted-hull ink outline: the mesh pushed out along its normals, back faces only.
uniform vec3 ink : source_color = vec3(0.18, 0.12, 0.08);
uniform float width = 0.012;

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = ink;
}
