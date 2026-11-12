shader_type sky;
// Небо карты: градиент с рассеянием у горизонта (дымка ярче к солнцу), диск солнца или луны,
// объёмные облака (несколько срезов слоя с затенением к свету), звёзды ночью. Всё из шума.

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
uniform float haze = 0.5;          // сила рассеяния у горизонта и вокруг солнца
uniform float sky_energy = 1.0;    // общая яркость неба (соотношение с солнцем)
uniform int cloud_steps = 6;       // срезов облачного слоя (качество)

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

// Плотность облака в точке слоя: y01 — 0 у основания, 1 у верхней кромки.
// Кромки слоя «съедают» плотность — получаются округлые клубы, а не плоская плёнка.
float cloud_density(vec2 p, float y01, int oct) {
	float n = fbm(p + vec2(y01 * 0.35, -y01 * 0.2), oct);
	float shape = clamp(4.0 * y01 * (1.0 - y01), 0.0, 1.0);
	float edge = 1.0 - cloud_cover;
	float th = edge + (1.0 - shape) * 0.22 - 0.08;
	// Сплошная облачность: при покрытии > 0,75 слой затягивает всё небо, остаётся фактура.
	float deck = clamp((cloud_cover - 0.75) * 4.0, 0.0, 1.0) * (0.35 + 0.4 * n);
	return clamp(max((n - th) * 4.5, deck), 0.0, 1.0);
}

// Фазовая функция Хеньи — Гринштейна: вперёд рассеивающая дымка вокруг солнца.
float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float hp = clamp(h, 0.0, 1.0);
	// Небо темнее и насыщеннее к зениту, у горизонта — светлая полоса воздушной толщи.
	vec3 col = mix(horizon_color, top_color, 1.0 - pow(1.0 - hp, 5.0));
	col = mix(col, horizon_color * 1.08, exp(-hp * 40.0) * 0.6);
	vec3 lc = vec3(0.0);
	float mu = 0.0;
	if (LIGHT0_ENABLED) {
		lc = LIGHT0_COLOR * LIGHT0_ENERGY;
		mu = dot(d, LIGHT0_DIRECTION);
		// Рассеяние: широкое (Рэлей ≈ подсветка всей половины неба к солнцу) и узкое (Ми — ореол).
		float air = exp(-hp * 6.0);
		float wide = (0.5 + 0.5 * mu) * air * 0.25;
		float mie = hg(mu, 0.76) * (0.35 + 0.65 * air);
		col += lc * haze * (wide + mie * 0.55) * (1.0 - moon * 0.75);
		col += lc * (pow(max(mu, 0.0), 60.0) * 0.25) * mix(0.3, 1.0, sun_disk) * (1.0 - moon * 0.6);
		float r = moon > 0.5 ? 0.9997 : 0.99965;
		float disk = smoothstep(r, r + 0.00012, mu) * sun_disk * smoothstep(-0.01, 0.01, h);
		col = mix(col, lc * (moon > 0.5 ? 1.6 : 8.0), disk);
	}
	col *= sky_energy;

	// Объёмные облака: слой между высотами 1 и 1,7 (в условных единицах), несколько срезов.
	if (h > 0.0 && cloud_cover > 0.01) {
		int steps = AT_CUBEMAP_PASS ? 3 : cloud_steps;
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		vec2 drift = vec2(cloud_seed) + TIME * cloud_drift;
		float inv = 1.0 / (h + 0.09);
		vec2 sun2 = LIGHT0_ENABLED ? LIGHT0_DIRECTION.xz : vec2(0.0);
		float trans = 1.0;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < steps; i++) {
			float y01 = (float(i) + 0.5) / float(steps);
			float t = (1.0 + y01 * 0.7) * inv;
			vec2 p = d.xz * t * 0.55 + drift;
			float den = cloud_density(p, y01, oct);
			if (den <= 0.001) continue;
			// Затенение к свету: две пробы вверх-к-солнцу.
			float ld = 0.0;
			if (LIGHT0_ENABLED) {
				ld += cloud_density(p + sun2 * 0.05, min(y01 + 0.2, 1.0), 3);
				ld += cloud_density(p + sun2 * 0.12, min(y01 + 0.45, 1.0), 2) * 0.7;
			}
			float lit = exp(-ld * 1.6) * (0.55 + 0.45 * y01);
			lit = mix(lit, 0.55 + 0.2 * den, clamp((cloud_cover - 0.75) * 4.0, 0.0, 1.0) * 0.7);   // сплошная облачность — ровный серый
			float powder = 1.0 - exp(-den * 2.0);
			vec3 c = mix(cloud_shade, cloud_color, lit) * sky_energy;
			c += lc * hg(mu, 0.55) * lit * powder * 0.5 * (1.0 - moon * 0.7);
			float a = 1.0 - exp(-den * 2.4 * 6.0 / float(steps));
			acc += trans * a * c;
			trans *= 1.0 - a;
			if (trans < 0.02) break;
		}
		// Далёкие облака тонут в дымке горизонта.
		float far = smoothstep(0.0, 0.16, h);
		float cov = (1.0 - trans) * far;
		vec3 cc = acc / max(1.0 - trans, 1e-3);
		cc = mix(horizon_color * sky_energy, cc, smoothstep(0.0, 0.35, h) * 0.6 + 0.4);
		col = mix(col, cc, cov * 0.96);
	}

	// Земля под горизонтом (дальше дальней земли) — цвет дымки.
	col = mix(col, ground_color * sky_energy, smoothstep(0.0, -0.12, h));

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
