class_name WorldBuilder
## Строит видимый мир по Terrain: землю, лес, руины, небо, свет и туман.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")


static func build(terrain: Terrain, root: Node3D, quality: int) -> void:
	_environment(root, quality)
	_ground(terrain, root)
	_trees(terrain, root)
	_ruins(terrain, root)


static func _environment(root: Node3D, quality: int) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.45, 0.58)
	sky_mat.sky_horizon_color = Color(0.70, 0.70, 0.66)
	sky_mat.ground_horizon_color = Color(0.55, 0.55, 0.50)
	sky_mat.ground_bottom_color = Color(0.25, 0.25, 0.22)
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.64, 0.62)
	env.fog_density = 0.0008
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.12
	if quality >= 2:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.003
		env.volumetric_fog_albedo = Color(0.85, 0.85, 0.8)
		env.volumetric_fog_length = 220.0
		env.volumetric_fog_anisotropy = 0.6
		env.ssao_enabled = true
		env.ssao_radius = 1.5
	if quality >= 1:
		env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.6
	sun.shadow_enabled = quality >= 1
	sun.directional_shadow_max_distance = 260.0 if quality >= 2 else 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_volumetric_fog_energy = 1.4
	root.add_child(sun)


static func _noise_tex(freq: float, seamless := true) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = seamless
	t.generate_mipmaps = true
	return t


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
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("detail_noise", _noise_tex(0.02))
	mat.set_shader_parameter("macro_noise", _noise_tex(0.008))
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
	fm.albedo_color = Color(0.30, 0.33, 0.22)
	fm.roughness = 1.0
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	far.material_override = fm
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far)


static func tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.28, 0.20, 0.14)
	_cone(st, Vector3(0, 0, 0), 0.25, 0.18, 2.2, 6, trunk)
	var greens := [Color(0.14, 0.24, 0.13), Color(0.17, 0.28, 0.14), Color(0.20, 0.31, 0.16)]
	_cone(st, Vector3(0, 1.4, 0), 1.6, 0.0, 3.6, 7, greens[0])
	_cone(st, Vector3(0, 3.0, 0), 1.25, 0.0, 3.0, 7, greens[1])
	_cone(st, Vector3(0, 4.4, 0), 0.9, 0.0, 2.4, 7, greens[2])
	st.generate_normals()
	return st.commit()


static func _cone(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, seg: int, c: Color) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		st.set_color(c * 0.85)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.set_color(c)
		st.add_vertex(q0)
		if r1 > 0.0:
			st.add_vertex(q0)
			st.set_color(c * 0.85)
			st.add_vertex(p1)
			st.set_color(c)
			st.add_vertex(q1)
		# днище
		st.set_color(c * 0.5)
		st.add_vertex(base)
		st.add_vertex(p1)
		st.add_vertex(p0)


static func _trees(terrain: Terrain, root: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tree_mesh()
	mm.instance_count = terrain.trees.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed + 3
	for i in terrain.trees.size():
		var t := terrain.trees[i]
		var g := terrain.height_at(t.x, t.y)
		var h := t.w - g
		var s := h / 7.0
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * (t.z / 2.0) * 1.1, s, s * (t.z / 2.0) * 1.1))
		mm.set_instance_transform(i, Transform3D(b, Vector3(t.x, g - 0.3, t.y)))
		var tint := rng.randf_range(0.8, 1.2)
		mm.set_instance_color(i, Color(tint, tint * rng.randf_range(0.95, 1.08), tint))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
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
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	mi.name = "Ruins"
	root.add_child(mi)


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
