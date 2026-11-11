shader_type sky;
// Небо карты: градиент, диск солнца или луны, процедурные облака со сдвигом по ветру,
// звёзды ночью. Всё из шума, без текстур.

uniform vec3 top_color = vec3(0.30, 0.45, 0.66);
uniform vec3 horizon_color = vec3(0.70, 0.74, 0.76);
uniform vec3 ground_color = vec3(0.25, 0.25, 0.22);
uniform vec3 cloud_color = vec3(0.95, 0.95, 0.95);
uniform vec3 cloud_shade = vec3(0.55, 0.58, 0.62);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform vec2 cloud_drift = vec2(0.002, 0.0);
uniform float cloud_seed = 0.0;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float sun_disk = 1.0;      // 0 — не рисовать диск (пасмурно)
uniform float moon = 0.0;          // 1 — диск луны вместо солнца

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));

	// Солнце или луна: диск + ореол.
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		vec3 lc = LIGHT0_COLOR * LIGHT0_ENERGY;
		float glow = pow(max(sd, 0.0), 6.0) * 0.18 + pow(max(sd, 0.0), 60.0) * 0.35;
		col += lc * glow * (1.0 - moon * 0.6) * mix(0.35, 1.0, sun_disk);
		float r = moon > 0.5 ? 0.9997 : 0.99965;
		float disk = smoothstep(r, r + 0.00012, sd) * sun_disk;
		col = mix(col, lc * (moon > 0.5 ? 1.6 : 6.0), disk);
	}

	// Облака: проекция на плоскость, рыхлый fbm.
	if (h > 0.0 && cloud_cover > 0.01) {
		vec2 uv = d.xz / (h + 0.09) * 0.55 + vec2(cloud_seed) + TIME * cloud_drift;
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		float n = fbm(uv, oct);
		float edge = 1.0 - cloud_cover;
		float c = smoothstep(edge - 0.08, edge + 0.22, n) * smoothstep(0.0, 0.14, h);
		// Подсветка с солнечной стороны: сдвиг выборки к свету.
		float lit = 1.0;
		if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {
			float n2 = fbm(uv + LIGHT0_DIRECTION.xz * 0.06, 4);
			lit = clamp(1.0 - (n2 - n) * 4.0, 0.4, 1.3);
		}
		vec3 cc = mix(cloud_shade, cloud_color, clamp(n * 1.4 - 0.2, 0.0, 1.0)) * lit;
		col = mix(col, cc, c * 0.92);
	}

	// Звёзды.
	if (stars > 0.0 && h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 g = d.xz / (h + 0.3) * 260.0;
		vec2 cell = floor(g);
		float s = hash12(cell);
		vec2 pos = fract(g) - 0.5 - (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.6;
		float star = step(0.985, s) * smoothstep(0.12, 0.0, length(pos)) * (0.5 + 0.5 * sin(TIME * 2.0 + s * 60.0));
		col += vec3(0.85, 0.9, 1.0) * star * stars * smoothstep(0.02, 0.2, h);
	}
	COLOR = col;
}
