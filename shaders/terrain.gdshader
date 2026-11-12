shader_type spatial;
// Земля карты: послойный материал из библиотеки поверхностей (SurfaceLib, массивы текстур:
// 0 трава, 1 сухая трава, 2 грунт, 3 грязь, 4 гравий, 5 скала, 6 снег). Слои смешиваются по высоте
// фактуры (height-blend), веса — от склона, высоты, маски троп (COLOR.r) и макро-шума 30–300 м.
// Скала на склонах — трипланарно. Анти-тайлинг: два масштаба UV с поворотом + макро-вариация.
// Вблизи — детальные нормали. В дождь — мокрое и лужи на тропах, зимой — снег.
// far_mode — дальняя земля за картой: тот же цвет без выборок фактур (стыка по тону нет).
// Геометрия не смещается: всё только во фрагменте.

uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a = vec3(0.20, 0.27, 0.10);
uniform vec3 grass_b = vec3(0.33, 0.34, 0.15);
uniform vec3 dirt = vec3(0.30, 0.24, 0.17);
uniform vec3 rock = vec3(0.38, 0.36, 0.34);
uniform vec3 snow = vec3(0.80, 0.82, 0.84);
uniform float snow_lo = 95.0;
uniform float snow_hi = 125.0;
uniform float wetness = 0.0;      // 0..1 — дождь: темнее, глаже, лужи
uniform float snow_cover = 0.0;   // 0..1 — снегопад: снег и на склонах положе
uniform bool lite = false;        // низкое качество: один масштаб, без трипланара и деталей
uniform bool far_mode = false;
uniform vec4 tiles = vec4(0.5, 0.5, 1.0, 0.25);   // 1/метры: трава, грунт, гравий, скала

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Нормаль из карты (горизонтальная проекция): возмущение мировой нормали.
vec3 hn(vec4 t) {
	vec2 d = t.xy * 2.0 - 1.0;
	return vec3(d.x, 0.0, -d.y);
}

void fragment() {
	vec3 n = normalize(world_n);
	vec3 p = world_pos;
	float dist = length(p - CAMERA_POSITION_WORLD);
	// Макро-вариация: 300 м (поля), 60 м (пятна), 25 м (мелкие пятна).
	float m300 = texture(macro_noise, p.xz * 0.0021).r;
	float m60 = texture(macro_noise, p.xz * 0.011 + 0.37).r;
	float m25 = texture(macro_noise, p.xz * 0.027 + 0.71).r;
	float slope = 1.0 - n.y;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, m300));
	grass *= 0.88 + m60 * 0.24;
	vec3 dry = vec3(grass_b.r * 1.3, grass_b.g * 1.12, grass_b.b * 0.8);
	float path = COLOR.r;

	// Веса слоёв до учёта высоты фактуры.
	float sn_h = smoothstep(snow_lo, snow_hi, p.y + (m60 - 0.5) * 24.0);
	float w_dry = smoothstep(0.55, 0.75, m60 * 0.7 + m300 * 0.5) * 0.9;
	float w_soil = smoothstep(0.3, 0.6, path) + smoothstep(0.72, 0.8, m25) * 0.6 + smoothstep(0.25, 0.35, slope) * 0.5;
	float w_mud = smoothstep(0.55, 0.75, path) * smoothstep(0.35, 0.6, m25 + wetness * 0.3);
	float w_gravel = (1.0 - max(sn_h, snow_cover)) * smoothstep(0.2, 0.3, slope) * (1.0 - smoothstep(0.25, 0.35, slope)) * 0.8 + smoothstep(0.68, 0.72, path) * (1.0 - smoothstep(0.5, 0.6, m25)) * 0.6;
	float w_rock = smoothstep(0.19, 0.29, slope + (m25 - 0.5) * 0.08);
	float w_snow = max(sn_h, snow_cover) * (1.0 - smoothstep(0.25, 0.5 + snow_cover * 0.15, slope)) * (1.0 - w_mud * 0.6);

	if (far_mode) {
		vec3 c = mix(grass, dry, w_dry * 0.6);
		c = mix(c, snow, w_snow);
		ALBEDO = c * (0.9 + m25 * 0.2);
		ROUGHNESS = 1.0;
		SPECULAR = 0.2;
	} else {

	vec2 uvg = p.xz * tiles.x;
	vec2 uvs = p.xz * tiles.y;
	vec2 uvr = p.xz * tiles.z;
	// Анти-тайлинг травы: второй масштаб с поворотом, смесь по макро-шуму.
	vec2 uvg2 = rot(p.xz, 0.6) * tiles.x * 0.37;
	float mixk = lite ? 0.0 : smoothstep(0.35, 0.65, m25);

	vec4 ga = texture(alb_arr, vec3(uvg, 0.0));
	vec4 go = texture(orm_arr, vec3(uvg, 0.0));
	vec4 gn = texture(nrm_arr, vec3(uvg, 0.0));
	if (!lite) {
		ga = mix(ga, texture(alb_arr, vec3(uvg2, 0.0)), mixk);
		go = mix(go, texture(orm_arr, vec3(uvg2, 0.0)), mixk);
		gn = mix(gn, texture(nrm_arr, vec3(uvg2, 0.0)), mixk);
	}
	// Слои: albedo (оттенок × фактура × 2), orm (a — высота), нормаль.
	vec3 acc_c = vec3(0.0);
	vec4 acc_o = vec4(0.0);
	vec3 acc_n = vec3(0.0);
	float best = -1.0;
	float hgts[7];
	float ws[7];
	ws[0] = 1.0;
	ws[1] = w_dry;
	ws[2] = w_soil;
	ws[3] = w_mud;
	ws[4] = w_gravel;
	ws[5] = w_rock;
	ws[6] = w_snow;
	// Под снегом остальное проглядывает лишь кочками.
	for (int i = 0; i < 5; i++) ws[i] *= 1.0 - w_snow * 0.75;
	// Сначала высоты (из ORM.a) — для height-blend.
	vec4 o1 = vec4(0.0), o2 = vec4(0.0), o3 = vec4(0.0), o4 = vec4(0.0), o6 = vec4(0.0);
	hgts[0] = go.a;
	if (ws[1] > 0.01) { o1 = texture(orm_arr, vec3(uvg * 0.9 + 0.31, 1.0)); }
	if (ws[2] > 0.01) { o2 = texture(orm_arr, vec3(uvs, 2.0)); }
	if (ws[3] > 0.01) { o3 = texture(orm_arr, vec3(uvs * 0.8, 3.0)); }
	if (ws[4] > 0.01) { o4 = texture(orm_arr, vec3(uvr, 4.0)); }
	if (ws[6] > 0.01) { o6 = texture(orm_arr, vec3(uvs * 0.5, 6.0)); }
	// Скала: трипланарно на склонах.
	vec3 tw = pow(abs(n), vec3(4.0));
	tw /= tw.x + tw.y + tw.z;
	vec4 ra = vec4(0.0), ro = vec4(0.0);
	vec3 rn = vec3(0.0);
	if (ws[5] > 0.01) {
		vec3 q = p * tiles.w;
		if (lite) {
			ra = texture(alb_arr, vec3(q.xz, 5.0));
			ro = texture(orm_arr, vec3(q.xz, 5.0));
			rn = hn(texture(nrm_arr, vec3(q.xz, 5.0)));
		} else {
			vec4 ax = texture(alb_arr, vec3(q.zy, 5.0)), ay = texture(alb_arr, vec3(q.xz, 5.0)), az = texture(alb_arr, vec3(q.xy, 5.0));
			vec4 ox = texture(orm_arr, vec3(q.zy, 5.0)), oy = texture(orm_arr, vec3(q.xz, 5.0)), oz = texture(orm_arr, vec3(q.xy, 5.0));
			vec2 nx = texture(nrm_arr, vec3(q.zy, 5.0)).xy * 2.0 - 1.0;
			vec2 ny = texture(nrm_arr, vec3(q.xz, 5.0)).xy * 2.0 - 1.0;
			vec2 nz = texture(nrm_arr, vec3(q.xy, 5.0)).xy * 2.0 - 1.0;
			ra = ax * tw.x + ay * tw.y + az * tw.z;
			ro = ox * tw.x + oy * tw.y + oz * tw.z;
			rn = vec3(0.0, -nx.y, nx.x) * tw.x + vec3(ny.x, 0.0, -ny.y) * tw.y + vec3(nz.x, -nz.y, 0.0) * tw.z;
		}
	}
	hgts[1] = o1.a;
	hgts[2] = o2.a;
	hgts[3] = o3.a * 0.7;
	hgts[4] = o4.a;
	hgts[5] = ro.a;
	hgts[6] = o6.a * 0.3 + 0.75 + w_snow * 0.3;
	// Height-blend: побеждает слой с бо́льшим (вес + высота), переход шириной 0,2.
	float top = -10.0;
	for (int i = 0; i < 7; i++) {
		if (ws[i] > 0.001) top = max(top, ws[i] * 1.6 + hgts[i]);
	}
	float wsum = 0.0;
	float fw[7];
	for (int i = 0; i < 7; i++) {
		fw[i] = ws[i] > 0.001 ? max(ws[i] * 1.6 + hgts[i] - top + 0.2, 0.0) : 0.0;
		wsum += fw[i];
	}
	for (int i = 0; i < 7; i++) fw[i] /= max(wsum, 1e-4);

	vec3 c = grass * ga.rgb * 2.0 * fw[0];
	vec4 o = go * fw[0];
	vec3 dn = hn(gn) * fw[0];
	if (fw[1] > 0.0) {
		vec2 uv = uvg * 0.9 + 0.31;
		c += dry * texture(alb_arr, vec3(uv, 1.0)).rgb * 2.0 * fw[1];
		o += o1 * fw[1];
		dn += hn(texture(nrm_arr, vec3(uv, 1.0))) * fw[1];
	}
	if (fw[2] > 0.0) {
		c += dirt * texture(alb_arr, vec3(uvs, 2.0)).rgb * 2.0 * fw[2];
		o += o2 * fw[2];
		dn += hn(texture(nrm_arr, vec3(uvs, 2.0))) * fw[2];
	}
	if (fw[3] > 0.0) {
		c += dirt * 0.75 * texture(alb_arr, vec3(uvs * 0.8, 3.0)).rgb * 2.0 * fw[3];
		o += o3 * fw[3];
		dn += hn(texture(nrm_arr, vec3(uvs * 0.8, 3.0))) * fw[3];
	}
	if (fw[4] > 0.0) {
		c += mix(rock, dirt, 0.3) * 1.1 * texture(alb_arr, vec3(uvr, 4.0)).rgb * 2.0 * fw[4];
		o += o4 * fw[4];
		dn += hn(texture(nrm_arr, vec3(uvr, 4.0))) * fw[4];
	}
	if (fw[5] > 0.0) {
		float strata = sin(p.y * 0.9 + m25 * 6.0) * 0.5 + 0.5;
		c += rock * ra.rgb * 2.0 * (0.9 + strata * 0.15) * fw[5];
		o += ro * fw[5];
		dn += rn * fw[5];
	}
	if (fw[6] > 0.0) {
		c += snow * texture(alb_arr, vec3(uvs * 0.5, 6.0)).rgb * 2.0 * fw[6];
		o += o6 * fw[6];
		dn += hn(texture(nrm_arr, vec3(uvs * 0.5, 6.0))) * fw[6] * 0.3;
	}
	// Детальные нормали вблизи (до 30 м) — мелкий масштаб той же травы/грунта.
	float near_k = lite ? 0.0 : (1.0 - smoothstep(8.0, 30.0, dist)) * (1.0 - fw[6]) * (1.0 - fw[5]);
	if (near_k > 0.0) {
		vec4 dt = texture(nrm_arr, vec3(p.xz * 2.1, fw[2] + fw[3] > 0.5 ? 2.0 : 0.0));
		dn += hn(dt) * 0.5 * near_k;
	}
	// Дальше — нормали фактуры мягче (меньше муара), общий тон — макро.
	float far_k = smoothstep(120.0, 400.0, dist);
	dn *= 1.0 - far_k * 0.7;
	c *= 0.86 + m25 * 0.28 * (1.0 - fw[6]);

	// Влажность: мокрая земля темнее и глаже, лужи — во впадинах грязи/грунта на тропах.
	float rough = o.g;
	float wet = wetness * (1.0 - fw[6]);
	if (wet > 0.0) {
		float porous = fw[2] + fw[3] + fw[0] * 0.5 + fw[1] * 0.5;
		c *= 1.0 - wet * 0.35 * porous;
		rough = mix(rough, rough * 0.55, wet);
		float h = fw[3] * hgts[3] + fw[2] * hgts[2] + (1.0 - fw[3] - fw[2]) * 1.0;
		float puddle = wet * (1.0 - smoothstep(0.3, 0.42, h)) * smoothstep(0.4, 0.7, path);
		c = mix(c, c * 0.35 + vec3(0.02, 0.025, 0.03), puddle);
		rough = mix(rough, 0.04, puddle);
		dn *= 1.0 - puddle;
	}
	vec3 nb = normalize(n + dn * 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = rough;
	AO = mix(o.r, 1.0, fw[6] * 0.85);
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.3 + fw[6] * 0.1;
	}
}
