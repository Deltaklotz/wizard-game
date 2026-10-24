shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Money Rain (MoneyRain.gd): the divine shaft of light below its cloud. Soft at the silhouette
// (faces seen edge-on fade, so it reads as a volume of light), slowly shifting rays round it,
// ripples of brightness drifting down; brighter towards the cloud, gone before its rim (which
// would show as a hard ring). Mesh-local y runs -height/2 .. height/2.

uniform vec3 color : source_color = vec3(1.0, 0.86, 0.52);
uniform float energy = 1.1;
uniform float height = 9.0;
instance uniform float strength = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// The cone mesh is centred on its node (half way up).
	float t = clamp(v_local.y / height + 0.5, 0.0, 1.0);
	float ang = atan(v_local.x, v_local.z);
	float rays = 0.5 + 0.5 * sin(ang * 7.0 + TIME * 0.35 + sin(ang * 3.0 - TIME * 0.25) * 2.0);
	rays *= 0.55 + 0.45 * sin(ang * 13.0 - TIME * 0.5);
	float drift = 0.5 + 0.5 * sin(v_local.y * 1.3 + TIME * 2.2 + ang * 4.0);
	float facing = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float ends = smoothstep(0.0, 0.25, t) * smoothstep(0.97, 0.7, t);
	float a = facing * ends * (0.25 + 0.75 * rays) * (0.85 + 0.15 * drift) * mix(0.55, 1.0, t);
	ALBEDO = color * energy * a * strength;
}
