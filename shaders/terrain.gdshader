shader_type spatial;
// Земля карты: палитра биома (uniform), грунт из вершин, камень на склонах с трипланарной
// фактурой и слоистостью, снег выше линии снега, рельефные нормали из шума.

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a = vec3(0.20, 0.27, 0.10);
uniform vec3 grass_b = vec3(0.33, 0.34, 0.15);
uniform vec3 dirt = vec3(0.30, 0.24, 0.17);
uniform vec3 rock = vec3(0.38, 0.36, 0.34);
uniform vec3 snow = vec3(0.80, 0.82, 0.84);
uniform float snow_lo = 95.0;
uniform float snow_hi = 125.0;
uniform float bump = 1.0;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 w, float s) {
	return texture(detail_noise, p.zy * s).r * w.x
		+ texture(detail_noise, p.xz * s).r * w.y
		+ texture(detail_noise, p.xy * s).r * w.z;
}

void fragment() {
	vec3 n = normalize(world_n);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float d1 = texture(detail_noise, world_pos.xz * 0.11).r;
	float d2 = texture(detail_noise, world_pos.xz * 0.023).r;
	float m = texture(macro_noise, world_pos.xz * 0.0021).r;
	float slope = 1.0 - n.y;
	float rock_k = smoothstep(0.18, 0.32, slope + (d1 - 0.5) * 0.08);

	// Рельефные нормали: градиент шума в мире (на склонах — трипланарный).
	float e = 0.6;
	float s1 = 0.09;
	float hc = tri(world_pos, w, s1);
	float hx = tri(world_pos + vec3(e, 0.0, 0.0), w, s1);
	float hy = tri(world_pos + vec3(0.0, e, 0.0), w, s1);
	float hz = tri(world_pos + vec3(0.0, 0.0, e), w, s1);
	vec3 g = vec3(hx - hc, hy - hc, hz - hc) / e;
	g -= n * dot(g, n);
	vec3 nb = normalize(n - g * bump * mix(0.12, 1.3, rock_k));
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);

	vec3 base = COLOR.rgb;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, m));
	vec3 c = grass;
	c = mix(c, dirt, smoothstep(0.55, 0.75, d2 * 0.6 + base.r * 0.8));
	// Камень: трипланарная фактура и слои породы.
	float rt = tri(world_pos, w, 0.035);
	float strata = sin(world_pos.y * 0.9 + rt * 6.0) * 0.5 + 0.5;
	vec3 rk = rock * (0.78 + rt * 0.35) * (0.9 + strata * 0.18);
	c = mix(c, rk, rock_k);
	float sn = smoothstep(snow_lo, snow_hi, world_pos.y + d2 * 12.0) * smoothstep(0.45, 0.2, slope);
	c = mix(c, snow, sn);
	c *= 0.82 + d1 * 0.32;
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.75, sn);
	SPECULAR = mix(0.2, 0.35, sn);
}
