class_name Terrain
extends RefCounted
## Процедурная долина: карта высот, лес (цилиндры), руины (коробки), кольцо укрытий.
## Генерируется из сида одинаково на сервере и в клиенте.

const N := 161                                   # узлов по стороне
const CELL := SimConst.MAP_HALF * 2.0 / (N - 1)  # 7,5 м
const GRID := 40.0                               # ячейка пространственного индекса

var seed := 0
var heights := PackedFloat32Array()
var trees: Array[Vector4] = []      # x, z, радиус, высота верхушки (абсолютная)
var boxes: Array[AABB] = []         # руины и постройки
var shelters: Array[Vector3] = []   # 8 точек на кольце (на земле)
var _tree_grid := {}
var _box_grid := {}


func generate(p_seed: int) -> void:
	seed = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var hills := FastNoiseLite.new()
	hills.seed = p_seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.0042
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 4
	var ridges := FastNoiseLite.new()
	ridges.seed = p_seed + 17
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.frequency = 0.0021
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3

	# Укрытия по кольцу с небольшим сдвигом от сида.
	shelters.clear()
	var a0 := rng.randf() * TAU
	for i in SimConst.MAX_PLAYERS:
		var a := a0 + TAU * i / SimConst.MAX_PLAYERS + rng.randf_range(-0.08, 0.08)
		var r := SimConst.SHELTER_RING + rng.randf_range(-25.0, 25.0)
		shelters.append(Vector3(cos(a) * r, 0.0, sin(a) * r))

	heights.resize(N * N)
	for zi in N:
		for xi in N:
			var x := -SimConst.MAP_HALF + xi * CELL
			var z := -SimConst.MAP_HALF + zi * CELL
			heights[zi * N + xi] = _raw_height(x, z, hills, ridges)
	# Площадки под укрытия: выравниваем землю.
	for si in shelters.size():
		var s := shelters[si]
		var base := _raw_height(s.x, s.z, hills, ridges)
		for zi in N:
			for xi in N:
				var x := -SimConst.MAP_HALF + xi * CELL
				var z := -SimConst.MAP_HALF + zi * CELL
				var d := Vector2(x - s.x, z - s.z).length()
				if d < 60.0:
					var k := smoothstep(60.0, 22.0, d)
					heights[zi * N + xi] = lerpf(heights[zi * N + xi], base, k)
		shelters[si].y = base

	_place_ruins(rng)
	_place_trees(rng)
	_build_grids()


func _raw_height(x: float, z: float, hills: FastNoiseLite, ridges: FastNoiseLite) -> float:
	var r := Vector2(x, z).length()
	var h := 6.0 + hills.get_noise_2d(x, z) * 24.0
	h += maxf(0.0, ridges.get_noise_2d(x, z)) * 30.0 * smoothstep(120.0, 380.0, r)
	h += pow(smoothstep(470.0, 640.0, r), 1.6) * 110.0   # горы по краю долины
	h -= smoothstep(160.0, 0.0, r) * 6.0                 # низина с деревней в центре
	return h


func _place_ruins(rng: RandomNumberGenerator) -> void:
	boxes.clear()
	# Деревня в центре.
	for i in 22:
		var p := Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90))
		_add_box(p, Vector3(rng.randf_range(7, 14), rng.randf_range(4, 11), rng.randf_range(7, 13)))
	# Разбросанные развалины и вышки по долине.
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(150.0, 360.0)
		var p := Vector2(cos(a) * r, sin(a) * r)
		if _near_shelter(p, 70.0):
			continue
		if rng.randf() < 0.25:
			_add_box(p, Vector3(4, rng.randf_range(16, 26), 4))   # водонапорная/вышка
		else:
			_add_box(p, Vector3(rng.randf_range(6, 12), rng.randf_range(3, 8), rng.randf_range(6, 12)))


func _add_box(p: Vector2, size: Vector3) -> void:
	var h := minf(minf(height_at(p.x - size.x * 0.5, p.y - size.z * 0.5), height_at(p.x + size.x * 0.5, p.y + size.z * 0.5)), height_at(p.x, p.y))
	boxes.append(AABB(Vector3(p.x - size.x * 0.5, h - 1.0, p.y - size.z * 0.5), Vector3(size.x, size.y + 1.0, size.z)))


func _place_trees(rng: RandomNumberGenerator) -> void:
	trees.clear()
	var forest := FastNoiseLite.new()
	forest.seed = seed + 99
	forest.frequency = 0.006
	var tries := 0
	while trees.size() < 900 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-560, 560)
		var z := rng.randf_range(-560, 560)
		if forest.get_noise_2d(x, z) < 0.08:
			continue
		if Vector2(x, z).length() > 590.0 or _near_shelter(Vector2(x, z), 45.0):
			continue
		if absf(x) < 110 and absf(z) < 110:
			continue
		if normal_at(x, z).y < 0.82:
			continue
		var blocked := false
		for b in boxes:
			if b.grow(3.0).has_point(Vector3(x, b.position.y + 1.0, z)):
				blocked = true
				break
		if blocked:
			continue
		var top := height_at(x, z) + rng.randf_range(9.0, 17.0)
		trees.append(Vector4(x, z, rng.randf_range(1.6, 2.4), top))


func _near_shelter(p: Vector2, d: float) -> bool:
	for s in shelters:
		if Vector2(s.x, s.z).distance_to(p) < d:
			return true
	return false


func _build_grids() -> void:
	_tree_grid.clear()
	_box_grid.clear()
	for i in trees.size():
		var t := trees[i]
		_grid_add(_tree_grid, Rect2(t.x, t.y, 0, 0).grow(t.z + 1.0), i)
	for i in boxes.size():
		var b := boxes[i]
		_grid_add(_box_grid, Rect2(b.position.x, b.position.z, b.size.x, b.size.z).grow(1.0), i)


func _grid_add(grid: Dictionary, r: Rect2, idx: int) -> void:
	var x0 := int(floor(r.position.x / GRID))
	var x1 := int(floor(r.end.x / GRID))
	var z0 := int(floor(r.position.y / GRID))
	var z1 := int(floor(r.end.y / GRID))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var k := cx * 4096 + cz
			if not grid.has(k):
				grid[k] = PackedInt32Array()
			var arr: PackedInt32Array = grid[k]
			arr.append(idx)
			grid[k] = arr


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SimConst.MAP_HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + SimConst.MAP_HALF) / CELL, 0.0, N - 1.001)
	var xi := int(fx)
	var zi := int(fz)
	var tx := fx - xi
	var tz := fz - zi
	var i := zi * N + xi
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + N]
	var h11 := heights[i + N + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := CELL * 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Столкновение сферы с миром: земля, деревья, руины, края карты.
## Возвращает "" если свободно, иначе что задели.
func collide(p: Vector3, r: float) -> String:
	if p.y - r < height_at(p.x, p.z):
		return "ground"
	if absf(p.x) > SimConst.MAP_HALF + 40.0 or absf(p.z) > SimConst.MAP_HALF + 40.0 or p.y > 600.0:
		return "bounds"
	var k := int(floor(p.x / GRID)) * 4096 + int(floor(p.z / GRID))
	if _tree_grid.has(k):
		for i in _tree_grid[k]:
			var t := trees[i]
			if p.y - r < t.w and Vector2(p.x - t.x, p.z - t.y).length() < t.z + r:
				return "tree"
	if _box_grid.has(k):
		for i in _box_grid[k]:
			if boxes[i].grow(r).has_point(p):
				return "building"
	return ""


## Есть ли прямая видимость между точками (рельеф и постройки, лес не мешает).
func line_of_sight(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var len := d.length()
	var steps := int(ceil(len / 9.0))
	for i in range(1, steps):
		var p := a + d * (float(i) / steps)
		if p.y < height_at(p.x, p.z) + 0.5:
			return false
	for bx in boxes:
		if bx.intersects_segment(a, b):
			return false
	return true


## Высота над землёй.
func agl(p: Vector3) -> float:
	return p.y - height_at(p.x, p.z)
