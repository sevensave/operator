shader_type spatial;
// Руины и укрытия: слой библиотеки поверхностей по коду в альфе вершинного цвета
// (0 бетон, 1 кирпич, 2 штукатурка, 3 ржавый металл, 4 дерево/кора, 5 грунт, 6 асфальт).
// Фактура — в мировых координатах; UV — локальные метры грани, UV2 — её размер: сколы у краёв.
// CUSTOM0.x — уровень земли (в координатах сетки): грязь и сырость у основания.
// Потёки под верхом стен, мох (лето/осень) или снег (зима) на горизонтальных гранях.

uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tiles[7];
uniform float moss = 1.0;
uniform float snow = 0.0;
uniform float wet = 0.0;

varying vec3 wp;
varying vec3 wn;
varying float above;
varying vec2 fsize;
varying float layer;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	above = VERTEX.y - CUSTOM0.x;
	fsize = UV2;
	layer = floor(COLOR.a * 8.0);
}

void fragment() {
	int s = clamp(int(layer + 0.01), 0, 6);
	// Фактура — в мировых координатах по преобладающей оси (стыки сегментов стены без швов).
	vec3 an = abs(wn);
	vec2 wuv = an.y > max(an.x, an.z) ? wp.xz : (an.x > an.z ? vec2(wp.z, -wp.y) : vec2(wp.x, -wp.y));
	vec2 uv = wuv * tiles[s];
	vec4 a = texture(alb_arr, vec3(uv, float(s)));
	vec4 o = texture(orm_arr, vec3(uv, float(s)));
	vec3 nm = texture(nrm_arr, vec3(uv, float(s))).rgb;
	float big = texture(noise_tex, wp.xz * 0.05 + wp.y * 0.03).r;
	float fine = texture(noise_tex, (wp.xz + wp.yy) * 0.6).r;
	// Абсолютные поверхности окрашены относительно серого 0,55; кора и грунт — относительные.
	vec3 c = (s == 4 || s == 5) ? COLOR.rgb * a.rgb * 2.0 : a.rgb * COLOR.rgb / 0.55;
	c *= 0.85 + big * 0.3;
	float rough = o.g;
	// Сколы рёбер (верх стен, края плит): у края грани светлее и шершавее (свежий скол бетона/кирпича), зубчато по шуму.
	// Только верхняя кромка: вертикальные края сегментов стены — внутренние стыки, их не трогаем.
	float e = an.y > 0.5 ? min(min(UV.x, fsize.x - UV.x), min(UV.y, fsize.y - UV.y)) : UV.y;
	float chip = (1.0 - smoothstep(0.02, 0.09 + fine * 0.1, e)) * step(0.4, fine) * float(s <= 2);
	c = mix(c, c * 1.35 + vec3(0.04), chip * 0.7);
	rough = mix(rough, 0.95, chip);
	nm = mix(nm, vec3(0.5 + (fine - 0.5) * 0.6, 0.5, 1.0), chip * 0.5);
	float vert = 1.0 - abs(wn.y);
	// Потёки: тёмные вертикальные полосы под верхней кромкой стены.
	float streak = texture(noise_tex, vec2((wp.x + wp.z) * 0.9, wp.y * 0.05)).r;
	float from_top = UV.y;   // 0 — верх боковой грани
	float run = (1.0 - smoothstep(0.0, 2.5 + streak * 2.0, from_top)) * smoothstep(0.5, 0.75, streak) * vert;
	c *= 1.0 - run * 0.35;
	// Грязь и сырость у земли.
	float grime = (1.0 - smoothstep(0.0, 1.2 + big * 1.2, above)) * vert;
	c = mix(c, c * vec3(0.55, 0.5, 0.45), grime * 0.7);
	rough = mix(rough, 0.95, grime * 0.5);
	// Мох — на верхних гранях и в низу северных стен, снег — на верхних гранях.
	float up = clamp(wn.y, 0.0, 1.0);
	float mz = moss * (smoothstep(0.6, 0.9, up) * smoothstep(0.45, 0.65, big) + grime * smoothstep(0.55, 0.7, fine) * 0.6) * float(s != 3);
	c = mix(c, vec3(0.13, 0.17, 0.07) * (0.7 + fine * 0.6), clamp(mz, 0.0, 0.85));
	float sn = snow * smoothstep(0.65, 0.9, up);
	c = mix(c, vec3(0.86, 0.88, 0.92), sn * 0.9);
	// Мокрое в дождь: темнее, глаже.
	c *= 1.0 - wet * 0.3 * (1.0 - float(s == 3));
	rough = mix(rough, rough * 0.5, wet);
	ALBEDO = c;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = rough;
	METALLIC = o.b * (1.0 - sn);
	AO = o.r;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = 0.35;
}
