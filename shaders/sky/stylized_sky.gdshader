shader_type sky;

// Stylized sky: deep, saturated blue overhead fading to a bright, hazy horizon, a warm
// sun glow and disc, and painterly 2.5D clouds.
//
// Clouds are density fields on horizontal layers high above the world (a stack of
// cumulus layers plus thin cirrus). Lighting marches a few samples along the sun's
// direction *within the layer*: the side facing the sun is bright, the far side falls into
// cool blue-grey shade, thick centres read as darker undersides and thin edges glow as
// silver linings when you look towards the sun. No raymarched volume, so no noise or
// banding, and it is cheap enough for reflections too.
// Wind offset, coverage and the weather map are global uniforms shared with the ground's
// cloud shadows (see Atmosphere.gd).

global uniform sampler2D cloud_weather : filter_linear, repeat_enable;
global uniform vec4 cloud_params;

uniform sampler3D cloud_shape : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail : filter_linear_mipmap, repeat_enable;

uniform vec3 zenith_color : source_color = vec3(0.09, 0.28, 0.7);
uniform vec3 sky_color : source_color = vec3(0.28, 0.55, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.76, 0.85, 0.93);
uniform vec3 ground_color : source_color = vec3(0.45, 0.53, 0.62);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.8, 0.55);
uniform float sun_disc_size = 0.99965;
uniform float sky_energy = 1.0;

uniform float cloud_height = 2200.0;
// Metres between the stacked cumulus layers.
uniform float layer_spacing = 180.0;
// Texture tiles per metre.
uniform float cloud_shape_scale = 0.0002;
uniform float cloud_detail_scale = 0.0008;
// Number of cumulus layers (0 = no clouds) and sun samples for their shading.
uniform int cloud_layers = 3;
uniform int light_steps = 4;
uniform float cirrus_amount = 0.16;
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade_color : source_color = vec3(0.4, 0.5, 0.72);
uniform vec3 cloud_warm_color : source_color = vec3(1.0, 0.74, 0.5);
uniform float cloud_brightness = 1.2;

vec3 sky_gradient(vec3 dir, vec3 sun) {
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(horizon_color, sky_color, smoothstep(0.0, 0.28, y));
		col = mix(col, zenith_color, smoothstep(0.22, 1.0, y));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -y));
	}
	float sd = max(dot(dir, sun), 0.0);
	float near_horizon = 1.0 + 1.5 * exp(-abs(y) * 6.0);
	col += sun_glow_color * (pow(sd, 5.0) * 0.16 + pow(sd, 40.0) * 0.4 + pow(sd, 400.0) * 1.2) * near_horizon;
	return col * sky_energy;
}

float remap01(float v, float a, float b) {
	return clamp((v - a) / (b - a), 0.0, 1.0);
}

// Cloud thickness (0..1) at a point of a layer. `layer` in 0..1 shifts the noise a little
// and keeps only the cores higher up, so stacked layers form towers with wide bases.
float cloud_thickness(vec2 xz, float layer, bool detailed) {
	vec2 q = xz + cloud_params.xy;
	float weather = textureLod(cloud_weather, q * cloud_params.z, 0.0).r;
	float cov = clamp(cloud_params.w + (weather - 0.5) * 0.9, 0.0, 1.0);
	// Slowly evolving shapes: the third texture axis drifts with the wind offset.
	float evolve = cloud_params.x * 0.016;
	vec3 p = vec3(q.x, layer * 180.0 + evolve, q.y);
	float base = textureLod(cloud_shape, p * cloud_shape_scale, 0.0).r;
	float billow = textureLod(cloud_detail, p * cloud_shape_scale * 2.3 + vec3(0.37), 0.0).r;
	float shape = base * 0.62 + billow * 0.5 - 0.08;
	float lo = 1.0 - cov + layer * 0.12;
	float d = remap01(shape, lo, lo + 0.35);
	if (detailed && d > 0.0) {
		float det = textureLod(cloud_detail, p * cloud_detail_scale, 0.0).r;
		d = remap01(d, (1.0 - det) * 0.28, 1.0);
	}
	return d;
}

// Premultiplied colour + alpha of one cumulus layer seen along rd.
vec4 cumulus_layer(vec3 ro, vec3 rd, vec3 sun, float layer, bool detailed) {
	float h = cloud_height + layer * layer_spacing * float(max(cloud_layers - 1, 1));
	float t = (h - ro.y) / rd.y;
	vec2 xz = ro.xz + rd.xz * t;
	float d = cloud_thickness(xz, layer, detailed);
	if (d <= 0.0) {
		return vec4(0.0);
	}
	// March towards the sun inside the layer: how much cloud shades this point.
	vec2 sdir = normalize(sun.xz + vec2(1e-4));
	float od = 0.0;
	float step_len = 140.0;
	for (int i = 0; i < light_steps; i++) {
		float s = step_len * (float(i) + 1.0) * (1.0 + float(i) * 0.5);
		od += cloud_thickness(xz + sdir * s, layer, false) * (1.0 - float(i) / float(light_steps + 1));
	}
	od /= max(float(light_steps), 1.0) * 0.5;
	float lit = exp(-od * 2.2);
	// A sun high overhead lights everything from above; a low sun makes it directional.
	lit = mix(lit, 1.0, smoothstep(0.6, 1.0, sun.y) * 0.5);
	// Thick cores are darker from below, the top layers catch more light.
	// Seen from below, thick cores are shaded; the top layers catch more light.
	float under = mix(1.0, 0.3, pow(d, 0.7) * (1.0 - layer * 0.5) * (1.0 - smoothstep(0.1, 0.5, dot(rd, sun)) * 0.5));
	float ramp = smoothstep(0.08, 0.75, lit * under);
	vec3 c = mix(cloud_shade_color * mix(0.85, 1.1, layer), cloud_lit_color, ramp);
	c += cloud_warm_color * ramp * (1.0 - ramp) * 0.9;
	// Silver lining: thin edges glow when looking towards the sun.
	float mu = max(dot(rd, sun), 0.0);
	c += cloud_lit_color * pow(mu, 8.0) * (1.0 - d) * 2.2;
	c *= cloud_brightness;
	// Edges soften with distance so far clouds don't alias.
	float soft = mix(0.12, 0.45, clamp(t / 30000.0, 0.0, 1.0));
	float alpha = smoothstep(0.0, soft, d);
	return vec4(c * alpha, alpha);
}

vec4 cirrus(vec3 ro, vec3 rd, vec3 sun) {
	float t = (9000.0 - ro.y) / rd.y;
	vec2 q = (ro.xz + rd.xz * t + cloud_params.xy * 2.0) * 0.00004;
	// Wind-combed streaks: stretch the noise along one axis.
	float n = textureLod(cloud_shape, vec3(q.x, 0.5, q.y * 2.5), 0.0).r;
	float streak = textureLod(cloud_detail, vec3(q.x * 2.0, 0.2, q.y * 5.0), 0.0).r;
	float a = smoothstep(0.55, 0.85, n * 0.7 + streak * 0.45) * cirrus_amount;
	float mu = max(dot(rd, sun), 0.0);
	vec3 c = mix(vec3(0.9, 0.94, 1.0), cloud_lit_color + cloud_warm_color * 0.3, pow(mu, 4.0)) * cloud_brightness;
	return vec4(c * a, a);
}

vec3 sky_with_clouds(vec3 ro, vec3 rd, vec3 sun, bool detailed) {
	vec3 col = sky_gradient(rd, sun);
	if (rd.y < 0.01 || cloud_layers <= 0) {
		return col;
	}
	float horizon_fade = smoothstep(0.01, 0.12, rd.y);
	vec3 haze = col * 1.04;
	vec4 ci = cirrus(ro, rd, sun);
	col = col * (1.0 - ci.a * horizon_fade) + ci.rgb * horizon_fade;
	// Stack the layers bottom to top: seen from below, lower layers are in front.
	vec4 acc = vec4(0.0);
	for (int i = 0; i < cloud_layers; i++) {
		float layer = cloud_layers > 1 ? float(i) / float(cloud_layers - 1) : 0.0;
		vec4 l = cumulus_layer(ro, rd, sun, layer, detailed);
		acc.rgb += l.rgb * (1.0 - acc.a);
		acc.a += l.a * (1.0 - acc.a);
	}
	// Distant clouds dissolve into the horizon haze.
	acc.rgb = mix(haze * acc.a, acc.rgb, mix(0.35, 1.0, horizon_fade));
	acc *= smoothstep(0.01, 0.05, rd.y);
	return col * (1.0 - acc.a) + acc.rgb;
}

void sky() {
	vec3 sun = normalize(LIGHT0_DIRECTION);
	if (AT_CUBEMAP_PASS) {
		// Ambient and reflections: clouds without detail, and a softer, less saturated
		// colour so shadows turn cool but not icy blue.
		vec3 c = sky_with_clouds(POSITION, EYEDIR, sun, false);
		float luma = dot(c, vec3(0.3, 0.59, 0.11));
		COLOR = mix(vec3(luma) * vec3(1.02, 1.0, 0.97), c, 0.6);
	} else {
		vec3 clear = sky_gradient(EYEDIR, sun);
		vec3 c = sky_with_clouds(POSITION, EYEDIR, sun, true);
		// The disc only shows where no cloud covers it.
		float cover = clamp(1.0 - length(c - clear) * 2.0, 0.0, 1.0);
		float sd = dot(EYEDIR, sun);
		COLOR = c + sun_glow_color * 30.0 * smoothstep(sun_disc_size, sun_disc_size + 0.00012, sd) * cover;
	}
}
