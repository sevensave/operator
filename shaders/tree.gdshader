shader_type spatial;
// Деревья в MultiMesh: вершинный цвет — оттенок (rgb) и признак кроны (a),
// INSTANCE_CUSTOM — цвет кроны экземпляра (rgb) и фаза покачивания (a).

uniform vec3 trunk_color = vec3(0.28, 0.20, 0.14);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway = 0.25;        // амплитуда в метрах у верхушки
uniform float tree_height = 7.0;  // высота меша до масштаба

varying vec4 crown;

void vertex() {
	crown = INSTANCE_CUSTOM;
	float k = clamp(VERTEX.y / tree_height, 0.0, 1.0);
	k *= k;
	float ph = INSTANCE_CUSTOM.a * 6.2831;
	float s = sin(TIME * 1.3 + ph) * 0.7 + sin(TIME * 2.9 + ph * 1.7) * 0.3;
	// Ветер в мире, вершины в локальных координатах: переводим сдвиг через обратный поворот.
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (0.6 + 0.4 * s) * sway * k;
	off += vec3(-wind_dir.y, 0.0, wind_dir.x) * sin(TIME * 2.1 + ph * 2.3) * sway * 0.25 * k;
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * off;
}

void fragment() {
	vec3 c = mix(trunk_color, crown.rgb, COLOR.a) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(0.12) * COLOR.a;
}
