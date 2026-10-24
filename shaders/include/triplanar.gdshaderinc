// Triplanar and planar mapping helpers working in world space.
// Normal maps are treated as OpenGL style (+Y up) and flipped so that
// tangent-space +Y points along +V of the projection.

vec3 unpack_normal(vec4 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	xy.y = -xy.y;
	return vec3(xy, sqrt(clamp(1.0 - dot(xy, xy), 0.0, 1.0)));
}

vec3 triplanar_weights(vec3 n, float sharpness) {
	vec3 w = pow(abs(n), vec3(sharpness));
	return w / max(dot(w, vec3(1.0)), 1e-4);
}

vec4 triplanar_sample(sampler2D tex, vec3 p, vec3 w) {
	vec4 c = vec4(0.0);
	if (w.x > 0.01) c += texture(tex, p.zy) * w.x;
	if (w.y > 0.01) c += texture(tex, p.xz) * w.y;
	if (w.z > 0.01) c += texture(tex, p.xy) * w.z;
	return c;
}

// Whiteout-blended triplanar normal mapping (world space in, world space out).
vec3 triplanar_normal(sampler2D tex, vec3 p, vec3 n, vec3 w) {
	vec3 tx = unpack_normal(texture(tex, p.zy));
	vec3 ty = unpack_normal(texture(tex, p.xz));
	vec3 tz = unpack_normal(texture(tex, p.xy));
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

// Tangent-space normal from a texture projected along world Y (uv = xz).
vec3 planar_normal_y(vec3 tn, vec3 n) {
	return normalize(vec3(tn.x + n.x, abs(tn.z) * n.y, tn.y + n.z));
}
