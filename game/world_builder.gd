class_name WorldBuilder
## Строит видимый мир по Terrain: землю, лес, руины, небо, свет и туман.
## Время суток, погода и палитра — от пресета карты (MapPreset), как и рельеф.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")


const SKY_SHADER := preload("res://shaders/sky.gdshader")
const TREE_SHADER := preload("res://shaders/tree.gdshader")


static func build(terrain: Terrain, root: Node3D, quality: int) -> void:
	_environment(root, quality, terrain.preset)
	_ground(terrain, root)
	_trees(terrain, root)
	_ruins(terrain, root)


## Наборы времени суток/погоды: свет, небо, туман, экспозиция.
## Соотношение солнце/небо — как у реальной освещённости: ясным днём прямой свет в 4–5 раз
## сильнее рассеянного, в пасмурно/туман почти весь свет — от неба, ночью луна слабая и холодная.
## ang — угловой размер источника (мягкость теней), haze — рассеяние у горизонта,
## ae_iso/ae_scale — опорная чувствительность и цель автоэкспозиции FPV-камеры.
static func atmosphere(daytime: int) -> Dictionary:
	match daytime:
		MapPreset.Daytime.DAWN:
			return {"elev": 9.0, "sun": Color(1.0, 0.70, 0.48), "energy": 1.7, "top": Color(0.26, 0.34, 0.52),
				"horizon": Color(0.92, 0.70, 0.56), "fog": Color(0.78, 0.66, 0.60), "density": 0.0011,
				"ambient": Color(0.55, 0.50, 0.55), "amb_energy": 0.45, "sky_amb": 0.75, "exposure": 1.0,
				"clouds": 0.42, "cloud": Color(1.0, 0.80, 0.68), "cloud_shade": Color(0.46, 0.42, 0.50), "vol": 0.006,
				"ang": 0.6, "haze": 0.9, "sky_e": 1.0, "scatter": 0.35, "ae_lum": 0.30, "ae_up": 1.5}
		MapPreset.Daytime.DUSK:
			return {"elev": 7.0, "sun": Color(1.0, 0.55, 0.32), "energy": 1.7, "top": Color(0.20, 0.22, 0.40),
				"horizon": Color(0.96, 0.56, 0.38), "fog": Color(0.68, 0.50, 0.44), "density": 0.0010,
				"ambient": Color(0.50, 0.42, 0.48), "amb_energy": 0.45, "sky_amb": 0.75, "exposure": 1.0,
				"clouds": 0.5, "cloud": Color(1.0, 0.62, 0.42), "cloud_shade": Color(0.34, 0.29, 0.38), "vol": 0.006,
				"ang": 0.6, "haze": 1.0, "sky_e": 0.95, "scatter": 0.4, "ae_lum": 0.28, "ae_up": 1.5}
		MapPreset.Daytime.OVERCAST:
			return {"elev": 42.0, "sun": Color(0.86, 0.89, 0.93), "energy": 0.4, "top": Color(0.50, 0.54, 0.58),
				"horizon": Color(0.70, 0.72, 0.73), "fog": Color(0.62, 0.64, 0.66), "density": 0.0016,
				"ambient": Color(0.62, 0.65, 0.70), "amb_energy": 1.0, "sky_amb": 0.9, "exposure": 1.0,
				"clouds": 0.9, "cloud": Color(0.76, 0.77, 0.78), "cloud_shade": Color(0.50, 0.51, 0.52), "vol": 0.008, "disk": 0.0,
				"ang": 6.0, "haze": 0.15, "sky_e": 1.0, "scatter": 0.0, "ae_lum": 0.40, "ae_up": 1.4}
		MapPreset.Daytime.FOG:
			return {"elev": 28.0, "sun": Color(0.96, 0.93, 0.86), "energy": 0.55, "top": Color(0.62, 0.65, 0.68),
				"horizon": Color(0.78, 0.79, 0.80), "fog": Color(0.74, 0.76, 0.77), "density": 0.0042,
				"ambient": Color(0.70, 0.72, 0.74), "amb_energy": 0.9, "sky_amb": 0.85, "exposure": 1.0,
				"clouds": 0.7, "cloud": Color(0.88, 0.89, 0.90), "cloud_shade": Color(0.62, 0.64, 0.66), "vol": 0.008, "disk": 0.3,
				"ang": 3.0, "haze": 0.3, "sky_e": 1.0, "scatter": 0.25, "ae_lum": 0.45, "ae_up": 1.3}
		MapPreset.Daytime.NIGHT:
			return {"elev": 38.0, "sun": Color(0.55, 0.66, 1.0), "energy": 0.35, "top": Color(0.02, 0.03, 0.08),
				"horizon": Color(0.10, 0.13, 0.22), "fog": Color(0.10, 0.12, 0.19), "density": 0.0011,
				"ambient": Color(0.26, 0.32, 0.52), "amb_energy": 0.6, "sky_amb": 0.3, "exposure": 1.5,
				"clouds": 0.3, "cloud": Color(0.22, 0.25, 0.34), "cloud_shade": Color(0.06, 0.07, 0.11), "vol": 0.004,
				"stars": 1.0, "moon": 1.0, "ang": 0.5, "haze": 0.2, "sky_e": 1.0, "scatter": 0.05, "ae_lum": 0.07, "ae_up": 1.0}
	return {"elev": 48.0, "sun": Color(1.0, 0.95, 0.87), "energy": 2.2, "top": Color(0.26, 0.42, 0.66),
		"horizon": Color(0.70, 0.75, 0.80), "fog": Color(0.64, 0.68, 0.72), "density": 0.0007,
		"ambient": Color(0.60, 0.64, 0.66), "amb_energy": 0.5, "sky_amb": 0.9, "exposure": 1.0,
		"clouds": 0.35, "cloud": Color(0.98, 0.98, 0.97), "cloud_shade": Color(0.58, 0.62, 0.68), "vol": 0.003,
		"ang": 0.55, "haze": 0.6, "sky_e": 1.0, "scatter": 0.2, "ae_lum": 0.50, "ae_up": 1.4}


## Палитры биомов для земли, деревьев и дальнего пола.
static func palette(biome: int) -> Dictionary:
	match biome:
		MapPreset.Biome.AUTUMN:
			return {"grass_a": Color(0.33, 0.27, 0.11), "grass_b": Color(0.44, 0.33, 0.13), "dirt": Color(0.32, 0.22, 0.14),
				"rock": Color(0.40, 0.37, 0.33), "snow": Color(0.80, 0.82, 0.84), "snow_lo": 110.0, "snow_hi": 140.0,
				"far": Color(0.34, 0.28, 0.16), "spruce": Color(0.15, 0.24, 0.13),
				"leafy": [Color(0.72, 0.38, 0.10), Color(0.78, 0.60, 0.16), Color(0.58, 0.20, 0.10), Color(0.45, 0.42, 0.14)]}
		MapPreset.Biome.WINTER:
			return {"grass_a": Color(0.50, 0.49, 0.44), "grass_b": Color(0.62, 0.62, 0.60), "dirt": Color(0.34, 0.30, 0.27),
				"rock": Color(0.34, 0.34, 0.36), "snow": Color(0.86, 0.88, 0.92), "snow_lo": -10.0, "snow_hi": 30.0,
				"far": Color(0.78, 0.80, 0.84), "spruce": Color(0.30, 0.38, 0.36),
				"leafy": [Color(0.42, 0.38, 0.32), Color(0.50, 0.46, 0.40)]}
		MapPreset.Biome.STEPPE:
			return {"grass_a": Color(0.38, 0.34, 0.18), "grass_b": Color(0.47, 0.41, 0.22), "dirt": Color(0.44, 0.34, 0.22),
				"rock": Color(0.50, 0.43, 0.35), "snow": Color(0.80, 0.82, 0.84), "snow_lo": 900.0, "snow_hi": 1000.0,
				"far": Color(0.44, 0.38, 0.22), "spruce": Color(0.20, 0.27, 0.15),
				"leafy": [Color(0.38, 0.40, 0.17), Color(0.46, 0.44, 0.20)]}
	return {"grass_a": Color(0.20, 0.27, 0.10), "grass_b": Color(0.33, 0.34, 0.15), "dirt": Color(0.30, 0.24, 0.17),
		"rock": Color(0.38, 0.36, 0.34), "snow": Color(0.80, 0.82, 0.84), "snow_lo": 95.0, "snow_hi": 125.0,
		"far": Color(0.30, 0.33, 0.22), "spruce": Color(0.17, 0.28, 0.14),
		"leafy": [Color(0.24, 0.38, 0.14), Color(0.30, 0.44, 0.16), Color(0.20, 0.33, 0.12)]}


static func _environment(root: Node3D, quality: int, preset: MapPreset) -> void:
	var at := atmosphere(preset.daytime)
	var night := preset.daytime == MapPreset.Daytime.NIGHT
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", at.top)
	sky_mat.set_shader_parameter("horizon_color", at.horizon)
	sky_mat.set_shader_parameter("ground_color", (at.fog as Color).darkened(0.45))
	sky_mat.set_shader_parameter("cloud_color", at.cloud)
	sky_mat.set_shader_parameter("cloud_shade", at.cloud_shade)
	sky_mat.set_shader_parameter("cloud_cover", at.clouds)
	sky_mat.set_shader_parameter("cloud_seed", float(preset.seed % 997) * 0.731)
	var wd := Vector2(cos(preset.wind_dir), sin(preset.wind_dir))
	sky_mat.set_shader_parameter("cloud_drift", wd * preset.wind_base * 0.0012)
	sky_mat.set_shader_parameter("stars", at.get("stars", 0.0))
	sky_mat.set_shader_parameter("sun_disk", at.get("disk", 1.0))
	sky_mat.set_shader_parameter("moon", at.get("moon", 0.0))
	sky_mat.set_shader_parameter("haze", at.haze)
	sky_mat.set_shader_parameter("sky_energy", at.sky_e)
	sky_mat.set_shader_parameter("cloud_steps", [3, 6, 8][clampi(quality, 0, 2)])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# Облака движутся (TIME) — отражения обновляем постепенно.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256 if quality >= 1 else Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = at.ambient
	env.ambient_light_sky_contribution = at.sky_amb
	env.ambient_light_energy = at.amb_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX: мягкое плечо и честное выцветание пересветов, как у сенсора дешёвой камеры.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = at.exposure
	env.tonemap_agx_white = 8.0
	env.tonemap_agx_contrast = 1.35
	env.fog_enabled = true
	env.fog_light_color = at.fog
	env.fog_density = at.density
	env.fog_aerial_perspective = 0.65
	env.fog_sun_scatter = at.get("scatter", 0.15)
	env.fog_sky_affect = 0.35 if preset.daytime != MapPreset.Daytime.FOG else 0.7
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.5 if not night else 0.8
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Приглушённая нейтральная гамма: без «мультяшной» насыщенности.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9 if not night else 0.6
	env.adjustment_contrast = 1.0
	if quality >= 1:
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.6
		env.ssao_power = 1.4
		env.ssao_light_affect = 0.15
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.ssil_intensity = 0.7
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = at.vol * (1.0 if quality >= 2 else 0.8)
		env.volumetric_fog_albedo = (at.fog as Color).lightened(0.2)
		env.volumetric_fog_length = 220.0 if quality >= 2 else 140.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_ambient_inject = 0.7   # туман подсвечен небом, а не только солнцем — не темнеет
		env.volumetric_fog_sky_affect = 0.0
	if quality >= 2:
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_energy = 0.8
		env.ssil_enabled = false   # SDFGI даёт отражённый свет сам
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-at.elev), preset.sun_azimuth, 0)
	sun.light_color = at.sun
	sun.light_energy = at.energy
	# Угловой размер источника — мягкость теней: солнце ясным днём, рассеянный свет в пасмурно/туман.
	sun.light_angular_distance = at.ang
	sun.shadow_enabled = quality >= 1
	sun.shadow_blur = 1.0 + at.ang * 0.4
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = 320.0 if quality >= 2 else 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = quality >= 2
	sun.directional_shadow_fade_start = 0.85
	sun.light_volumetric_fog_energy = 1.4
	sun.name = "Sun"
	root.add_child(sun)


## Атрибуты FPV-камеры: инерционная автоэкспозиция в пределах, заданных временем суток
## (ночь не вытягивается в день, против солнца кадр темнеет, в тени — светлеет).
static func camera_attributes(daytime: int) -> CameraAttributesPractical:
	var at := atmosphere(daytime)
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_speed = 0.9
	# Опорная средняя яркость сцены ae_lum даёт ту же экспозицию, что ручная tonemap_exposure.
	# Вытянуть тёмный кадр можно не больше чем в ae_up раз, затемнить яркий — до 2,5 раза.
	# Пределы задаются чувствительностью (ISO): яркость = ISO × 12,5 / 100 / 100.
	var lum: float = at.ae_lum
	ca.auto_exposure_scale = lum
	ca.auto_exposure_min_sensitivity = lum / float(at.ae_up) / 0.00125
	ca.auto_exposure_max_sensitivity = lum * 2.5 / 0.00125
	return ca


## Настройки вьюпорта и глобальные качества эффектов по уровню графики.
## 0 — MSAA+FXAA как раньше; 1–2 — TAA (сглаживает и мелкую листву/траву, и тени).
static func apply_viewport(vp: Viewport, quality: int) -> void:
	if vp == null:
		return
	if quality >= 1:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = true
	else:
		vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.use_taa = false
	vp.use_debanding = quality >= 1
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X if quality <= 1 else Viewport.ANISOTROPY_16X
	var rs := RenderingServer
	if quality >= 2:
		rs.environment_set_volumetric_fog_volume_size(64, 64)
		rs.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2, 50.0, 300.0)
		rs.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	else:
		rs.environment_set_volumetric_fog_volume_size(48, 32)
		rs.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		rs.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
	rs.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality >= 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


## Косметические осадки вокруг камеры (только при quality ≥ 1). null — если на карте сухо.
static func precipitation(preset: MapPreset, quality: int) -> GPUParticles3D:
	if preset.precip == MapPreset.Precip.NONE or quality < 1:
		return null
	var rain := preset.precip == MapPreset.Precip.RAIN
	var p := GPUParticles3D.new()
	p.amount = (1600 if rain else 1200) * (2 if quality >= 2 else 1)
	p.lifetime = 1.6 if rain else 5.0
	p.preprocess = p.lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-50, -40, -50), Vector3(100, 80, 100))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 2, 45)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0 if rain else 25.0
	pm.initial_velocity_min = 22.0 if rain else 1.5
	pm.initial_velocity_max = 28.0 if rain else 3.0
	pm.gravity = Vector3(0, -9.8, 0) if rain else Vector3(0, -0.6, 0)
	if not rain:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.5
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.9) if rain else Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.80, 0.88, 0.35) if rain else Color(0.95, 0.96, 1.0, 0.85)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if rain else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	p.draw_pass_1 = q
	p.name = "Precip"
	return p


static func _ground(terrain: Terrain, root: Node3D) -> void:
	var n := Terrain.N
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirt := FastNoiseLite.new()
	dirt.seed = terrain.seed + 5
	dirt.frequency = 0.01
	# Вершины
	for zi in n:
		for xi in n:
			var x := -SimConst.MAP_HALF + xi * Terrain.CELL
			var z := -SimConst.MAP_HALF + zi * Terrain.CELL
			var h := terrain.heights[zi * n + xi]
			var nrm := terrain.normal_at(x, z)
			var road := 0.0
			# Тропинки от укрытий к центру — тёмный грунт.
			for s in terrain.shelters:
				var a := Vector2(s.x, s.z)
				var p := Vector2(x, z)
				var dir := -a.normalized()
				var t := clampf((p - a).dot(dir), 0.0, a.length())
				var dist := (a + dir * t).distance_to(p)
				road = maxf(road, smoothstep(9.0, 3.0, dist + dirt.get_noise_2d(x, z) * 6.0))
			st.set_color(Color(road * 0.8 + maxf(0.0, dirt.get_noise_2d(x * 2.0, z * 2.0)) * 0.4, 0, 0))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z) * 0.05)
			st.add_vertex(Vector3(x, h, z))
	for zi in n - 1:
		for xi in n - 1:
			var i := zi * n + xi
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + n)
	var mesh := st.commit()
	var pal := palette(terrain.preset.biome)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("detail_noise", SurfaceLib.noise_tex(0.02))
	mat.set_shader_parameter("macro_noise", SurfaceLib.noise_tex(0.008))
	for key in ["grass_a", "grass_b", "dirt", "rock", "snow"]:
		var col: Color = pal[key]
		mat.set_shader_parameter(key, Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("snow_lo", pal.snow_lo + terrain.preset.base_lift)
	mat.set_shader_parameter("snow_hi", pal.snow_hi + terrain.preset.base_lift)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Ground"
	root.add_child(mi)
	# Дальняя земля вокруг карты (с дырой над долиной), чтобы у гор не было обрыва.
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := SimConst.MAP_HALF - 2.0
	var outer := 4000.0
	# Уровень — чуть ниже самой низкой точки края карты (у каждого архетипа свой).
	var y := INF
	for i in n:
		y = minf(y, minf(minf(terrain.heights[i], terrain.heights[(n - 1) * n + i]), minf(terrain.heights[i * n], terrain.heights[i * n + n - 1])))
	y -= 4.0
	var rects := [Rect2(-outer, -outer, outer * 2, outer - inner), Rect2(-outer, inner, outer * 2, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2), Rect2(inner, -inner, outer - inner, inner * 2)]
	for r in rects:
		var a := Vector3(r.position.x, y, r.position.y)
		var b := Vector3(r.end.x, y, r.position.y)
		var c := Vector3(r.end.x, y, r.end.y)
		var d := Vector3(r.position.x, y, r.end.y)
		fst.set_normal(Vector3.UP)
		for v in [a, b, c, a, c, d]:
			fst.add_vertex(v)
	var far := MeshInstance3D.new()
	far.mesh = fst.commit()
	var fm := StandardMaterial3D.new()
	fm.albedo_color = pal.far
	fm.roughness = 1.0
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	far.material_override = fm
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far)


## Три вида деревьев одной высоты (~7 м до масштаба). Вершинный цвет: rgb — оттенок,
## a — 1 для кроны, 0 для ствола (цвет кроны задаёт экземпляр).
static func tree_mesh(kind := MapPreset.TreeKind.SPRUCE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(1, 1, 1, 0)
	match kind:
		MapPreset.TreeKind.LEAFY:
			_cone(st, Vector3(0, 0, 0), 0.28, 0.16, 3.6, 6, trunk)
			_cone(st, Vector3(0, 2.4, 0), 0.12, 0.05, 1.6, 5, trunk, Vector3(0.6, 0, 0.2))
			_cone(st, Vector3(0, 2.6, 0), 0.12, 0.05, 1.5, 5, trunk, Vector3(-0.5, 0, -0.3))
			var crown := [Vector4(0, 4.7, 0, 1.9), Vector4(0.9, 4.0, 0.4, 1.4), Vector4(-0.8, 4.2, -0.5, 1.5),
				Vector4(0.1, 5.7, -0.2, 1.3)]
			for i in crown.size():
				var c: Vector4 = crown[i]
				var shade := 0.82 + 0.06 * i
				_blob(st, Vector3(c.x, c.y, c.z), c.w, Color(shade, shade, shade, 1))
		MapPreset.TreeKind.DEAD:
			_cone(st, Vector3(0, 0, 0), 0.3, 0.06, 6.6, 6, trunk)
			var br := [Vector3(0.7, 0, 0.3), Vector3(-0.6, 0, 0.5), Vector3(0.2, 0, -0.8), Vector3(-0.4, 0, -0.4), Vector3(0.6, 0, -0.2)]
			for i in br.size():
				var y := 2.0 + i * 0.85
				_cone(st, Vector3(0, y, 0), 0.1 - i * 0.012, 0.03, 1.4 - i * 0.15, 4, trunk, br[i] * 1.2)
		_:
			_cone(st, Vector3(0, 0, 0), 0.25, 0.18, 2.2, 6, trunk)
			_cone(st, Vector3(0, 1.4, 0), 1.6, 0.0, 3.6, 7, Color(0.85, 0.85, 0.85, 1))
			_cone(st, Vector3(0, 3.0, 0), 1.25, 0.0, 3.0, 7, Color(1.0, 1.0, 1.0, 1))
			_cone(st, Vector3(0, 4.4, 0), 0.9, 0.0, 2.4, 7, Color(1.12, 1.12, 1.12, 1))
	st.generate_normals()
	return st.commit()


## Низкополигональный «шар» кроны (октаэдр, дважды разбитый) со смещёнными вершинами.
static func _blob(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var v := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 3, 4], [0, 4, 2], [0, 2, 5], [0, 5, 3], [1, 4, 3], [1, 2, 4], [1, 5, 2], [1, 3, 5]]
	for f in faces:
		_blob_tri(st, c, r, v[f[0]], v[f[1]], v[f[2]], 1, col)


static func _blob_tri(st: SurfaceTool, c: Vector3, r: float, a: Vector3, b: Vector3, d: Vector3, depth: int, col: Color) -> void:
	if depth > 0:
		var ab := (a + b).normalized()
		var bd := (b + d).normalized()
		var da := (d + a).normalized()
		_blob_tri(st, c, r, a, ab, da, depth - 1, col)
		_blob_tri(st, c, r, ab, b, bd, depth - 1, col)
		_blob_tri(st, c, r, da, bd, d, depth - 1, col)
		_blob_tri(st, c, r, ab, bd, da, depth - 1, col)
		return
	for p: Vector3 in [a, d, b]:
		var wob := 1.0 + 0.12 * sin(p.x * 7.0 + p.z * 5.0) + 0.08 * sin(p.y * 9.0)
		var sh := 0.78 + 0.22 * (p.y * 0.5 + 0.5)
		st.set_color(Color(col.r * sh, col.g * sh, col.b * sh, col.a))
		st.add_vertex(c + p * r * Vector3(1.0, 0.85, 1.0) * wob)


static func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, seg: int, c: Color, lean := Vector3.ZERO) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + lean + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + lean + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		var lo := Color(c.r * 0.85, c.g * 0.85, c.b * 0.85, c.a)
		st.set_color(lo)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.set_color(c)
		st.add_vertex(q0)
		if r1 > 0.0:
			st.add_vertex(q0)
			st.set_color(lo)
			st.add_vertex(p1)
			st.set_color(c)
			st.add_vertex(q1)
		# днище
		st.set_color(Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, c.a))
		st.add_vertex(base)
		st.add_vertex(p1)
		st.add_vertex(p0)


static func _trees(terrain: Terrain, root: Node3D) -> void:
	var preset := terrain.preset
	var pal := palette(preset.biome)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var kind := preset.tree_kind
	if kind == MapPreset.TreeKind.LEAFY and preset.biome == MapPreset.Biome.WINTER:
		kind = MapPreset.TreeKind.DEAD   # зимой лиственные стоят голые
	mm.mesh = tree_mesh(kind)
	mm.instance_count = terrain.trees.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed + 3
	var leafy: Array = pal.leafy
	for i in terrain.trees.size():
		var t := terrain.trees[i]
		var g := terrain.height_at(t.x, t.y)
		var h := t.w - g
		var s := h / 7.0
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * (t.z / 2.0) * 1.1, s, s * (t.z / 2.0) * 1.1))
		mm.set_instance_transform(i, Transform3D(b, Vector3(t.x, g - 0.3, t.y)))
		var tint := rng.randf_range(0.82, 1.18)
		var crown: Color = pal.spruce if preset.tree_kind == MapPreset.TreeKind.SPRUCE else leafy[rng.randi() % leafy.size()]
		crown = Color(crown.r * tint, crown.g * tint * rng.randf_range(0.95, 1.06), crown.b * tint, rng.randf())
		mm.set_instance_custom_data(i, crown)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADER
	var trunk := Color(0.28, 0.20, 0.14) if kind != MapPreset.TreeKind.DEAD else Color(0.34, 0.30, 0.26)
	mat.set_shader_parameter("trunk_color", Vector3(trunk.r, trunk.g, trunk.b))
	mat.set_shader_parameter("wind_dir", Vector2(cos(preset.wind_dir), sin(preset.wind_dir)))
	mat.set_shader_parameter("sway", 0.06 + preset.wind_base * 0.06)
	mi.material_override = mat
	mi.name = "Forest"
	root.add_child(mi)


static func _ruins(terrain: Terrain, root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed + 11
	for b in terrain.boxes:
		var tall := b.size.y > 15.0
		var c := Color(0.55, 0.53, 0.50) if not tall else Color(0.42, 0.40, 0.38)
		c = c * rng.randf_range(0.85, 1.1)
		if tall:
			# Вышка: опоры и бак сверху.
			var top := b.position + Vector3(0, b.size.y, 0)
			for k in 4:
				var off := Vector3(0.3 if k % 2 == 0 else b.size.x - 0.6, 0, 0.3 if k < 2 else b.size.z - 0.6)
				_box(st, AABB(b.position + off, Vector3(0.3, b.size.y - 4.0, 0.3)), c)
			_box(st, AABB(top - Vector3(0, 4.0, 0) + Vector3(-0.4, 0, -0.4), Vector3(b.size.x + 0.8, 4.0, b.size.z + 0.8)), c * 1.1)
			continue
		# Коробка разрушенного дома: стены с проломами, без крыши.
		var wall := 0.5
		var heights := [b.size.y * rng.randf_range(0.5, 1.0), b.size.y * rng.randf_range(0.3, 1.0),
			b.size.y * rng.randf_range(0.6, 1.0), b.size.y * rng.randf_range(0.2, 0.9)]
		_box(st, AABB(b.position, Vector3(b.size.x, heights[0], wall)), c)
		_box(st, AABB(b.position + Vector3(0, 0, b.size.z - wall), Vector3(b.size.x * rng.randf_range(0.4, 1.0), heights[1], wall)), c)
		_box(st, AABB(b.position, Vector3(wall, heights[2], b.size.z)), c * 0.95)
		_box(st, AABB(b.position + Vector3(b.size.x - wall, 0, 0), Vector3(wall, heights[3], b.size.z * rng.randf_range(0.5, 1.0))), c * 0.95)
		# Перекрытие-плита, иногда.
		if rng.randf() < 0.5:
			_box(st, AABB(b.position + Vector3(0, minf(heights[0], heights[2]) - 0.4, 0), Vector3(b.size.x * 0.7, 0.4, b.size.z * 0.6)), c * 0.8)
		# Завалы.
		for k in 4:
			var p := b.position + Vector3(rng.randf() * b.size.x, 0.6, rng.randf() * b.size.z)
			_box(st, AABB(p, Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.4, 1.0), rng.randf_range(0.6, 1.8))), c * 0.7)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = structure_material()
	mi.name = "Ruins"
	root.add_child(mi)


const STRUCTURE_SHADER := preload("res://shaders/structure.gdshader")
static var _structure_mat: ShaderMaterial


## Общий материал построек: вершинный цвет + процедурная фактура.
static func structure_material() -> ShaderMaterial:
	if _structure_mat == null:
		_structure_mat = ShaderMaterial.new()
		_structure_mat.shader = STRUCTURE_SHADER
		_structure_mat.set_shader_parameter("noise_tex", SurfaceLib.noise_tex(0.03))
	return _structure_mat


static func _box(st: SurfaceTool, b: AABB, c: Color) -> void:
	var p := b.position
	var s := b.size
	var v := [
		p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z),
		p + Vector3(0, s.y, 0), p + Vector3(s.x, s.y, 0), p + Vector3(s.x, s.y, s.z), p + Vector3(0, s.y, s.z)]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]
	var shade := [0.9, 0.8, 0.9, 0.8, 1.0, 0.5]
	for fi in faces.size():
		var f: Array = faces[fi]
		var col: Color = c * shade[fi]
		col.a = 1.0
		st.set_color(col)
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[3]])
		st.add_vertex(v[f[2]])


## Публичный помощник для других построек.
static func add_box(st: SurfaceTool, b: AABB, c: Color) -> void:
	_box(st, b, c)


## Повёрнутая коробка: центр и базис в xf, размеры size.
static func add_obox(st: SurfaceTool, xf: Transform3D, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var v := []
	for k in 8:
		var p := Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		v.append(xf * p)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		st.set_color(c)
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[2]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[3]])
		st.add_vertex(v[f[2]])
