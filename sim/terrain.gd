class_name Terrain
extends RefCounted
## Процедурная карта по пресету из сида: рельеф одного из архетипов, лес (цилиндры),
## руины (коробки), 8 укрытий.
## Генерируется из сида одинаково на сервере и в клиенте.

const N := 161                                   # узлов по стороне
const CELL := SimConst.MAP_HALF * 2.0 / (N - 1)  # 7,5 м
const GRID := 40.0                               # ячейка пространственного индекса

var seed := 0
var preset: MapPreset
var heights := PackedFloat32Array()
var trees: Array[Vector4] = []      # x, z, радиус, высота верхушки (абсолютная)
var boxes: Array[AABB] = []         # руины и постройки
var shelters: Array[Vector3] = []   # 8 точек укрытий (на земле)
var _tree_grid := {}
var _box_grid := {}
var _hills: FastNoiseLite
var _ridges: FastNoiseLite
var _warp: FastNoiseLite
var _nx := 1.0   # нормаль оси хребта/каньона
var _nz := 0.0

const MAX_PROBE := 4.0         # самый большой радиус сферы для collide (проба ботов — 3 м)
const SHELTER_MIN_DIST := 220.0
const SHELTER_PAD := 60.0      # радиус выравнивания площадки
const SHELTER_R_MIN := 360.0
const SHELTER_R_MAX := 500.0
const MIN_GAP := deg_to_rad(36.0)


func generate(p_seed: int) -> void:
	seed = p_seed
	preset = MapPreset.from_seed(p_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_hills = FastNoiseLite.new()
	_hills.seed = p_seed
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = preset.hill_freq
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_ridges = FastNoiseLite.new()
	_ridges.seed = p_seed + 17
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = preset.ridge_freq
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 3
	_warp = FastNoiseLite.new()
	_warp.seed = p_seed + 31
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 0.003
	_warp.fractal_type = FastNoiseLite.FRACTAL_NONE

	_nx = cos(preset.axis_angle)
	_nz = sin(preset.axis_angle)
	heights.resize(N * N)
	for zi in N:
		for xi in N:
			var x := -SimConst.MAP_HALF + xi * CELL
			var z := -SimConst.MAP_HALF + zi * CELL
			heights[zi * N + xi] = _raw_height(x, z, false)
	_add_outcrops()
	boxes.clear()
	trees.clear()
	_place_shelters(rng)
	# Площадки под укрытия: выравниваем землю.
	for si in shelters.size():
		var s := shelters[si]
		var base := _raw_height(s.x, s.z)
		var r := int(ceil(SHELTER_PAD / CELL)) + 1
		var cx := int(round((s.x + SimConst.MAP_HALF) / CELL))
		var cz := int(round((s.z + SimConst.MAP_HALF) / CELL))
		for zi in range(maxi(0, cz - r), mini(N, cz + r + 1)):
			for xi in range(maxi(0, cx - r), mini(N, cx + r + 1)):
				var x := -SimConst.MAP_HALF + xi * CELL
				var z := -SimConst.MAP_HALF + zi * CELL
				var d := Vector2(x - s.x, z - s.z).length()
				if d < SHELTER_PAD:
					var k := smoothstep(SHELTER_PAD, 22.0, d)
					heights[zi * N + xi] = lerpf(heights[zi * N + xi], base, k)
		shelters[si].y = base

	_place_ruins(rng)
	_place_trees(rng)
	_build_grids()


## Останцы «Холмов» добавляем в сетку локально — так дешевле, чем в каждом узле.
func _add_outcrops() -> void:
	for o in preset.outcrops:
		var rr := o.z * 1.6
		var x0 := maxi(0, int(floor((o.x - rr + SimConst.MAP_HALF) / CELL)))
		var x1 := mini(N - 1, int(ceil((o.x + rr + SimConst.MAP_HALF) / CELL)))
		var z0 := maxi(0, int(floor((o.y - rr + SimConst.MAP_HALF) / CELL)))
		var z1 := mini(N - 1, int(ceil((o.y + rr + SimConst.MAP_HALF) / CELL)))
		for zi in range(z0, z1 + 1):
			for xi in range(x0, x1 + 1):
				var x := -SimConst.MAP_HALF + xi * CELL
				var z := -SimConst.MAP_HALF + zi * CELL
				heights[zi * N + xi] += _outcrop(o, x, z)


static func _outcrop(o: Vector4, x: float, z: float) -> float:
	var d := Vector2(x - o.x, z - o.y).length()
	if d >= o.z * 1.6:
		return 0.0
	return o.w * smoothstep(o.z * 1.6, o.z * 0.8, d)


func _raw_height(x: float, z: float, with_outcrops := true) -> float:
	var p := preset
	var r := Vector2(x, z).length()
	var h := p.base_lift + _hills.get_noise_2d(x, z) * p.hill_amp
	match p.relief:
		MapPreset.Relief.VALLEY:
			h += maxf(0.0, _ridges.get_noise_2d(x, z)) * p.ridge_amp * smoothstep(p.ridge_r0, p.ridge_r1, r)
			h -= smoothstep(160.0, 0.0, r) * p.center_depth             # низина в центре
		MapPreset.Relief.PLATEAU:
			# Приподнятый центр с двумя уступами, край изрезан шумом; низины по периметру.
			var rp := Vector2(x - _nx * p.axis_offset, z - _nz * p.axis_offset).length()
			rp += _warp.get_noise_2d(x, z) * 70.0
			var w := p.feature_width
			var step1 := smoothstep(w + 18.0, w - 8.0, rp)
			var step2 := smoothstep(w * 0.55 + 15.0, w * 0.55 - 5.0, rp)
			h += p.feature_height * (0.6 * step1 + 0.4 * step2)
			h += maxf(0.0, _ridges.get_noise_2d(x, z)) * p.ridge_amp * step1
			h -= smoothstep(w + 40.0, w + 120.0, rp) * smoothstep(520.0, 420.0, r) * 6.0
		MapPreset.Relief.RIDGE:
			# Гряда через карту под углом, с перевалами.
			var along := -_nz * x + _nx * z
			var across := _nx * x + _nz * z - p.axis_offset + _warp.get_noise_2d(x, z) * 40.0
			var cw := across / p.feature_width
			var crest := exp(-cw * cw)
			var gap := 1.0
			for u in p.passes:
				var gu := (along - u) / 48.0
				gap -= 0.78 * exp(-gu * gu)
			h += p.feature_height * crest * maxf(gap, 0.12)
			h += maxf(0.0, _ridges.get_noise_2d(x, z)) * p.ridge_amp * (0.4 + crest)
		MapPreset.Relief.CANYON:
			# Извилистое русло через карту, по бокам — ровные террасы.
			var along := -_nz * x + _nx * z
			var across := _nx * x + _nz * z - p.axis_offset
			across -= sin(along * p.meander_freq) * p.meander_amp + _warp.get_noise_2d(x, z) * 35.0
			var d := absf(across)
			var w := p.feature_width
			var cut := 1.0 - smoothstep(w, w * 2.4, d)
			var terrace := smoothstep(w * 3.2, w * 4.2, d) * 7.0
			h += terrace - p.feature_height * cut
			h += maxf(0.0, _ridges.get_noise_2d(x, z)) * p.ridge_amp * smoothstep(w * 2.4, w * 5.0, d)
		MapPreset.Relief.HILLS:
			h += maxf(0.0, _ridges.get_noise_2d(x, z)) * p.ridge_amp
			if with_outcrops:
				for o in p.outcrops:
					h += _outcrop(o, x, z)
	h += pow(smoothstep(470.0, 640.0, r), 1.6) * p.border_height   # горы по краю — стена арены
	return h


## 8 укрытий по неровному кольцу. Шаг углов не меньше MIN_GAP, радиус не меньше
## SHELTER_R_MIN — тогда соседи гарантированно дальше SHELTER_MIN_DIST:
## d² ≥ 2·r²·(1 − cos 36°) → d ≥ 222 м. Радиус каждой точки — самый ровный из нескольких.
func _place_shelters(rng: RandomNumberGenerator) -> void:
	shelters.clear()
	var n := SimConst.MAX_PLAYERS
	var weights: Array[float] = []
	var wsum := 0.0
	for i in n:
		var w := rng.randf_range(0.25, 1.0)
		weights.append(w)
		wsum += w
	var spare := TAU - MIN_GAP * n
	var gaps: Array[float] = []   # gaps[i] — шаг от точки i к i+1
	for i in n:
		gaps.append(MIN_GAP + spare * weights[i] / wsum)
	var a := rng.randf() * TAU
	for i in n:
		# Каждая точка может сдвинуться на половину запаса до соседей — шаг всё равно ≥ MIN_GAP.
		var back := (gaps[(i + n - 1) % n] - MIN_GAP) * 0.5
		var fwd := (gaps[i] - MIN_GAP) * 0.5
		var best := Vector3.ZERO
		var best_rough := INF
		for k in 10:
			var ak := a if k == 0 else a + rng.randf_range(-back, fwd)
			var r := clampf(preset.shelter_ring + rng.randf_range(-60.0, 60.0), SHELTER_R_MIN, SHELTER_R_MAX)
			var c := Vector3(cos(ak) * r, 0.0, sin(ak) * r)
			var rough := _roughness(c.x, c.z)
			# Из ямы (дно каньона, низина за гребнем) связь до центра не пробить — штраф.
			c.y = _raw_height(c.x, c.z)
			if not line_of_sight(c + Vector3(0, SimConst.MAST_HEIGHT, 0), Vector3(0, _raw_height(0, 0) + 90.0, 0)):
				rough += 100.0
			c.y = 0.0
			if rough < best_rough:
				best_rough = rough
				best = c
		shelters.append(best)
		a += gaps[i]


## Перепад высот вокруг точки — насколько неудобно ставить площадку.
func _roughness(x: float, z: float) -> float:
	var h0 := _raw_height(x, z)
	var lo := h0
	var hi := h0
	for k in 8:
		var a := TAU * k / 8.0
		var h := _raw_height(x + cos(a) * 40.0, z + sin(a) * 40.0)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


func _place_ruins(rng: RandomNumberGenerator) -> void:
	boxes.clear()
	# Скопления домов (деревни).
	for ci in preset.clusters.size():
		var c := preset.clusters[ci]
		var cp := Vector2(c.x, c.y)
		for i in preset.cluster_sizes[ci]:
			var p := cp + Vector2(rng.randf_range(-c.z, c.z), rng.randf_range(-c.z, c.z))
			if _near_shelter(p, 70.0) or normal_at(p.x, p.y).y < 0.85:
				continue
			_add_box(p, Vector3(rng.randf_range(7, 14), rng.randf_range(4, 11), rng.randf_range(7, 13)))
	# Разбросанные развалины и вышки.
	var towers_left := preset.towers
	for i in preset.scattered + preset.towers:
		var a := rng.randf() * TAU
		var r := rng.randf_range(120.0, 400.0)
		var p := Vector2(cos(a) * r, sin(a) * r)
		var tower := towers_left > 0 and (rng.randf() < 0.35 or i >= preset.scattered)
		if _near_shelter(p, 70.0) or normal_at(p.x, p.y).y < 0.8:
			continue
		if tower:
			towers_left -= 1
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
	var lim := SimConst.MAP_HALF - 40.0
	while trees.size() < preset.tree_count and tries < 20000:
		tries += 1
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if forest.get_noise_2d(x, z) < preset.tree_threshold:
			continue
		if Vector2(x, z).length() > SimConst.MAP_HALF - 10.0 or _near_shelter(Vector2(x, z), 45.0):
			continue
		if _in_cluster(Vector2(x, z), 20.0):
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


func _in_cluster(p: Vector2, margin: float) -> bool:
	for c in preset.clusters:
		if Vector2(c.x, c.y).distance_to(p) < c.z + margin:
			return true
	return false


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
		_grid_add(_tree_grid, Rect2(t.x, t.y, 0, 0).grow(t.z + MAX_PROBE), i)
	for i in boxes.size():
		var b := boxes[i]
		_grid_add(_box_grid, Rect2(b.position.x, b.position.z, b.size.x, b.size.z).grow(MAX_PROBE), i)


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
## Возвращает "" если свободно, иначе что задели. Индекс заложен с запасом MAX_PROBE,
## поэтому радиус r не должен его превышать.
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


## Верхушка самого высокого дерева или постройки в радиусе r от точки (x, z); нет — −INF.
## Для помощи высоты: насколько подняться, чтобы пройти над препятствием.
func obstacle_top(x: float, z: float, r: float) -> float:
	var top := -INF
	var k := int(floor(x / GRID)) * 4096 + int(floor(z / GRID))
	if _tree_grid.has(k):
		for i in _tree_grid[k]:
			var t := trees[i]
			if Vector2(x - t.x, z - t.y).length() < t.z + r:
				top = maxf(top, t.w)
	if _box_grid.has(k):
		for i in _box_grid[k]:
			var b := boxes[i]
			if x > b.position.x - r and x < b.end.x + r and z > b.position.z - r and z < b.end.z + r:
				top = maxf(top, b.end.y)
	return top


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
