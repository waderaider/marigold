shader_type sky;
// MarigoldSky procedural sky: gradient + sun/moon discs + stars + 2-octave
// value-noise clouds. Quest-3-perf: no volumetrics, cheap hash noise only.

uniform vec4 sky_top_color : source_color = vec4(0.25, 0.12, 0.45, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(1.0, 0.45, 0.15, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.20, 0.08, 0.15, 1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float night_factor = 0.0; // 0 = full day, 1 = full night
uniform float cloud_cover = 0.1; // 0..1 cloud threshold
uniform float cloud_drift = 0.0; // animated from GDScript (time * wind)
uniform float dim_factor = 1.0; // weather dimming multiplier

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float star_field(vec3 dir) {
	vec3 p = dir * 140.0;
	vec3 id = floor(p);
	float h = hash13(id);
	float star = step(0.992, h);
	vec3 f = fract(p) - 0.5;
	float m = smoothstep(0.28, 0.0, length(f)) * star;
	return m * (0.35 + 0.65 * hash13(id + 7.7));
}

float cloud_field(vec3 dir) {
	if (dir.y < 0.015) {
		return 0.0;
	}
	vec2 cuv = dir.xz / (dir.y + 0.28);
	cuv.x *= 0.55; // stretch clouds horizontally
	vec2 q = cuv * 1.7 + vec2(cloud_drift, cloud_drift * 0.35);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 5.2) * 0.35;
	float thresh = 1.0 - cloud_cover * 0.92;
	return smoothstep(thresh, thresh + 0.38, n);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;

	// Base gradient.
	vec3 col = mix(sky_horizon_color.rgb, sky_top_color.rgb,
			pow(clamp(up, 0.0, 1.0), 0.55));
	if (up < 0.0) {
		col = mix(sky_horizon_color.rgb, ground_horizon_color.rgb,
				clamp(-up * 4.0, 0.0, 1.0));
	}

	// Sun disc + glow.
	float sdot = dot(dir, normalize(sun_dir));
	float disc = smoothstep(0.99935, 0.99965, sdot);
	float glow = pow(clamp(sdot, 0.0, 1.0), 20.0) * 0.45
			+ pow(clamp(sdot, 0.0, 1.0), 160.0) * 0.9;
	col += sun_color.rgb * (disc * 3.0 + glow);

	// Moon disc + halo (gated by night).
	float mdot = dot(dir, normalize(moon_dir));
	float moon = smoothstep(0.99955, 0.99985, mdot) * night_factor;
	float moon_halo = pow(clamp(mdot, 0.0, 1.0), 600.0) * 0.6 * night_factor;
	col += vec3(0.85, 0.9, 1.0) * (moon * 1.6 + moon_halo);

	// Stars (gated by night).
	col += vec3(0.9, 0.93, 1.0) * star_field(dir) * night_factor
			* smoothstep(0.0, 0.25, up);

	// Clouds.
	float clouds = cloud_field(dir);
	float day_lit = clamp(sdot * 0.5 + 0.5, 0.0, 1.0);
	vec3 cloud_lit = mix(vec3(0.10, 0.08, 0.14), sun_color.rgb * 1.15, day_lit);
	cloud_lit = mix(cloud_lit, vec3(0.05, 0.05, 0.10), night_factor * 0.85);
	vec3 cloud_dark = cloud_lit * 0.45;
	float shade = vnoise(dir.xz / max(dir.y + 0.28, 0.05) * 3.4
			+ vec2(cloud_drift * 1.7, 0.0));
	vec3 cloud_col = mix(cloud_dark, cloud_lit, shade);
	col = mix(col, cloud_col, clouds * 0.92);

	col *= dim_factor;
	COLOR = col;
}
