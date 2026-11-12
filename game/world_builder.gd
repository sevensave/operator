class_name WorldBuilder
## Строит видимый мир по Terrain: землю, лес, руины, небо, свет и туман.
## Время суток, погода и палитра — от пресета карты (MapPreset), как и рельеф.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")


const SKY_SHADER := preload("res://shaders/sky.gdshader")


static func build(terrain: Terrain, root: Node3D, quality: int) -> void:
	_quality = quality
	_environment(root, quality, terrain.preset)
	_ground(terrain, root, quality)
	FoliageBuilder.build(terrain, root, quality)
	_ruins(terrain, root, quality)
	_structure_weather(terrain.preset)


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
	q.size = Vector2(0.025, 1.1) if rain else Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.80, 0.88, 0.3) if rain else Color(0.95, 0.96, 1.0, 0.85)
	# Штрих дождя — с мягкими концами (смаз капли за выдержку), снежинка — мягкий кружок.
	m.albedo_texture = _streak_texture(rain)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if rain else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	q.material = m
	p.draw_pass_1 = q
	p.name = "Precip"
	if rain and quality >= 1:
		p.add_child(_splashes(quality))
	return p


## Брызги дождя у земли: короткие белёсые всплески в полосе вокруг камеры (match_view держит
## узел осадков над камерой — брызги опускаются к земле своим смещением).
static func _splashes(quality: int) -> GPUParticles3D:
	var s := GPUParticles3D.new()
	s.amount = 500 if quality >= 2 else 260
	s.lifetime = 0.35
	s.local_coords = false
	s.name = "Splashes"
	s.visibility_aabb = AABB(Vector3(-40, -60, -40), Vector3(80, 80, 80))
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.1, 22)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	s.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.8, 0.84, 0.9, 0.45)
	m.albedo_texture = _streak_texture(false)
	q.material = m
	s.draw_pass_1 = q
	return s


static var _streaks := {}


static func _streak_texture(rain: bool) -> Texture2D:
	if _streaks.has(rain):
		return _streaks[rain]
	var w := 8 if rain else 32
	var h := 64 if rain else 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var a := (1.0 - u * u) * (1.0 - v * v * v * v) if rain else clampf(1.0 - (u * u + v * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_streaks[rain] = ImageTexture.create_from_image(img)
	return _streaks[rain]


static func _ground(terrain: Terrain, root: Node3D, quality := 1) -> void:
	var n := Terrain.N
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirt := FastNoiseLite.new()
	dirt.seed = terrain.seed + 5
	dirt.frequency = 0.01
	var path_mask := PackedFloat32Array()
	path_mask.resize(n * n)
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
			var mask := road * 0.8 + maxf(0.0, dirt.get_noise_2d(x * 2.0, z * 2.0)) * 0.4
			path_mask[zi * n + xi] = mask
			st.set_color(Color(mask, 0, 0))
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
	terrain.set_meta("path_mask", path_mask)   # для травы и мелочи (FoliageBuilder)
	var mat := ground_material(terrain.preset, quality)
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
	# Тот же материал в упрощённом виде: тон и макро-пятна совпадают с краем карты.
	var fm := mat.duplicate() as ShaderMaterial
	fm.set_shader_parameter("far_mode", true)
	far.material_override = fm
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far)


const GROUND_LAYERS := [SurfaceLib.GRASS, SurfaceLib.DRY_GRASS, SurfaceLib.SOIL, SurfaceLib.MUD,
	SurfaceLib.GRAVEL, SurfaceLib.ROCK, SurfaceLib.SNOW]


## Материал земли: слои из библиотеки поверхностей, оттенки — палитра биома, погода — пресет.
static func ground_material(preset: MapPreset, quality: int) -> ShaderMaterial:
	var size := SurfaceLib.size_for(quality)
	var pal := palette(preset.biome)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("alb_arr", SurfaceLib.array(GROUND_LAYERS, 0, size))
	mat.set_shader_parameter("nrm_arr", SurfaceLib.array(GROUND_LAYERS, 1, size))
	mat.set_shader_parameter("orm_arr", SurfaceLib.array(GROUND_LAYERS, 2, size))
	mat.set_shader_parameter("macro_noise", SurfaceLib.noise_tex(0.008))
	for key in ["grass_a", "grass_b", "dirt", "rock", "snow"]:
		var col: Color = pal[key]
		mat.set_shader_parameter(key, Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("snow_lo", pal.snow_lo + preset.base_lift)
	mat.set_shader_parameter("snow_hi", pal.snow_hi + preset.base_lift)
	var t := SurfaceLib.TILE
	mat.set_shader_parameter("tiles", Vector4(1.0 / t[SurfaceLib.GRASS], 1.0 / t[SurfaceLib.SOIL], 1.0 / t[SurfaceLib.GRAVEL], 1.0 / t[SurfaceLib.ROCK]))
	var rain := preset.precip == MapPreset.Precip.RAIN
	var damp := preset.daytime == MapPreset.Daytime.FOG or preset.daytime == MapPreset.Daytime.OVERCAST
	mat.set_shader_parameter("wetness", 0.85 if rain else (0.3 if damp and preset.biome != MapPreset.Biome.STEPPE else 0.0))
	mat.set_shader_parameter("snow_cover", 0.35 if preset.precip == MapPreset.Precip.SNOW else 0.0)
	mat.set_shader_parameter("lite", quality <= 0)
	return mat


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


## Поверхности построек (код в альфе вершинного цвета, слой массива текстур structure-шейдера).
enum { SURF_CONCRETE, SURF_BRICK, SURF_PLASTER, SURF_RUST, SURF_WOOD, SURF_SOIL, SURF_ASPHALT }
const STRUCT_LAYERS := [SurfaceLib.CONCRETE, SurfaceLib.BRICK, SurfaceLib.PLASTER, SurfaceLib.RUST,
	SurfaceLib.BARK, SurfaceLib.SOIL, SurfaceLib.ASPHALT]
static var _quality := 1


## Начать сетку постройки: нужен канал CUSTOM0 (уровень земли для грязи у основания).
static func begin_structure(st: SurfaceTool) -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)


## Руины: дома со стенами из простенков и перемычек (оконные проёмы с откосами — толщина стены),
## обломанным верхом, обрушенным перекрытием, арматурой и завалами; вышки — опоры с раскосами и бак.
## Всё строго внутри AABB из Terrain.boxes (хитбокс не меняется); внешний вид — свой RNG.
static func _ruins(terrain: Terrain, root: Node3D, quality := 1) -> void:
	var st := SurfaceTool.new()
	begin_structure(st)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed + 11
	var decals := []
	for b in terrain.boxes:
		var ground := b.position.y + 1.0
		var tall := b.size.y > 15.0
		if tall:
			_tower(st, b, ground, rng)
			continue
		var k := rng.randf()
		var surf := SURF_BRICK if k < 0.5 else (SURF_PLASTER if k < 0.78 else SURF_CONCRETE)
		var c := Color(0.56, 0.54, 0.51) * rng.randf_range(0.9, 1.08)
		if surf == SURF_PLASTER:
			c = [Color(0.62, 0.58, 0.50), Color(0.55, 0.57, 0.55), Color(0.60, 0.52, 0.46)][rng.randi() % 3] * rng.randf_range(0.9, 1.05)
		var wall := 0.45
		var top := b.size.y
		var hs := [top * rng.randf_range(0.6, 1.0), top * rng.randf_range(0.35, 1.0), top * rng.randf_range(0.65, 1.0), top * rng.randf_range(0.25, 0.9)]
		var lens := [1.0, rng.randf_range(0.45, 1.0), 1.0, rng.randf_range(0.5, 1.0)]
		# Стены: 0 — передняя (−z), 1 — задняя (+z), 2 — левая (−x), 3 — правая (+x).
		_wall(st, b.position, Vector3.RIGHT, b.size.x * lens[0], hs[0], wall, ground, surf, c, rng, Vector3.BACK)
		_wall(st, b.position + Vector3(0, 0, b.size.z - wall), Vector3.RIGHT, b.size.x * lens[1], hs[1], wall, ground, surf, c, rng, Vector3.FORWARD)
		_wall(st, b.position + Vector3(0, 0, wall), Vector3.BACK, (b.size.z - wall * 2.0), hs[2], wall, ground, surf, c * 0.97, rng, Vector3.RIGHT, true)
		_wall(st, b.position + Vector3(b.size.x - wall, 0, wall), Vector3.BACK, (b.size.z - wall * 2.0) * lens[3], hs[3], wall, ground, surf, c * 0.97, rng, Vector3.LEFT, true)
		# Перекрытие: целое по краю или обрушенное наклонно внутрь (внутри AABB).
		var slab_y := minf(hs[0], hs[2])
		if slab_y > 3.4 and rng.randf() < 0.7:
			var fl := b.position.y + minf(3.4, slab_y - 0.3)
			var sx := b.size.x * rng.randf_range(0.45, 0.7)
			var sz := b.size.z * rng.randf_range(0.45, 0.7)
			_box(st, AABB(Vector3(b.position.x + wall, fl, b.position.z + wall), Vector3(sx, 0.25, sz)), c * 0.85, SURF_CONCRETE, ground)
			# Свисающая обрушенная часть: повёрнутая плита от края целой до пола.
			var drop := fl - b.position.y - 1.2
			var span := minf(b.size.x - sx - wall * 2.0 - 0.2, 4.0)
			if span > 1.2 and drop > 1.0:
				var ang := atan2(drop, span)
				var len := sqrt(span * span + drop * drop) * 0.9
				var cpos := Vector3(b.position.x + wall + sx + span * 0.45, fl - drop * 0.45, b.position.z + wall + sz * 0.5)
				var xf := Transform3D(Basis(Vector3.BACK, -ang), cpos)
				add_obox(st, xf, Vector3(len, 0.22, sz * 0.9), c * 0.8, SURF_CONCRETE, ground)
			# Арматура из края плиты.
			for r in 6:
				var p := Vector3(b.position.x + wall + sx, fl + 0.12, b.position.z + wall + 0.3 + r * (sz - 0.6) / 5.0)
				var l := rng.randf_range(0.4, 1.1)
				var bend := Vector3(l * 0.7, rng.randf_range(-0.25, 0.1), rng.randf_range(-0.15, 0.15))
				_rebar(st, p, bend, b, ground)
		# Завалы: кучи обломков внутри у стен.
		for pile in 3:
			var center := b.position + Vector3(rng.randf_range(1.2, b.size.x - 1.2), 1.0, rng.randf_range(1.2, b.size.z - 1.2))
			for j in 7:
				var sz3 := Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.15, 0.5), rng.randf_range(0.3, 0.9))
				var p := center + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.15, 0.25), rng.randf_range(-1.0, 1.0))
				var xf := Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))), p)
				var surf2 := surf if rng.randf() < 0.6 else SURF_CONCRETE
				add_obox(st, _clamp_xf(xf, sz3, b), sz3, c * rng.randf_range(0.7, 0.95), surf2, ground)
		# Наклейки: копоть над проёмом и трещина (только на среднем и высоком).
		if quality >= 1:
			decals.append([b, ground, rng.randf(), rng.randf(), hs[0]])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = structure_material()
	mi.name = "Ruins"
	root.add_child(mi)
	for d in decals:
		_wall_decals(root, d[0], d[1], d[2], d[3], d[4])


## Стена вдоль axis длиной len, высотой h (от основания AABB), толщиной t, нормаль наружу — out.
## Проёмы окон 1,2×1,3 м через ~3 м на каждом этаже; верх обломан ступенями.
static func _wall(st: SurfaceTool, o: Vector3, axis: Vector3, len: float, h: float, t: float, ground: float,
		surf: int, c: Color, rng: RandomNumberGenerator, out: Vector3, side := false) -> void:
	if len < 0.6 or h < 0.6:
		return
	var thick := Vector3(t, 0, 0) if side else Vector3(0, 0, t)
	var n := int(floor((len - 1.4) / 3.0))
	var wins := []
	for i in n:
		var cx := (i + 0.5) * len / n
		wins.append(cx)
	var base := o.y
	var floor0 := ground - base   # высота пола от основания AABB (≈ 1 м — подземная часть)
	# Колонки: простенки между окнами, по всей высоте с обломанным верхом.
	# Профиль облома: плавная «волна» вдоль стены, глубина своя у каждой стены.
	var drop := rng.randf_range(0.3, 2.4)
	var ph := rng.randf() * TAU
	var fq := rng.randf_range(0.35, 0.8)
	var cuts := [0.0]
	for cx in wins:
		cuts.append(cx - 0.6)
		cuts.append(cx + 0.6)
	cuts.append(len)
	for i in range(0, cuts.size() - 1):
		var x0: float = cuts[i]
		var x1: float = cuts[i + 1]
		if x1 - x0 < 0.05:
			continue
		var is_win := i % 2 == 1
		# Обломанный верх: несколько ступеней разной высоты на отрезке.
		var steps := maxi(1, int((x1 - x0) / 0.9))
		for sidx in steps:
			var a := x0 + (x1 - x0) * sidx / steps
			var bb := x0 + (x1 - x0) * (sidx + 1) / steps
			var xm := (a + bb) * 0.5
			var top := clampf(h - drop * (0.5 + 0.5 * sin(xm * fq + ph)) * absf(sin(xm * fq * 0.37 + ph * 1.7)) - rng.randf_range(0.0, 0.15), 0.6, h)
			if not is_win:
				_box(st, _seg(o, axis, thick, a, bb, 0.0, top), c, surf, ground)
				continue
			# Под окнами и между этажами — подоконная часть и перемычки.
			var y := 0.0
			var fl := 0
			while y < top:
				var sill := floor0 + 0.9 + fl * 3.0
				var head := sill + 1.3
				if head > top - 0.25:
					_box(st, _seg(o, axis, thick, a, bb, y, top), c, surf, ground)
					break
				if sill > y:
					_box(st, _seg(o, axis, thick, a, bb, y, sill), c, surf, ground)
				y = head
				fl += 1
	# Пояс/карниз на высоте перекрытия — тоньше и чуть темнее (читается этажность).
	if h > 4.0 and surf != SURF_CONCRETE:
		var by := floor0 + 2.9
		_box(st, _seg(o - out * 0.0, axis, thick, 0.0, len, by, by + 0.22), c * 0.82, SURF_CONCRETE, ground)


static func _seg(o: Vector3, axis: Vector3, thick: Vector3, a: float, b: float, y0: float, y1: float) -> AABB:
	var p := o + axis * a + Vector3(0, y0, 0)
	var size := axis * (b - a) + thick + Vector3(0, y1 - y0, 0)
	return AABB(p, size).abs()


## Арматура: два отрезка тонкого прутка, обрезанные по AABB.
static func _rebar(st: SurfaceTool, p: Vector3, bend: Vector3, b: AABB, ground: float) -> void:
	var mid := p + bend * 0.6
	var tip := mid + bend * 0.4 + Vector3(0, -0.15, 0)
	for seg in [[p, mid], [mid, tip]]:
		var a: Vector3 = seg[0]
		var e: Vector3 = seg[1]
		e = e.clamp(b.position + Vector3.ONE * 0.05, b.end - Vector3.ONE * 0.05)
		var d := e - a
		if d.length() < 0.05:
			continue
		var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
		add_obox(st, Transform3D(basis, (a + e) * 0.5), Vector3(0.03, 0.03, d.length()), Color(0.4, 0.33, 0.28), SURF_RUST, ground)


## Обломок не выходит за AABB: центр подвигается внутрь с запасом на полудиагональ.
static func _clamp_xf(xf: Transform3D, size: Vector3, b: AABB) -> Transform3D:
	var r := size.length() * 0.5
	var lo := b.position + Vector3.ONE * r
	var hi := b.end - Vector3.ONE * r
	var o := xf.origin
	o = Vector3(clampf(o.x, lo.x, maxf(lo.x, hi.x)), clampf(o.y, lo.y, maxf(lo.y, hi.y)), clampf(o.z, lo.z, maxf(lo.z, hi.z)))
	return Transform3D(xf.basis, o)


## Вышка: четыре опоры, раскосы, площадка и бак сверху (металл, бетонный фундамент).
static func _tower(st: SurfaceTool, b: AABB, ground: float, rng: RandomNumberGenerator) -> void:
	var c := Color(0.45, 0.42, 0.40) * rng.randf_range(0.9, 1.1)
	var leg_h := b.size.y - 4.0
	for k in 4:
		var off := Vector3(0.0 if k % 2 == 0 else b.size.x - 0.3, 0, 0.0 if k < 2 else b.size.z - 0.3)
		_box(st, AABB(b.position + off, Vector3(0.3, leg_h, 0.3)), c, SURF_RUST, ground)
		_box(st, AABB(b.position + off - Vector3(0.0, 0, 0.0) + Vector3(-0.0, 0, 0), Vector3(0.3, 1.6, 0.3)).grow(0.0), c * 0.9, SURF_CONCRETE, ground)
	# Раскосы по граням: наклонные полосы внутри габарита.
	var lv := 4
	for i in lv:
		var y0 := 1.0 + i * (leg_h - 1.0) / lv
		var y1 := y0 + (leg_h - 1.0) / lv
		for face in 4:
			var a: Vector3
			var e: Vector3
			match face:
				0: a = Vector3(0.15, y0, 0.15); e = Vector3(b.size.x - 0.15, y1, 0.15)
				1: a = Vector3(0.15, y0, b.size.z - 0.15); e = Vector3(b.size.x - 0.15, y1, b.size.z - 0.15)
				2: a = Vector3(0.15, y0, 0.15); e = Vector3(0.15, y1, b.size.z - 0.15)
				_: a = Vector3(b.size.x - 0.15, y0, 0.15); e = Vector3(b.size.x - 0.15, y1, b.size.z - 0.15)
			var d := e - a
			var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
			add_obox(st, Transform3D(basis, b.position + (a + e) * 0.5), Vector3(0.08, 0.08, d.length()), c * 0.85, SURF_RUST, ground)
	var top := b.position + Vector3(0, leg_h, 0)
	_box(st, AABB(top, Vector3(b.size.x, 0.25, b.size.z)), c * 0.9, SURF_RUST, ground)
	_box(st, AABB(top + Vector3(0.2, 0.25, 0.2), Vector3(b.size.x - 0.4, 3.75, b.size.z - 0.4)), c * 1.05, SURF_RUST, ground)


static var _decal_tex := {}


## Копоть над окном и трещина на передней стене дома.
static func _wall_decals(root: Node3D, b: AABB, ground: float, r1: float, r2: float, h: float) -> void:
	if h < 2.0:
		return
	for kind in 2:
		var d := Decal.new()
		var w := 3.0 if kind == 0 else 2.2
		var hh := 3.5 if kind == 0 else 2.2
		d.size = Vector3(w, 1.2, hh)
		d.texture_albedo = _decal_texture(kind)
		d.albedo_mix = 1.0
		d.modulate = Color(0.08, 0.07, 0.06, 0.85) if kind == 0 else Color(0.15, 0.14, 0.13, 0.9)
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 120.0
		d.distance_fade_length = 30.0
		var x := b.position.x + clampf(b.size.x * (0.25 + r1 * 0.5), w * 0.5, b.size.x - w * 0.5)
		var y := clampf(ground + (2.4 if kind == 0 else 1.2 + r2 * 1.5), ground + 0.5, b.end.y - hh * 0.3)
		d.position = Vector3(x + (r2 - 0.5) * 2.0 * kind, y, b.position.z - 0.1)
		d.rotation = Vector3(-PI * 0.5, 0, 0)   # проекция −Y → +z: в переднюю стену снаружи
		root.add_child(d)


## Процедурные текстуры наклеек: 0 — языки копоти (вверх), 1 — ветвистая трещина.
static func _decal_texture(kind: int) -> Texture2D:
	if _decal_tex.has(kind):
		return _decal_tex[kind]
	var size := 256
	var data := PackedByteArray()
	data.resize(size * size * 4)
	if kind == 0:
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		n.seed = 5
		for y in size:
			for x in size:
				var u := (x - size * 0.5) / (size * 0.5)
				var v := float(y) / size   # 0 — верх, 1 — низ
				var plume := exp(-u * u / (0.08 + (1.0 - v) * 0.35)) * smoothstep(0.0, 0.35, v) * (1.0 - smoothstep(0.9, 1.0, v))
				var a := clampf(plume * (0.6 + n.get_noise_2d(x, y * 0.5) * 0.8), 0.0, 1.0)
				var o := (y * size + x) * 4
				data[o] = 255
				data[o + 1] = 255
				data[o + 2] = 255
				data[o + 3] = int(a * 255.0)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		FoliageBuilder._twig(data, size, rng, Vector2(128, 10), PI * 0.5 + rng.randf_range(-0.3, 0.3), 140.0, 2.5, 4)
		for i in size * size:
			data[i * 4] = 255
			data[i * 4 + 1] = 255
			data[i * 4 + 2] = 255
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_decal_tex[kind] = t
	return t


const STRUCTURE_SHADER := preload("res://shaders/structure.gdshader")
static var _structure_mats := {}


## Общий материал построек: слои библиотеки поверхностей (код в вершине), износ рёбер,
## грязь у земли, потёки, мох/снег сверху. Кэш по размеру текстур (уровню качества).
static func structure_material() -> ShaderMaterial:
	var size := SurfaceLib.size_for(_quality)
	if not _structure_mats.has(size):
		var m := ShaderMaterial.new()
		m.shader = STRUCTURE_SHADER
		m.set_shader_parameter("alb_arr", SurfaceLib.array(STRUCT_LAYERS, 0, size))
		m.set_shader_parameter("nrm_arr", SurfaceLib.array(STRUCT_LAYERS, 1, size))
		m.set_shader_parameter("orm_arr", SurfaceLib.array(STRUCT_LAYERS, 2, size))
		m.set_shader_parameter("noise_tex", SurfaceLib.noise_tex(0.03))
		var tiles := PackedFloat32Array()
		for k in STRUCT_LAYERS:
			tiles.append(1.0 / SurfaceLib.TILE[k])
		m.set_shader_parameter("tiles", tiles)
		_structure_mats[size] = m
	return _structure_mats[size]


## Погода на постройках (мох летом/осенью, снег зимой, мокрое в дождь) — общий материал на матч.
static func _structure_weather(preset: MapPreset) -> void:
	var m := structure_material()
	m.set_shader_parameter("snow", 1.0 if preset.biome == MapPreset.Biome.WINTER else 0.0)
	m.set_shader_parameter("moss", 0.0 if preset.biome == MapPreset.Biome.WINTER or preset.biome == MapPreset.Biome.STEPPE else 1.0)
	m.set_shader_parameter("wet", 1.0 if preset.precip == MapPreset.Precip.RAIN else 0.0)


## Коробка с гранями: UV — локальные метры грани (u — вдоль, v — вверх для боковых),
## UV2 — размер грани (для износа рёбер), CUSTOM0.x — уровень земли, альфа цвета — код поверхности.
static func _box(st: SurfaceTool, b: AABB, c: Color, surf := SURF_CONCRETE, ground := NAN) -> void:
	var p := b.position
	var s := b.size
	var v := [
		p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z),
		p + Vector3(0, s.y, 0), p + Vector3(s.x, s.y, 0), p + Vector3(s.x, s.y, s.z), p + Vector3(0, s.y, s.z)]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]
	_faces(st, v, faces, c, surf, p.y if is_nan(ground) else ground)


static func _faces(st: SurfaceTool, v: Array, faces: Array, c: Color, surf: int, ground: float) -> void:
	var col := Color(c.r, c.g, c.b, (surf + 0.5) / 8.0)
	var cust := Color(ground, 0, 0, 0)
	var center := Vector3.ZERO
	for p: Vector3 in v:
		center += p / v.size()
	for f: Array in faces:
		var a: Vector3 = v[f[0]]
		# Плоская нормаль грани: у прямоугольной коробки центр грани лежит на нормали от центра.
		var fc: Vector3 = (v[f[0]] + v[f[1]] + v[f[2]] + v[f[3]]) * 0.25
		var fn := (fc - center).normalized()
		var w := a.distance_to(v[f[1]])
		var h := a.distance_to(v[f[3]])
		var uvs := [Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_custom(0, cust)
			st.set_uv(uvs[idx])
			st.set_uv2(Vector2(w, h))
			st.set_normal(fn)
			st.add_vertex(v[f[idx]])


## Публичный помощник для других построек.
static func add_box(st: SurfaceTool, b: AABB, c: Color, surf := SURF_CONCRETE, ground := NAN) -> void:
	_box(st, b, c, surf, ground)


## Повёрнутая коробка: центр и базис в xf, размеры size.
static func add_obox(st: SurfaceTool, xf: Transform3D, size: Vector3, c: Color, surf := SURF_CONCRETE, ground := 0.0) -> void:
	var h := size * 0.5
	var v := []
	for k in 8:
		var p := Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z)
		v.append(xf * p)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	_faces(st, v, faces, c, surf, ground)
