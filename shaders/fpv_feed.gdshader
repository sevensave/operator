shader_type canvas_item;
// Аналоговая FPV-картинка: линза, зерно, сканлайны, хроматика, срыв кадра по качеству сигнала.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float signal_q = 1.0;     // 0..1
uniform float nolink = 0.0;       // 0..1 — сплошной «снег»
uniform float jam = 0.0;          // 0..1 — полосы глушилки
uniform float hit_flash = 0.0;    // вспышка при потере дрона
uniform float lens = 0.12;        // бочка линзы
uniform float grain_base = 0.025;
uniform float spectate = 0.0;     // режим наблюдения — мягче

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float bad = clamp(1.0 - signal_q, 0.0, 1.0);
	// Бочкообразное искажение линзы.
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	uv = 0.5 + c * (1.0 + lens * r2);

	// Срыв строк: горизонтальные сдвиги полос при слабом сигнале.
	float band = floor(uv.y * 48.0 + floor(t * 18.0) * 7.0);
	float tear = step(1.0 - pow(bad, 2.2) * 0.55 - jam * 0.25, hash(vec2(band, floor(t * 24.0))));
	uv.x += tear * (hash(vec2(band, t)) - 0.5) * 0.08 * (bad + jam);
	// Кадр «прыгает» по вертикали.
	float roll = step(0.985 - bad * 0.05, hash(vec2(floor(t * 8.0), 3.0))) * bad;
	bool outside = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
	if (roll > 0.0) uv.y = fract(uv.y + roll * 0.15);

	float ca = 0.0015 + bad * 0.006 + jam * 0.004;
	vec3 col;
	col.r = textureLod(screen_tex, uv + vec2(ca, 0.0), 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - vec2(ca, 0.0), 0.0).b;

	// Зерно и «снег».
	float n = hash(uv * vec2(1920.0, 1080.0) + fract(t * 61.0));
	float grain = grain_base + bad * bad * 0.45 + jam * 0.12;
	col += (n - 0.5) * grain;
	// Сканлайны.
	float scan = sin(uv.y * 900.0) * 0.5 + 0.5;
	col *= 1.0 - scan * (0.05 + bad * 0.08) * (1.0 - spectate * 0.7);
	// Потеря цвета при плохой связи.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), bad * 0.7);
	// Полный «снег».
	vec3 snow = vec3(hash(uv * 800.0 + t));
	col = mix(col, snow * 0.8, clamp(nolink, 0.0, 1.0));
	// Виньетка.
	col *= 1.0 - smoothstep(0.25, 0.75, r2 * 1.8) * 0.55;
	col = mix(col, vec3(1.0, 0.9, 0.8), hit_flash);
	// За краем линзы — чёрное.
	if (outside) col = vec3(0.0);
	COLOR = vec4(col, 1.0);
}
