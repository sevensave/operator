shader_type spatial;
// Земля долины: цвет из вершин (трава/грунт/камень) + мировой шум для деталей.

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float d1 = texture(detail_noise, world_pos.xz * 0.11).r;
	float d2 = texture(detail_noise, world_pos.xz * 0.023).r;
	float m = texture(macro_noise, world_pos.xz * 0.0021).r;
	vec3 base = COLOR.rgb;
	vec3 grass_a = vec3(0.20, 0.27, 0.10);
	vec3 grass_b = vec3(0.33, 0.34, 0.15);
	vec3 dirt = vec3(0.30, 0.24, 0.17);
	vec3 rock = vec3(0.38, 0.36, 0.34);
	float slope = 1.0 - world_n.y;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, m));
	vec3 c = grass;
	c = mix(c, dirt, smoothstep(0.55, 0.75, d2 * 0.6 + base.r * 0.8));
	c = mix(c, rock, smoothstep(0.18, 0.32, slope + (d1 - 0.5) * 0.08));
	c = mix(c, vec3(0.80, 0.82, 0.84), smoothstep(95.0, 125.0, world_pos.y + d2 * 12.0) * smoothstep(0.45, 0.2, slope));
	c *= 0.82 + d1 * 0.32;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
