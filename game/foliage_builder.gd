class_name FoliageBuilder
## Растительность и мелочь: деревья (ствол с корой + карточки веток с процедурной альфой,
## по 3 варианта на тип, дальний низкополигональный LOD), трава вокруг камеры (GPU, MultiMesh),
## камни, кусты и валежник (MultiMesh-чанки с visibility_range).
##
## Хитбоксы не меняются: крона и ствол дерева строго внутри цилиндра Terrain.trees (x, z, r, top) —
## сетка нормирована (высота 1, радиус ≤ CROWN_R), экземпляр масштабируется (r, высота, r).
## Декорация без коллизий — ниже DECOR_MAX_H, расставляется своим RNG от сида карты (не sim/).

const TREE_SHADER := preload("res://shaders/tree.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const CROWN_R := 0.85          # радиус кроны в долях радиуса коллизии (запас под покачивание)
const DECOR_MAX_H := 0.6
const VARIANTS := 3
const LOD_DIST := 120.0        # ближе — карточки, дальше — низкополигональный силуэт

static var _cards := {}
static var _meshes := {}


static func build(terrain: Terrain, root: Node3D, quality: int) -> void:
	_trees(terrain, root, quality)
	if quality >= 1:
		_decor(terrain, root, quality)
		_grass(terrain, root, quality)
	var drv := Driver.new()
	drv.preset = terrain.preset
	drv.terrain = terrain
	drv.name = "FoliageDriver"
	root.add_child(drv)


## Обновляет глобальные параметры шейдеров: центр вида (камера) и ветер (sim/wind.gd, только чтение).
class Driver extends Node:
	var preset: MapPreset
	var terrain: Terrain
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var p := cam.global_position
		RenderingServer.global_shader_parameter_set("view_center", p)
		var g := terrain.height_at(p.x, p.z)
		var w := Wind.at(Vector3(p.x, g + 2.0, p.z), _t, preset, g)
		RenderingServer.global_shader_parameter_set("wind_vec", w)


# ---------------- Текстуры карточек ----------------

## Процедурная альфа-текстура карточки: 0 — хвойная лапа, 1 — гроздь листьев, 2 — сухие ветки.
## RGB — относительная яркость (оттенок даёт экземпляр), A — покрытие.
static func card_texture(kind: int) -> Texture2D:
	if _cards.has(kind):
		return _cards[kind]
	var size := 256
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + kind
	match kind:
		0:
			# Лапа: изогнутая ось слева направо, хвоинки вперёд-в-стороны, боковые веточки.
			var pts := []
			for i in 40:
				var t := i / 39.0
				pts.append(Vector2(4 + t * 246, 128 + sin(t * 2.2) * 10.0 - t * 8.0))
			for i in 39:
				_line(data, size, pts[i], pts[i + 1], 3.0 - i * 0.05, 0.32)
			for k in 7:
				var a: Vector2 = pts[6 + k * 4]
				var side := 1.0 if k % 2 == 0 else -1.0
				var tip := a + Vector2(60 - k * 5, side * (55 - k * 4))
				_line(data, size, a, tip, 1.6, 0.36)
				for j in 18:
					var q := a.lerp(tip, j / 18.0)
					for sd in [-1.0, 1.0]:
						var d := (tip - a).normalized().rotated(sd * rng.randf_range(0.6, 1.0))
						_line(data, size, q, q + d * rng.randf_range(8, 15), 1.3, rng.randf_range(0.42, 0.62))
			for j in 70:
				var q: Vector2 = pts[mini(int(j * 0.55), 39)]
				for sd in [-1.0, 1.0]:
					var d := Vector2(1, 0).rotated(sd * rng.randf_range(0.5, 1.1))
					_line(data, size, q, q + d * rng.randf_range(10, 20), 1.4, rng.randf_range(0.4, 0.6))
		1:
			# Гроздь листьев: эллипсы с прожилкой, гуще к центру.
			for k in 14:
				var a := Vector2(128, 128)
				var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40, 110)
				_line(data, size, a, b, 1.6, 0.3)
			for i in 260:
				var c := Vector2(128, 128) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 108.0
				_leaf(data, size, c, rng.randf() * TAU, rng.randf_range(9, 14), rng.randf_range(4, 6.5), rng.randf_range(0.38, 0.66))
		_:
			# Сухие ветки: ветвление от нижнего края.
			_twig(data, size, rng, Vector2(128, 250), -PI * 0.5, 120.0, 4.0, 5)
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cards[kind] = tex
	return tex


static func _plot(data: PackedByteArray, size: int, x: int, y: int, v: float, a: float) -> void:
	if x < 0 or y < 0 or x >= size or y >= size:
		return
	var o := (y * size + x) * 4
	var na := maxf(data[o + 3] / 255.0, a)
	if a >= data[o + 3] / 255.0:
		var c := int(clampf(v, 0.0, 1.0) * 255.0)
		data[o] = c
		data[o + 1] = c
		data[o + 2] = c
	data[o + 3] = int(na * 255.0)


static func _line(data: PackedByteArray, size: int, a: Vector2, b: Vector2, w: float, v: float) -> void:
	var n := int(maxf(a.distance_to(b), 1.0))
	var r := int(ceil(w * 0.5))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d := Vector2(dx, dy).length()
				if d <= w * 0.5:
					_plot(data, size, int(p.x) + dx, int(p.y) + dy, v * (0.9 + 0.2 * float(i) / n), clampf(w * 0.5 - d + 0.5, 0.0, 1.0))


static func _leaf(data: PackedByteArray, size: int, c: Vector2, ang: float, l: float, w: float, v: float) -> void:
	var r := int(l) + 1
	var ax := Vector2.from_angle(ang)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := Vector2(dx, dy)
			var u := p.dot(ax) / l
			var s := p.dot(ax.orthogonal()) / w
			var e := u * u + s * s
			if e <= 1.0:
				var shade := v * (0.85 + 0.25 * (1.0 - absf(s))) * (0.9 + 0.1 * u)
				_plot(data, size, int(c.x) + dx, int(c.y) + dy, shade, clampf((1.0 - e) * 4.0, 0.0, 1.0))


static func _twig(data: PackedByteArray, size: int, rng: RandomNumberGenerator, a: Vector2, ang: float, l: float, w: float, depth: int) -> void:
	var b := a + Vector2.from_angle(ang) * l
	_line(data, size, a, b, w, 0.42 + rng.randf() * 0.1)
	if depth <= 0:
		return
	for k in 2 + int(rng.randf() < 0.4):
		var t := rng.randf_range(0.45, 0.95)
		_twig(data, size, rng, a.lerp(b, t), ang + rng.randf_range(-0.8, 0.8), l * rng.randf_range(0.4, 0.65), maxf(w * 0.65, 1.0), depth - 1)


# ---------------- Сетки деревьев ----------------

## Ближняя сетка дерева: поверхность 0 — ствол/ветви (кора), 1 — карточки (альфа).
## Нормирована: основание y=0, верх ≤ 1, радиус ≤ CROWN_R (в долях радиуса коллизии).
static func tree_mesh_near(kind: int, variant: int) -> ArrayMesh:
	var key := "n%d_%d" % [kind, variant]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind * 31 + variant * 7
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := SurfaceTool.new()
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		MapPreset.TreeKind.LEAFY:
			var top_y := rng.randf_range(0.34, 0.42)
			_tube(bark, Vector3.ZERO, Vector3(rng.randf_range(-0.04, 0.04), top_y, rng.randf_range(-0.04, 0.04)), 0.09, 0.055, 8)
			var cy := rng.randf_range(0.64, 0.68)
			var clumps := []
			for i in 16:
				var a := rng.randf() * TAU
				var cr := rng.randf_range(0.2, 0.3)
				var rr := sqrt(rng.randf()) * (CROWN_R - cr)
				var c := Vector3(cos(a) * rr, cy + rng.randf_range(-0.28, 0.26), sin(a) * rr)
				c.y = clampf(c.y, top_y + 0.05, 1.0 - cr * 0.6)
				clumps.append(Vector4(c.x, c.y, c.z, cr))
				if i < 6:
					_tube(bark, Vector3(0, top_y * rng.randf_range(0.7, 1.0), 0), c * Vector3(0.8, 1, 0.8), 0.04, 0.015, 5)
			for cl: Vector4 in clumps:
				_clump(leaf, rng, Vector3(cl.x, cl.y, cl.z), cl.w, Vector3(0, cy, 0))
		MapPreset.TreeKind.DEAD:
			_tube(bark, Vector3.ZERO, Vector3(rng.randf_range(-0.03, 0.03), 0.98, rng.randf_range(-0.03, 0.03)), 0.08, 0.012, 7)
			for i in 7:
				var y := rng.randf_range(0.3, 0.85)
				var a := rng.randf() * TAU
				var len := rng.randf_range(0.45, 0.78) * (1.1 - y * 0.4)
				var tip := Vector3(cos(a) * len, y + rng.randf_range(0.08, 0.2), sin(a) * len)
				_tube(bark, Vector3(0, y, 0), tip, 0.035 * (1.0 - y * 0.5), 0.008, 5)
				_card(leaf, Vector3(0, y, 0).lerp(tip, 0.45), tip + (tip - Vector3(0, y, 0)) * 0.15, 0.32, Vector3(0, 0.6, 0), Color(1, 1, 1, 1))
		_:
			_tube(bark, Vector3.ZERO, Vector3(0, 0.99, 0), 0.075, 0.015, 8)
			var y := 0.1
			var whorl := 0
			while y < 0.96:
				var rr := CROWN_R * pow(clampf(1.0 - (y - 0.06) / 0.95, 0.0, 1.0), 0.95) * rng.randf_range(0.85, 1.0)
				var n := 6 if y < 0.75 else 4
				var a0 := rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n + rng.randf_range(-0.25, 0.25)
					var droop := rr * rng.randf_range(0.25, 0.45)
					var tip := Vector3(cos(a) * rr, y - droop, sin(a) * rr)
					var shade := 0.72 + 0.4 * y
					_card(leaf, Vector3(0, y, 0), tip, rr * 0.55 + 0.03, Vector3(0, 0.55, 0), Color(shade, shade, shade, 1))
				y += rng.randf_range(0.055, 0.075)
				whorl += 1
			# Макушка: две скрещенные карточки.
			_card(leaf, Vector3(0, 0.88, 0), Vector3(0, 1.0, 0.0), 0.08, Vector3(0, 0.9, 0), Color(1.1, 1.1, 1.1, 1))
	var mesh := ArrayMesh.new()
	bark.generate_normals()
	bark.generate_tangents()
	bark.commit(mesh)
	leaf.commit(mesh)
	_meshes[key] = mesh
	return mesh


## Дальняя сетка: прежний низкополигональный силуэт, нормированный в тот же цилиндр.
static func tree_mesh_far(kind: int) -> ArrayMesh:
	var key := "f%d" % kind
	if _meshes.has(key):
		return _meshes[key]
	var src := WorldBuilder.tree_mesh(kind)
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var maxr := 0.01
	for v in verts:
		maxr = maxf(maxr, Vector2(v.x, v.z).length())
	var k := CROWN_R / maxr
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3(v.x * k, clampf(v.y / 7.0, 0.0, 1.0), v.z * k)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Труба (ствол/ветвь) от a до b, радиусы r0 → r1. UV: u — по окружности, v — вдоль (для коры).
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, seg: int) -> void:
	var ax := (b - a).normalized()
	var side := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(ax).normalized()
	var len := a.distance_to(b)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var p := [a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1]
		var uv := [Vector2(float(i) / seg, 0), Vector2(float(i + 1) / seg, 0), Vector2(float(i + 1) / seg, len * 6.0), Vector2(float(i) / seg, len * 6.0)]
		st.set_color(Color(1, 1, 1, 0))
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[idx])
			st.add_vertex(p[idx])


## Карточка ветки от основания a к концу b шириной w: две скрещенные плоскости.
## Нормали «раздуты» от оси кроны (center) — объёмный, мягкий свет без плоских граней.
static func _card(st: SurfaceTool, a: Vector3, b: Vector3, w: float, center: Vector3, col: Color) -> void:
	var ax := b - a
	var flat := ax.cross(Vector3.UP).normalized()
	if flat.length() < 0.1:
		flat = Vector3.RIGHT
	var tilt := ax.cross(flat).normalized()
	for side in [flat, (flat * 0.5 + tilt * 0.87).normalized()]:
		var s: Vector3 = side * w * 0.5
		var p := [a - s, a + s, b + s, b - s]
		var uv := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
		st.set_color(col)
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = p[idx]
			st.set_normal(((v - center) * Vector3(1, 0.6, 1) + Vector3(0, 0.35, 0)).normalized())
			st.set_uv(uv[idx])
			st.add_vertex(v)


## Гроздь листвы: 4 карточки, повёрнутые случайно вокруг центра c, радиус cr.
static func _clump(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, cr: float, center: Vector3) -> void:
	for k in 4:
		var ax := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		var up := ax.cross(Vector3(0, 1, 0.2)).normalized()
		var s1 := ax * cr
		var s2 := up * cr
		var p := [c - s1 - s2, c + s1 - s2, c + s1 + s2, c - s1 + s2]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var shade := 0.8 + (c.y - center.y) * 0.8 + rng.randf_range(-0.05, 0.05)
		st.set_color(Color(shade, shade, shade, 1))
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = p[idx]
			st.set_normal(((v - center) * Vector3(1, 1.2, 1) + Vector3(0, 0.2, 0)).normalized())
			st.set_uv(uv[idx])
			st.add_vertex(v)


static func tree_kind_for(preset: MapPreset) -> int:
	var kind := preset.tree_kind
	if kind == MapPreset.TreeKind.LEAFY and preset.biome == MapPreset.Biome.WINTER:
		kind = MapPreset.TreeKind.DEAD   # зимой лиственные стоят голые
	return kind


## Масштаб и положение экземпляра: основание чуть в земле, верх ровно на высоте коллизии.
static func tree_transform(terrain: Terrain, t: Vector4, yaw: float) -> Transform3D:
	var g := terrain.height_at(t.x, t.y) - 0.3
	var h := t.w - g
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(t.z, h, t.z))
	return Transform3D(b, Vector3(t.x, g, t.y))


static func _tree_materials(preset: MapPreset, kind: int, quality: int) -> Array:
	var pal := WorldBuilder.palette(preset.biome)
	var size := SurfaceLib.size_for(quality)
	var trunk := Color(0.30, 0.22, 0.16) if kind != MapPreset.TreeKind.DEAD else Color(0.36, 0.32, 0.28)
	if kind == MapPreset.TreeKind.SPRUCE:
		trunk = Color(0.32, 0.25, 0.20)
	var mats := []
	for part in 3:   # 0 кора, 1 карточки, 2 дальний силуэт
		var m := ShaderMaterial.new()
		m.shader = TREE_SHADER
		m.set_shader_parameter("trunk_color", Vector3(trunk.r, trunk.g, trunk.b))
		m.set_shader_parameter("wind_dir", Vector2(cos(preset.wind_dir), sin(preset.wind_dir)))
		m.set_shader_parameter("sway", 0.06 + preset.wind_base * 0.06)
		m.set_shader_parameter("bark_alb", SurfaceLib.texture(SurfaceLib.BARK, 0, size))
		m.set_shader_parameter("bark_nrm", SurfaceLib.texture(SurfaceLib.BARK, 1, size))
		m.set_shader_parameter("card_tex", card_texture(kind))
		m.set_shader_parameter("part", part)
		m.set_shader_parameter("lod_dist", LOD_DIST if quality >= 1 else -1.0)
		m.set_shader_parameter("snow", 1.0 if preset.biome == MapPreset.Biome.WINTER else 0.0)
		m.set_shader_parameter("snow_color", Vector3(pal.snow.r, pal.snow.g, pal.snow.b))
		mats.append(m)
	return mats


static func _trees(terrain: Terrain, root: Node3D, quality: int) -> void:
	var preset := terrain.preset
	var pal := WorldBuilder.palette(preset.biome)
	var kind := tree_kind_for(preset)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed + 3
	var leafy: Array = pal.leafy
	var n := terrain.trees.size()
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var vars: Array[int] = []
	for i in n:
		var t := terrain.trees[i]
		xf.append(tree_transform(terrain, t, rng.randf() * TAU))
		var tint := rng.randf_range(0.82, 1.18)
		var crown: Color = pal.spruce if preset.tree_kind == MapPreset.TreeKind.SPRUCE else leafy[rng.randi() % leafy.size()]
		crown = Color(crown.r * tint, crown.g * tint * rng.randf_range(0.95, 1.06), crown.b * tint, rng.randf())
		if kind == MapPreset.TreeKind.DEAD:   # сухие веточки — цвета коры, не листвы
			crown = Color(0.36 * tint, 0.31 * tint, 0.26 * tint, crown.a)
		cols.append(crown)
		vars.append(int(absf(t.x * 13.0 + t.y * 7.0)) % VARIANTS)
	var mats := _tree_materials(preset, kind, quality)
	# Дальний силуэт — все деревья одним MultiMesh (на низком качестве — единственный вид).
	var far := MultiMesh.new()
	far.transform_format = MultiMesh.TRANSFORM_3D
	far.use_custom_data = true
	far.mesh = tree_mesh_far(kind)
	far.instance_count = n
	for i in n:
		far.set_instance_transform(i, xf[i])
		far.set_instance_custom_data(i, cols[i])
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = far
	fmi.material_override = mats[2]
	fmi.name = "ForestFar"
	root.add_child(fmi)
	if quality < 1:
		return
	# Ближние карточные деревья: по MultiMesh на вариант. Дальше LOD_DIST вершины схлопываются в шейдере.
	for v in VARIANTS:
		var idx := []
		for i in n:
			if vars[i] == v:
				idx.append(i)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var mesh := tree_mesh_near(kind, v).duplicate() as ArrayMesh
		mesh.surface_set_material(0, mats[0])
		mesh.surface_set_material(1, mats[1])
		mm.mesh = mesh
		mm.instance_count = idx.size()
		for j in idx.size():
			mm.set_instance_transform(j, xf[idx[j]])
			mm.set_instance_custom_data(j, cols[idx[j]])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = "Forest%d" % v
		root.add_child(mi)


# ---------------- Трава ----------------

## Текстуры для травы: высоты сетки (RF) и маска (R — тропа, G — плотность травы).
static func ground_maps(terrain: Terrain) -> Array:
	var n := Terrain.N
	var hb := PackedByteArray()
	hb.resize(n * n * 4)
	for i in n * n:
		hb.encode_float(i * 4, terrain.heights[i])
	var himg := Image.create_from_data(n, n, false, Image.FORMAT_RF, hb)
	var path: PackedFloat32Array = terrain.get_meta("path_mask", PackedFloat32Array())
	var preset := terrain.preset
	var md := PackedByteArray()
	md.resize(n * n * 4)
	var pal := WorldBuilder.palette(preset.biome)
	for zi in n:
		for xi in n:
			var i := zi * n + xi
			var x := -SimConst.MAP_HALF + xi * Terrain.CELL
			var z := -SimConst.MAP_HALF + zi * Terrain.CELL
			var nrm := terrain.normal_at(x, z)
			var road := path[i] if path.size() == n * n else 0.0
			var dens := smoothstep(0.32, 0.18, 1.0 - nrm.y) * (1.0 - smoothstep(0.25, 0.6, road))
			if terrain.heights[i] > pal.snow_lo + preset.base_lift:
				dens *= 0.15
			md[i * 4] = int(clampf(road, 0.0, 1.0) * 255.0)
			md[i * 4 + 1] = int(clampf(dens, 0.0, 1.0) * 255.0)
			md[i * 4 + 3] = 255
	var mimg := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, md)
	return [ImageTexture.create_from_image(himg), ImageTexture.create_from_image(mimg)]


## Пучок травы: 9 изогнутых травинок (по 3 треугольника), высота 1 (масштаб — в шейдере).
static func grass_tuft() -> ArrayMesh:
	if _meshes.has("grass"):
		return _meshes.grass
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in 9:
		var a := TAU * b / 9.0 + rng.randf_range(-0.4, 0.4)
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.03, 0.22)
		var lean := Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * rng.randf_range(0.1, 0.35)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.03
		var h := rng.randf_range(0.7, 1.0)
		var p0 := base - side
		var p1 := base + side
		var m0 := base + lean * 0.35 + Vector3(0, h * 0.55, 0) - side * 0.7
		var m1 := base + lean * 0.35 + Vector3(0, h * 0.55, 0) + side * 0.7
		var tip := base + lean + Vector3(0, h, 0)
		var nrm := Vector3(cos(a), 0.8, sin(a)).normalized()
		for tri in [[p0, p1, m1], [p0, m1, m0], [m0, m1, tip]]:
			for v: Vector3 in tri:
				st.set_normal(nrm)
				st.set_color(Color(1, 1, 1, v.y))
				st.add_vertex(v)
	var mesh := st.commit()
	_meshes.grass = mesh
	return mesh


static func _grass(terrain: Terrain, root: Node3D, quality: int) -> void:
	var preset := terrain.preset
	var pal := WorldBuilder.palette(preset.biome)
	var maps := ground_maps(terrain)
	var n := 130 if quality == 1 else 180
	var spacing := 0.26 if quality == 1 else 0.24
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = grass_tuft()
	mm.instance_count = n * n
	# Положения считает шейдер (по INSTANCE_ID и центру вида) — преобразования единичные.
	var buf := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0])
	while buf.size() < n * n * 12:
		buf.append_array(buf.slice(0, mini(buf.size(), n * n * 12 - buf.size())))
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1500, 4000))   # отсечение не по единичным матрицам
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1500, 4000))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	m.set_shader_parameter("heights", maps[0])
	m.set_shader_parameter("mask", maps[1])
	m.set_shader_parameter("grid_n", n)
	m.set_shader_parameter("spacing", spacing)
	m.set_shader_parameter("map_half", SimConst.MAP_HALF)
	m.set_shader_parameter("cell", Terrain.CELL)
	var winter := preset.biome == MapPreset.Biome.WINTER
	var dry := preset.biome == MapPreset.Biome.STEPPE or preset.biome == MapPreset.Biome.AUTUMN or winter
	var ga: Color = pal.grass_a
	var gb: Color = pal.grass_b
	if winter:
		ga = Color(0.42, 0.38, 0.28)
		gb = Color(0.55, 0.50, 0.36)
	m.set_shader_parameter("color_a", Vector3(ga.r, ga.g, ga.b))
	m.set_shader_parameter("color_b", Vector3(gb.r, gb.g, gb.b))
	m.set_shader_parameter("dry", 0.6 if dry else 0.15)
	m.set_shader_parameter("blade_h", 0.3 if not winter else 0.24)
	m.set_shader_parameter("macro_noise", SurfaceLib.noise_tex(0.008))
	mi.material_override = m
	mi.name = "Grass"
	root.add_child(mi)


# ---------------- Камни, кусты, валежник ----------------

## Высота видимой земли (как в треугольниках сетки, а не билинейно) — мелочь не висит в воздухе.
static func mesh_height(terrain: Terrain, x: float, z: float) -> float:
	var n := Terrain.N
	var fx := clampf((x + SimConst.MAP_HALF) / Terrain.CELL, 0.0, n - 1.001)
	var fz := clampf((z + SimConst.MAP_HALF) / Terrain.CELL, 0.0, n - 1.001)
	var xi := int(fx)
	var zi := int(fz)
	var tx := fx - xi
	var tz := fz - zi
	var i := zi * n + xi
	var h := terrain.heights
	if tx + tz <= 1.0:
		return h[i] + (h[i + 1] - h[i]) * tx + (h[i + n] - h[i]) * tz
	return h[i + n + 1] + (h[i + n] - h[i + n + 1]) * (1.0 - tx) + (h[i + 1] - h[i + n + 1]) * (1.0 - tz)


static func rock_mesh(variant: int) -> ArrayMesh:
	var key := "rock%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var sm := SphereMesh.new()
	sm.radial_segments = 10
	sm.rings = 6
	sm.radius = 0.5
	sm.height = 1.0
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 31 + variant
	noise.frequency = 1.6
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v * 2.0) * 0.35
		v *= k
		v.y = v.y * 0.6 if v.y > 0.0 else v.y * 0.3   # приплюснут, низ уходит в землю
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


static func bush_mesh() -> ArrayMesh:
	if _meshes.has("bush"):
		return _meshes.bush
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	for i in 5:
		var c := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.2, 0.32), rng.randf_range(-0.25, 0.25))
		_clump(st, rng, c, 0.24, Vector3(0, 0.15, 0))
	var mesh := st.commit()
	_meshes.bush = mesh
	return mesh


static func log_mesh() -> ArrayMesh:
	if _meshes.has("log"):
		return _meshes.log
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, Vector3(-1.2, 0.12, 0), Vector3(1.2, 0.1, 0), 0.13, 0.09, 7)
	_tube(st, Vector3(0.3, 0.12, 0), Vector3(0.8, 0.22, 0.45), 0.04, 0.015, 4)
	st.generate_normals()
	var mesh := st.commit()
	_meshes.log = mesh
	return mesh


## Материал мелочи из библиотеки поверхностей (ORM: AO/шероховатость/металл).
static func surface_material(kind: int, tint: Color, quality: int, triplanar := true) -> ORMMaterial3D:
	var size := SurfaceLib.size_for(quality)
	var m := ORMMaterial3D.new()
	m.albedo_texture = SurfaceLib.texture(kind, 0, size)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = SurfaceLib.texture(kind, 1, size)
	m.normal_scale = 1.0
	m.orm_texture = SurfaceLib.texture(kind, 2, size)
	m.uv1_triplanar = triplanar
	m.uv1_world_triplanar = triplanar
	m.uv1_scale = Vector3.ONE * (1.0 / SurfaceLib.TILE[kind])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _decor(terrain: Terrain, root: Node3D, quality: int) -> void:
	var preset := terrain.preset
	var pal := WorldBuilder.palette(preset.biome)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed * 7 + 101   # свой генератор: на карту и симуляцию не влияет
	var k := 1.0 if quality == 1 else 1.6
	var winter := preset.biome == MapPreset.Biome.WINTER
	var chunks := 8
	var csize := SimConst.MAP_HALF * 2.0 / chunks
	var buckets := {}   # (вид, чанк) -> Array[Transform3D]
	var specs := [
		["rock", int(1800 * k), 0.5],
		["bush", int((600 if winter else 1300) * k), 0.0],
		["log", int(260 * k), 0.0],
	]
	for spec in specs:
		var kind: String = spec[0]
		var placed := 0
		var tries := 0
		while placed < spec[1] and tries < spec[1] * 6:
			tries += 1
			var x := rng.randf_range(-SimConst.MAP_HALF + 10, SimConst.MAP_HALF - 10)
			var z := rng.randf_range(-SimConst.MAP_HALF + 10, SimConst.MAP_HALF - 10)
			var nrm := terrain.normal_at(x, z)
			var slope := 1.0 - nrm.y
			if kind == "rock" and rng.randf() > 0.25 + slope * 3.0:
				continue
			if kind != "rock" and slope > 0.2:
				continue
			if _blocked(terrain, x, z, 1.5 if kind != "log" else 2.5):
				continue
			var y := mesh_height(terrain, x, z)
			var yaw := rng.randf() * TAU
			var b: Basis
			match kind:
				"rock":
					var s := rng.randf_range(0.25, 1.1)
					# Верх сетки камня ≈ 0,41 × масштаб по y: при s ≤ 1,1 — ниже DECOR_MAX_H.
					b = Basis(Vector3.UP, yaw).scaled(Vector3(s * rng.randf_range(0.8, 1.4), s * rng.randf_range(0.6, 1.0), s))
					y -= 0.05 * s
				"bush":
					var s := rng.randf_range(0.8, 1.05)
					b = Basis(Vector3.UP, yaw).scaled(Vector3(s * 1.3, s, s * 1.3))
				_:
					var s := rng.randf_range(0.7, 1.2)
					b = Basis(Vector3.UP, yaw).scaled(Vector3(s, 1.0, s))
			var ci := clampi(int((x + SimConst.MAP_HALF) / csize), 0, chunks - 1)
			var cj := clampi(int((z + SimConst.MAP_HALF) / csize), 0, chunks - 1)
			var key := "%s_%d" % [kind, ci * chunks + cj]
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(Transform3D(b, Vector3(x, y, z)))
			placed += 1
	var rock_tint: Color = pal.rock * 2.0
	var mats := {
		"rock": surface_material(SurfaceLib.ROCK, Color(rock_tint.r, rock_tint.g, rock_tint.b), quality),
		"log": surface_material(SurfaceLib.BARK, Color(0.62, 0.54, 0.46) if not winter else Color(0.6, 0.58, 0.56), quality, false),
	}
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = card_texture(1)
	var bush_col: Color = pal.spruce.lerp(pal.grass_a, 0.5) * 2.0
	if winter:
		bm.albedo_texture = card_texture(2)
		bush_col = Color(0.75, 0.62, 0.5)
	bm.albedo_color = Color(bush_col.r, bush_col.g, bush_col.b)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bm.alpha_scissor_threshold = 0.4
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.roughness = 0.85
	bm.backlight_enabled = true
	bm.backlight = Color(0.25, 0.3, 0.15)
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["bush"] = bm
	var ranges := {"rock": 170.0, "bush": 190.0, "log": 150.0}
	for key: String in buckets:
		var kind := key.get_slice("_", 0)
		var list: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		match kind:
			"rock": mm.mesh = rock_mesh(int(key.get_slice("_", 1)) % 3)
			"bush": mm.mesh = bush_mesh()
			_: mm.mesh = log_mesh()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mats[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Видимость чанка — по расстоянию до его центра: запас на полчанка.
		mi.visibility_range_end = ranges[kind] + csize * 0.5
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.name = "Decor_" + key
		root.add_child(mi)


static func _blocked(terrain: Terrain, x: float, z: float, pad: float) -> bool:
	for sp in terrain.shelters:
		if Vector2(sp.x - x, sp.z - z).length() < 22.0:
			return true
	# Деревья и постройки — через пространственный индекс симуляции (только чтение).
	return terrain.obstacle_top(x, z, pad) > -INF
