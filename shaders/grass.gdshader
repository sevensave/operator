shader_type spatial;
render_mode cull_disabled;
// Трава вокруг камеры: MultiMesh из grid_n² пучков, положение каждого считается здесь по INSTANCE_ID —
// клетка мировой сетки шагом spacing вокруг view_center (трава не «плывёт» за камерой).
// Высота — точно как в треугольниках сетки земли (heights, 161² RF), плотность — маска (G),
// тропы (R) без травы. К краю круга трава редеет и пропадает. Ветер — global wind_vec (sim/wind.gd).
// Высота пучка ≤ 0,6 м (декорация без коллизий).

global uniform vec3 view_center;
global uniform vec3 wind_vec;
uniform sampler2D heights : filter_nearest;
uniform sampler2D mask : filter_linear;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform int grid_n = 150;
uniform float spacing = 0.34;
uniform float map_half = 600.0;
uniform float cell = 7.5;
uniform vec3 color_a = vec3(0.20, 0.27, 0.10);
uniform vec3 color_b = vec3(0.33, 0.34, 0.15);
uniform float dry = 0.2;
uniform float blade_h = 0.38;

varying vec3 col;
varying float tipk;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float ground_h(vec2 xz) {
	vec2 f = clamp((xz + map_half) / cell, vec2(0.0), vec2(159.999));
	ivec2 i = ivec2(f);
	vec2 t = f - vec2(i);
	float h00 = texelFetch(heights, i, 0).r;
	float h10 = texelFetch(heights, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(heights, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(heights, i + ivec2(1, 1), 0).r;
	if (t.x + t.y <= 1.0) return h00 + (h10 - h00) * t.x + (h01 - h00) * t.y;
	return h11 + (h01 - h11) * (1.0 - t.x) + (h10 - h11) * (1.0 - t.y);
}

void vertex() {
	int ix = INSTANCE_ID % grid_n;
	int iz = INSTANCE_ID / grid_n;
	vec2 base = floor(view_center.xz / spacing) - float(grid_n / 2);
	vec2 c = base + vec2(float(ix), float(iz));
	vec2 xz = (c + vec2(hash(c), hash(c + 17.31))) * spacing;
	float h = ground_h(xz);
	vec4 m = texture(mask, ((xz + map_half) / cell + 0.5) / 161.0);
	float radius = float(grid_n) * spacing * 0.5;
	float r = length(xz - view_center.xz);
	// Редеет к краю круга и при взгляде с высоты (вдали трава не видна, экономим вершины).
	float edge = (1.0 - smoothstep(radius * 0.55, radius, r)) * (1.0 - smoothstep(25.0, 60.0, view_center.y - h));
	float inside = step(abs(xz.x), map_half - 4.0) * step(abs(xz.y), map_half - 4.0);
	float keep = step(hash(c + 5.13), m.g * edge) * inside;
	float sc = blade_h * (0.6 + 0.6 * hash(c + 9.7)) * keep * mix(0.55, 1.0, edge);
	float yaw = hash(c + 3.3) * 6.2831;
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 v = VERTEX;
	v.xz = vec2(cy * v.x - sy * v.z, sy * v.x + cy * v.z) * 1.2;
	v *= sc;
	tipk = COLOR.a;
	// Ветер: наклон по ветру и дрожь, сильнее к кончику.
	float gust = 0.7 + 0.3 * sin(TIME * 2.7 + xz.x * 0.35 + xz.y * 0.21);
	vec2 bend = wind_vec.xz * 0.045 * gust + vec2(sin(TIME * 4.1 + c.x), cos(TIME * 3.7 + c.y)) * 0.02;
	v.xz += bend * tipk * tipk * sc * 2.0;
	VERTEX = vec3(xz.x, h, xz.y) + v;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
	// Цвет как у слоя травы земли (тот же макро-шум), плюс сухие пучки.
	float m300 = texture(macro_noise, xz * 0.0021).r;
	float m60 = texture(macro_noise, xz * 0.011 + 0.37).r;
	col = mix(color_a, color_b, smoothstep(0.3, 0.7, m300)) * (0.88 + m60 * 0.24);
	float d = step(1.0 - dry * 0.6, hash(c + 1.9));
	col = mix(col, vec3(color_b.r * 1.45, color_b.g * 1.2, color_b.b * 0.7), d * 0.8);
	col *= 0.85 + hash(c + 2.7) * 0.3;
}

void fragment() {
	ALBEDO = col * mix(0.32, 0.9, tipk);
	BACKLIGHT = col * 0.25 * tipk;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	AO = mix(0.3, 0.9, tipk);
	AO_LIGHT_AFFECT = 0.4;
}
