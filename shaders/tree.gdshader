shader_type spatial;
render_mode cull_disabled;
// Деревья в MultiMesh (FoliageBuilder). part: 0 — кора (ствол, ветви), 1 — карточки веток/листвы
// с альфой, 2 — дальний низкополигональный силуэт. INSTANCE_CUSTOM — цвет кроны (rgb) и фаза (a).
// LOD: ближние части дальше lod_dist схлопываются, силуэт — ближе; в полосе перехода — дизеринг.
// Расстояние — от global view_center (камера), одинаково для основного прохода и теней.
// Покачивание ограничено 0,12 радиуса экземпляра: крона не выходит из цилиндра коллизии.

global uniform vec3 view_center;
uniform vec3 trunk_color = vec3(0.28, 0.20, 0.14);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway = 0.25;        // амплитуда в метрах у верхушки
uniform int part = 0;
uniform float lod_dist = 120.0;   // < 0 — без LOD (виден только силуэт)
uniform float snow = 0.0;
uniform vec3 snow_color = vec3(0.86, 0.88, 0.92);
uniform sampler2D card_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D bark_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec4 crown;
varying float fade;
varying float dist;
varying vec3 wnrm;

const float BAND = 18.0;

void vertex() {
	crown = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	dist = length(origin - view_center);
	fade = 1.0;
	if (lod_dist > 0.0) {
		float t = clamp((dist - (lod_dist - BAND)) / (2.0 * BAND), 0.0, 1.0);   // 0 — близко, 1 — далеко
		fade = part == 2 ? t : 1.0 - t;
		if (fade <= 0.0) VERTEX = vec3(0.0);
	}
	float k = clamp(VERTEX.y, 0.0, 1.0);
	k *= k;
	float ph = INSTANCE_CUSTOM.a * 6.2831;
	float s = sin(TIME * 1.3 + ph) * 0.7 + sin(TIME * 2.9 + ph * 1.7) * 0.3;
	float rs = length(MODEL_MATRIX[0].xyz);
	float amp = min(sway, rs * 0.12);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (0.6 + 0.4 * s) * amp * k;
	off += vec3(-wind_dir.y, 0.0, wind_dir.x) * sin(TIME * 2.1 + ph * 2.3) * amp * 0.25 * k;
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * off;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	if (fade < 1.0 && dither(FRAGCOORD.xy + float(int(TIME * 60.0) % 4) * 1.7) > fade) discard;
	float up = clamp(wnrm.y, 0.0, 1.0);
	if (part == 0) {
		vec3 b = texture(bark_alb, UV).rgb;
		ALBEDO = trunk_color * b * 2.0;
		NORMAL_MAP = texture(bark_nrm, UV).rgb;
		NORMAL_MAP_DEPTH = 1.2;
		ROUGHNESS = 0.9;
		ALBEDO = mix(ALBEDO, snow_color, snow * smoothstep(0.55, 0.85, up) * 0.8);
	} else if (part == 1) {
		vec4 t = texture(card_tex, UV);
		vec3 base = crown.rgb;
		ALBEDO = base * t.rgb * 2.0 * COLOR.rgb;
		ALPHA = t.a;
		// Вдали мипы размывают альфу — порог ниже, крона не «редеет».
		ALPHA_SCISSOR_THRESHOLD = mix(0.5, 0.22, smoothstep(10.0, 90.0, dist));
		ROUGHNESS = 0.82;
		SPECULAR = 0.3;
		BACKLIGHT = base * 0.6;
		ALBEDO = mix(ALBEDO, snow_color, snow * smoothstep(0.35, 0.8, up) * 0.75);
	} else {
		vec3 c = mix(trunk_color, crown.rgb, COLOR.a) * COLOR.rgb;
		ALBEDO = mix(c, snow_color, snow * COLOR.a * smoothstep(0.4, 0.9, up) * 0.6);
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
		BACKLIGHT = vec3(0.12) * COLOR.a;
	}
}
