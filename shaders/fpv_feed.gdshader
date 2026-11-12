shader_type canvas_item;
// Картинка дешёвой широкоугольной камеры дрона («bodycam») + аналоговый плохой сигнал.
// Линза: «рыбий глаз» с компенсацией — камера рендерит шире (match_view), а здесь центр
// возвращается к исходному масштабу (lens_s), края сжимаются (lens_k). Прицел в центре не смещается,
// метки OSD match_view пересчитывает той же функцией (lens_map). Дальше: падение резкости и хроматика
// к краям, смаз по угловой скорости, роллинг-шаттер и «желе», шум матрицы в тенях, ореол пересветов,
// блоки сжатия 8×8, бандинг, перешарп, капли/грязь на линзе, блик против солнца, узкий диапазон,
// холодноватый баланс. Эффекты плохого сигнала (срыв строк, снег, глушилка) — как раньше.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float signal_q = 1.0;     // 0..1
uniform float nolink = 0.0;       // 0..1 — сплошной «снег»
uniform float jam = 0.0;          // 0..1 — полосы глушилки
uniform float hit_flash = 0.0;    // вспышка при потере дрона
uniform float lens_k = 0.3;       // сила бочки
uniform float lens_s = 0.8;       // масштаб центра (компенсация расширенного FOV)
uniform float grain_base = 0.025;
uniform float spectate = 0.0;     // режим наблюдения — мягче
uniform float amount = 1.0;       // сила «камеры»: 0 — только сигнал, 0,5 — слабый фильтр, 1 — полный
uniform vec2 blur_vec = vec2(0.0);   // смаз от поворота камеры за кадр (в долях экрана)
uniform float roll_rate = 0.0;    // смаз вращения (радиан за кадр)
uniform float shutter = 0.0;      // роллинг-шаттер: наклон строк от рыскания
uniform float jello = 0.0;        // вибрация от газа
uniform float gain = 0.0;         // усиление матрицы (ночь/тени): шум
uniform float rain = 0.0;         // капли на линзе
uniform float dirt = 0.3;         // грязь на линзе
uniform vec3 sun_pos = vec3(0.5, 0.5, 0.0);   // xy — солнце на экране (uv), z — видимость 0..1
uniform float compress = 0.2;     // блочность сжатия

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 tap(vec2 uv, float lod) {
	return textureLod(screen_tex, uv, lod).rgb;
}

void fragment() {
	vec2 uv0 = SCREEN_UV;
	float t = TIME;
	float bad = clamp(1.0 - signal_q, 0.0, 1.0);
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 asp = vec2(aspect, 1.0);

	// Роллинг-шаттер: строки читаются сверху вниз — при рыскании кадр перекашивается; «желе» от винтов.
	vec2 uv = uv0;
	uv.x += shutter * (uv.y - 0.5) * amount;
	uv.y += sin(uv.y * 38.0 + t * 97.0) * jello * 0.0012 * amount;
	uv.x += sin(uv.y * 23.0 - t * 131.0) * jello * 0.0009 * amount;

	// Линза: центр в исходном масштабе, к краям — бочка.
	vec2 cn = (uv - 0.5) * asp;
	float r2 = dot(cn, cn);
	vec2 sc = cn * lens_s * (1.0 + lens_k * r2);
	uv = 0.5 + sc / asp;

	// Срыв строк: горизонтальные сдвиги полос при слабом сигнале.
	float band = floor(uv.y * 48.0 + floor(t * 18.0) * 7.0);
	float tear = step(1.0 - pow(bad, 2.2) * 0.55 - jam * 0.25, hash(vec2(band, floor(t * 24.0))));
	uv.x += tear * (hash(vec2(band, t)) - 0.5) * 0.08 * (bad + jam);
	float roll = step(0.985 - bad * 0.05, hash(vec2(floor(t * 8.0), 3.0))) * bad;
	bool outside = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
	if (roll > 0.0) uv.y = fract(uv.y + roll * 0.15);

	// Капли на линзе (дождь): преломляют кусочек кадра, края капель темнее.
	vec2 drop_off = vec2(0.0);
	float drop_edge = 0.0;
	if (rain > 0.0) {
		vec2 g = uv0 * vec2(aspect, 1.0) * 6.0;
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(cell + floor(t * 0.08) * 3.1);
		vec2 c = (vec2(hash(cell + 1.7), hash(cell + 4.3)) - 0.5) * 0.6;
		float rad = 0.06 + 0.16 * hash(cell + 9.1);
		float d = length(f - c);
		float on = step(1.0 - rain * 0.28, h);
		float m = (1.0 - smoothstep(rad * 0.8, rad, d)) * on;
		drop_off = (f - c) * m * 0.025;
		drop_edge = smoothstep(rad * 0.6, rad, d) * m;
	}
	uv += drop_off * amount;

	// Резкость падает к краям, к краям растёт хроматика (радиально).
	float edge = clamp(r2 * 1.6, 0.0, 1.0);
	float lod = edge * 1.1 * amount + rain * 0.6 * length(drop_off) * 40.0;
	vec2 cdir = (uv - 0.5);
	float ca = (0.0015 + bad * 0.006 + jam * 0.004) + edge * 0.006 * amount;
	vec3 col;
	col.r = textureLod(screen_tex, uv + cdir * ca * 1.0 + vec2(ca * 0.3, 0.0), lod).r;
	col.g = textureLod(screen_tex, uv, lod).g;
	col.b = textureLod(screen_tex, uv - cdir * ca * 1.0 - vec2(ca * 0.3, 0.0), lod).b;

	// Смаз по угловой скорости: несколько выборок вдоль сдвига кадра и по кругу при вращении.
	float bl = length(blur_vec) + abs(roll_rate) * 0.5;
	if (bl > 0.0005 && amount > 0.0) {
		vec3 acc = col;
		for (int i = 1; i <= 5; i++) {
			float k = (float(i) / 5.0 - 0.5);
			vec2 rot = vec2(-cdir.y, cdir.x) * roll_rate * k;
			acc += tap(uv + blur_vec * k * amount + rot * amount, lod);
		}
		col = acc / 6.0;
	}

	if (amount > 0.0) {
		// Перешарп (дешёвый сенсор): нерезкая маска от размытого мипа.
		vec3 blur1 = tap(uv, lod + 1.5);
		col += (col - blur1) * 0.55 * amount;
		// Пересвет: яркое расплывается ореолом.
		vec3 bloom = tap(uv, 4.5);
		col += max(bloom - 0.62, 0.0) * 0.7 * amount;
		// Блоки сжатия 8×8: в блоке детали огрубляются к среднему (сильнее при движении и плохой связи).
		vec2 blk = (floor(uv0 / (px * 8.0)) + 0.5) * px * 8.0;
		vec3 bavg = tap(0.5 + ((blk - 0.5) * asp * lens_s * (1.0 + lens_k * dot((blk - 0.5) * asp, (blk - 0.5) * asp))) / asp, 3.0);
		float cmp = clamp(compress + bad * 0.6 + bl * 12.0, 0.0, 1.0) * amount;
		col = mix(col, bavg + floor((col - bavg) * 10.0 + 0.5) / 10.0, cmp * 0.55);
		// Узкий диапазон: подъём чёрного, мягкое «плечо», холодноватый баланс.
		float lum0 = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum0), 0.08 * amount);
		col = col * (1.0 - 0.06 * amount) + 0.025 * amount;
		col = mix(col, 1.0 - exp(-col * 1.55) * 1.02, 0.5 * amount);
		col *= mix(vec3(1.0), vec3(0.96, 1.0, 1.05), amount);
		// Бандинг: квантование тонов (заметно в небе и тенях).
		col = mix(col, floor(col * 48.0 + 0.5) / 48.0, 0.7 * amount);
		// Блик против солнца: ореол, призраки по линии солнце—центр, вуаль.
		if (sun_pos.z > 0.0) {
			vec2 sp = sun_pos.xy;
			vec2 dv = (uv0 - sp) * asp;
			float glare = exp(-dot(dv, dv) * 18.0) * 0.35 + exp(-abs(dv.y) * 60.0) * exp(-abs(dv.x) * 3.0) * 0.12;
			vec2 axis = (vec2(0.5) - sp);
			for (int g = 1; g <= 3; g++) {
				vec2 gp = sp + axis * (0.6 + float(g) * 0.45);
				vec2 gd = (uv0 - gp) * asp;
				float rr = 0.02 + float(g) * 0.025;
				glare += (1.0 - smoothstep(rr * 0.7, rr, length(gd))) * 0.06 * (1.0 - float(g) * 0.2);
			}
			col += vec3(1.0, 0.92, 0.8) * glare * sun_pos.z * amount;
			col = mix(col, vec3(0.8, 0.82, 0.85), 0.05 * sun_pos.z * amount);
		}
		// Грязь на линзе: пятна дымки, заметные против света.
		float smear = smoothstep(0.55, 0.85, vnoise(uv0 * vec2(aspect, 1.0) * 3.0 + 7.0)) * dirt;
		col = mix(col, col * 0.85 + vec3(0.06), smear * (0.3 + sun_pos.z * 0.7) * amount);
		col *= 1.0 - drop_edge * 0.12;
	}

	// Зерно и «снег»; шум матрицы сильнее в тенях и при усилении.
	float n = hash(uv * vec2(1920.0, 1080.0) + fract(t * 61.0));
	float lum1 = dot(col, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(0.05, 0.5, lum1);
	float grain = grain_base + bad * bad * 0.45 + jam * 0.12 + (gain * 0.09 + 0.03) * dark * amount;
	vec2 cn2 = vec2(hash(uv * 911.0 + t), hash(uv * 577.0 - t)) - 0.5;
	col += (n - 0.5) * grain;
	col.rb += cn2 * grain * 0.5 * amount;   // цветной шум матрицы
	// Сканлайны.
	float scan = sin(uv.y * 900.0) * 0.5 + 0.5;
	col *= 1.0 - scan * (0.05 + bad * 0.08) * (1.0 - spectate * 0.7) * (1.0 - amount * 0.6);
	// Потеря цвета при плохой связи.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), bad * 0.7);
	// Полный «снег».
	vec3 snow = vec3(hash(uv * 800.0 + t));
	col = mix(col, snow * 0.8, clamp(nolink, 0.0, 1.0));
	// Виньетка (сильнее у широкоугольной линзы).
	col *= 1.0 - smoothstep(0.3, 0.85, r2 * (1.2 + 0.3 * amount)) * (0.55 - 0.1 * amount);
	col = mix(col, vec3(1.0, 0.9, 0.8), hit_flash);
	// За краем линзы — чёрное.
	if (outside) col = vec3(0.0);
	COLOR = vec4(col, 1.0);
}
