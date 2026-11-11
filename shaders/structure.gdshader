shader_type spatial;
// Руины и укрытия: вершинный цвет + трипланарная шумовая фактура (бетон, грунт, дерево),
// вертикальные потёки на стенах и закопчённость у земли. Без текстур-файлов.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wp;
varying vec3 wn;
varying float ly;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ly = VERTEX.y;
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= w.x + w.y + w.z;
	float fine = texture(noise_tex, wp.zy * 0.9).r * w.x + texture(noise_tex, wp.xz * 0.9).r * w.y + texture(noise_tex, wp.xy * 0.9).r * w.z;
	float big = texture(noise_tex, wp.zy * 0.12).r * w.x + texture(noise_tex, wp.xz * 0.12).r * w.y + texture(noise_tex, wp.xy * 0.12).r * w.z;
	// Потёки: шум, растянутый по вертикали, только на стенах.
	float streak = texture(noise_tex, vec2((wp.x + wp.z) * 0.6, wp.y * 0.06)).r;
	float wall = 1.0 - w.y;
	vec3 c = COLOR.rgb * (0.72 + big * 0.42) * (0.88 + fine * 0.24);
	c *= 1.0 - wall * smoothstep(0.55, 0.8, streak) * 0.25;
	ALBEDO = c;
	ROUGHNESS = 0.82 + fine * 0.15;
	SPECULAR = 0.25;
}
