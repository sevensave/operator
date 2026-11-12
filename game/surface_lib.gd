class_name SurfaceLib
## Библиотека процедурных поверхностей: бесшовные наборы albedo / normal / ORM (+ высота в альфе ORM)
## из FastNoiseLite и Image, без файлов-ассетов. Наборы строятся один раз на процесс
## (параллельно в WorkerThreadPool) и кэшируются статически; работает и headless.
##
## Поверхности земли и коры (GRASS…SNOW, BARK) — «относительные»: среднее ~0,5, оттенок задаёт шейдер
## палитрой биома (albedo = цвет × текстура × 2). Поверхности построек — в абсолютных цветах.
## ORM: R — затенение в щелях (AO), G — шероховатость, B — металличность, A — высота.

enum { GRASS, DRY_GRASS, SOIL, MUD, GRAVEL, ROCK, SNOW, CONCRETE, BRICK, PLASTER, RUST, BARK, ASPHALT }
const COUNT := 13
const NAMES := ["grass", "dry_grass", "soil", "mud", "gravel", "rock", "snow", "concrete", "brick", "plaster", "rust", "bark", "asphalt"]
## Сторона плитки в метрах (шейдеры делят мировые координаты на неё).
const TILE := [2.0, 2.0, 2.0, 2.0, 1.0, 4.0, 2.0, 2.0, 1.0, 2.0, 1.0, 1.0, 2.0]
## Сила рельефа нормалей.
const BUMP := [3.0, 3.0, 4.0, 2.0, 6.0, 7.0, 1.5, 2.5, 5.0, 2.0, 2.0, 7.0, 2.5]
const CHANNELS := ["albedo", "normal", "orm"]

static var _sets := {}       # size -> Array[Array[Image]] по видам
static var _tex := {}        # ключ -> Texture2D / Texture2DArray
static var _mutex := Mutex.new()


## Размер плитки по уровню графики: 512 на низком/среднем, 1024 на высоком.
static func size_for(quality: int) -> int:
	return 1024 if quality >= 2 else 512


## Все наборы указанного размера (строит при первом вызове, параллельно).
static func ensure(size: int) -> Array:
	_mutex.lock()
	var have: Array = _sets.get(size, [])
	_mutex.unlock()
	if not have.is_empty():
		return have
	var out: Array = []
	out.resize(COUNT)
	var lock := Mutex.new()
	var job := func(i: int) -> void:
		var r := _make(i, size)
		lock.lock()
		out[i] = r
		lock.unlock()
	if OS.get_processor_count() > 1:
		var gid := WorkerThreadPool.add_group_task(job, COUNT, -1, true, "SurfaceLib")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for i in COUNT:
			job.call(i)
	_mutex.lock()
	_sets[size] = out
	_mutex.unlock()
	return out


## Набор изображений [albedo, normal, orm] одного вида.
static func images(kind: int, size: int) -> Array:
	return ensure(size)[kind]


## Текстура одного канала (0 albedo, 1 normal, 2 orm) с мип-уровнями.
static func texture(kind: int, channel: int, size: int) -> Texture2D:
	var key := "t%d_%d_%d" % [kind, channel, size]
	if not _tex.has(key):
		_tex[key] = ImageTexture.create_from_image(images(kind, size)[channel])
	return _tex[key]


## Массив текстур одного канала для нескольких видов (слои земли — одной выборкой на канал).
static func array(kinds: Array, channel: int, size: int) -> Texture2DArray:
	var key := "a%s_%d_%d" % [str(kinds), channel, size]
	if not _tex.has(key):
		var imgs: Array[Image] = []
		for k in kinds:
			imgs.append(images(k, size)[channel])
		var ta := Texture2DArray.new()
		ta.create_from_images(imgs)
		_tex[key] = ta
	return _tex[key]


## Обычная шумовая текстура (бывший WorldBuilder._noise_tex): макро-вариация, пятна.
static func noise_tex(freq: float, seamless := true, seed := 0) -> NoiseTexture2D:
	var key := "n%f_%s_%d" % [freq, seamless, seed]
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	n.seed = seed
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = seamless
	t.generate_mipmaps = true
	_tex[key] = t
	return t


# ---------------- Генерация ----------------

## Бесшовный шум как байты L8 размера size×size. freq задан для плитки 512 — на других размерах
## узор тот же. sx/sy < 1 — шум строится в меньшем разрешении и растягивается (волокна, кора).
static func _noise(size: int, freq: float, seed: int, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, oct := 4,
		cell_ret := -1, fractal := FastNoiseLite.FRACTAL_FBM, sx := 1.0, sy := 1.0) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = type
	n.frequency = freq * 512.0 / size
	n.fractal_octaves = oct
	n.fractal_type = fractal if oct > 1 else FastNoiseLite.FRACTAL_NONE
	if cell_ret >= 0:
		n.cellular_return_type = cell_ret
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		n.cellular_jitter = 0.9
	var w := maxi(8, int(size * sx))
	var h := maxi(8, int(size * sy))
	var img := n.get_seamless_image(w, h, false, false, 0.12, true)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	if w != size or h != size:
		img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return img.get_data()


static func _hash(a: int, b: int) -> float:
	var h := (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Строит набор: заполняет высоту, цвет, шероховатость, металл по рецепту вида,
## затем считает AO по впадинам и нормали по высоте (с заворотом краёв — без шва).
static func _make(kind: int, size: int) -> Array:
	var px := size * size
	var hgt := PackedFloat32Array()
	hgt.resize(px)
	var col := PackedByteArray()
	col.resize(px * 4)
	var rgh := PackedByteArray()
	rgh.resize(px)
	var met := PackedByteArray()
	met.resize(px)
	var s := 1000 + kind * 77
	match kind:
		GRASS, DRY_GRASS:
			_grass(size, s, kind == DRY_GRASS, hgt, col, rgh)
		SOIL, MUD:
			_soil(size, s, kind == MUD, hgt, col, rgh)
		GRAVEL:
			_gravel(size, s, hgt, col, rgh)
		ROCK:
			_rock(size, s, hgt, col, rgh)
		SNOW:
			_snow(size, s, hgt, col, rgh)
		CONCRETE, ASPHALT:
			_concrete(size, s, kind == ASPHALT, hgt, col, rgh)
		BRICK:
			_brick(size, s, hgt, col, rgh)
		PLASTER:
			_plaster(size, s, hgt, col, rgh)
		RUST:
			_rust(size, s, hgt, col, rgh, met)
		BARK:
			_bark(size, s, hgt, col, rgh)
	return _finish(size, hgt, col, rgh, met, BUMP[kind] * size / 512.0)


static func _finish(size: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray, met: PackedByteArray, bump: float) -> Array:
	var px := size * size
	# Размытая высота (вниз-вверх по разрешению — нативно и быстро) → AO во впадинах.
	var hb := PackedByteArray()
	hb.resize(px)
	for i in px:
		hb[i] = int(clampf(hgt[i], 0.0, 1.0) * 255.0)
	var himg := Image.create_from_data(size, size, false, Image.FORMAT_L8, hb)
	var blur := himg.duplicate() as Image
	blur.resize(maxi(size / 16, 4), maxi(size / 16, 4), Image.INTERPOLATE_BILINEAR)
	blur.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var bd := blur.get_data()
	var nrm := PackedByteArray()
	nrm.resize(px * 4)
	var orm := PackedByteArray()
	orm.resize(px * 4)
	var m := size - 1
	for y in size:
		var row := y * size
		var up := ((y - 1) & m) * size
		var dn := ((y + 1) & m) * size
		for x in size:
			var i := row + x
			var dx := hgt[row + ((x + 1) & m)] - hgt[row + ((x - 1) & m)]
			var dy := hgt[dn + x] - hgt[up + x]
			var nx := -dx * bump
			var ny := dy * bump
			var inv := 1.0 / sqrt(nx * nx + ny * ny + 1.0)
			var o := i * 4
			nrm[o] = int((nx * inv * 0.5 + 0.5) * 255.0)
			nrm[o + 1] = int((ny * inv * 0.5 + 0.5) * 255.0)
			nrm[o + 2] = int((inv * 0.5 + 0.5) * 255.0)
			nrm[o + 3] = 255
			var ao := clampf(1.0 + (hgt[i] - bd[i] / 255.0) * 2.2, 0.25, 1.0)
			orm[o] = int(ao * 255.0)
			orm[o + 1] = rgh[i]
			orm[o + 2] = met[i]
			orm[o + 3] = hb[i]
	var a := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, col)
	var n := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, nrm)
	var r := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, orm)
	a.generate_mipmaps()
	n.generate_mipmaps(true)
	r.generate_mipmaps()
	return [a, n, r]


static func _put(col: PackedByteArray, i: int, r: float, g: float, b: float) -> void:
	var o := i * 4
	col[o] = int(clampf(r, 0.0, 1.0) * 255.0)
	col[o + 1] = int(clampf(g, 0.0, 1.0) * 255.0)
	col[o + 2] = int(clampf(b, 0.0, 1.0) * 255.0)
	col[o + 3] = 255


## Трава: кочки и пучки (клеточный шум), мелкие стебли, сухие проплешины. Относительный цвет.
static func _grass(size: int, s: int, dry: bool, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var big := _noise(size, 0.012, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var tuft := _noise(size, 0.07, s + 1, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE)
	var fine := _noise(size, 0.22, s + 2, FastNoiseLite.TYPE_SIMPLEX, 2, -1, FastNoiseLite.FRACTAL_FBM, 1.0 if not dry else 0.35, 1.0)
	var spot := _noise(size, 0.04, s + 3, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_CELL_VALUE)
	for i in size * size:
		var b := big[i] / 255.0
		var t := 1.0 - tuft[i] / 255.0
		var f := fine[i] / 255.0
		var h := t * 0.55 + f * 0.45
		hgt[i] = h
		var dryk := smoothstep(0.55, 0.75, b) * (0.6 if not dry else 1.0)
		var v := 0.34 + h * 0.36 + (spot[i] / 255.0 - 0.5) * 0.12
		var y := dryk * 0.18 + (0.08 if dry else 0.0)
		_put(col, i, v * (1.0 + y * 0.9), v * (1.0 + y * 0.25), v * (1.0 - y * 0.9))
		rgh[i] = int((0.82 + f * 0.14) * 255.0)


## Грунт/грязь: комья, мелкие камушки; грязь — гладкая, тёмная, влажная во впадинах.
static func _soil(size: int, s: int, mud: bool, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var big := _noise(size, 0.02, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var clod := _noise(size, 0.05 if not mud else 0.03, s + 1, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE2_DIV)
	var peb := _noise(size, 0.16, s + 2, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE)
	var fine := _noise(size, 0.3, s + 3, FastNoiseLite.TYPE_VALUE, 1)
	for i in size * size:
		var b := big[i] / 255.0
		var c := 1.0 - clod[i] / 255.0
		var p := smoothstep(0.62, 0.8, 1.0 - peb[i] / 255.0)
		var f := fine[i] / 255.0
		var h: float
		var v: float
		var r: float
		if mud:
			h = b * 0.7 + c * 0.2 + f * 0.1
			var wet := smoothstep(0.5, 0.38, h)
			v = (0.40 + h * 0.25) * (1.0 - wet * 0.35)
			r = lerpf(0.75, 0.25, wet)
		else:
			h = b * 0.35 + c * 0.4 + p * 0.15 + f * 0.1
			v = 0.36 + h * 0.3 + p * 0.12
			r = 0.88 + f * 0.1 - p * 0.15
		hgt[i] = h
		_put(col, i, v * 1.04, v, v * 0.94)
		rgh[i] = int(clampf(r, 0.0, 1.0) * 255.0)


## Гравий: окатыши по клеткам (высота — купол клетки, цвет — значение клетки).
static func _gravel(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var dist := _noise(size, 0.045, s, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE)
	var cell := _noise(size, 0.045, s, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_CELL_VALUE)
	var fine := _noise(size, 0.4, s + 2, FastNoiseLite.TYPE_VALUE, 1)
	var dirt := _noise(size, 0.015, s + 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	for i in size * size:
		var d := dist[i] / 255.0
		var dome := sqrt(clampf(1.0 - d * 1.35, 0.0, 1.0))
		var cv := cell[i] / 255.0
		var f := fine[i] / 255.0
		var h := dome * 0.85 + f * 0.15
		hgt[i] = h
		var v := (0.30 + cv * 0.4) * (0.55 + dome * 0.45) + f * 0.05
		var fill := smoothstep(0.15, 0.0, dome) * (0.5 + dirt[i] / 255.0 * 0.5)
		v = lerpf(v, 0.3, fill)
		_put(col, i, v * (0.98 + cv * 0.06), v, v * (1.02 - cv * 0.06))
		rgh[i] = int((0.7 + f * 0.2 + fill * 0.1) * 255.0)


## Скала: гребни (ridged), слоистость, трещины.
static func _rock(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var ridge := _noise(size, 0.012, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5, -1, FastNoiseLite.FRACTAL_RIDGED)
	var fine := _noise(size, 0.09, s + 1, FastNoiseLite.TYPE_SIMPLEX, 3)
	var crack := _noise(size, 0.025, s + 2, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var lich := _noise(size, 0.05, s + 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	for y in size:
		var strata := sin(y * TAU * 5.0 / size) * 0.5 + 0.5
		for x in size:
			var i := y * size + x
			var rr := ridge[i] / 255.0
			var f := fine[i] / 255.0
			var cr := smoothstep(0.06, 0.0, crack[i] / 255.0)
			var h := rr * 0.6 + f * 0.25 + strata * 0.15 - cr * 0.35
			hgt[i] = h
			var v := 0.36 + h * 0.3 + (f - 0.5) * 0.1 - cr * 0.12
			var l := smoothstep(0.62, 0.72, lich[i] / 255.0) * 0.5
			_put(col, i, v * (1.0 + l * 0.05), v * (1.0 + l * 0.12), v * (0.98 - l * 0.15))
			rgh[i] = int((0.78 + f * 0.15) * 255.0)


## Снег: мягкие надувы, искры (низкая шероховатость точками), следы подтаявшей корки.
static func _snow(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var big := _noise(size, 0.012, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var fine := _noise(size, 0.12, s + 1, FastNoiseLite.TYPE_SIMPLEX, 2)
	var spark := _noise(size, 0.6, s + 2, FastNoiseLite.TYPE_VALUE, 1)
	for i in size * size:
		var b := big[i] / 255.0
		var f := fine[i] / 255.0
		var h := b * 0.8 + f * 0.2
		hgt[i] = h
		var v := 0.47 + b * 0.06 + f * 0.03
		_put(col, i, v * 0.98, v, v * 1.03)
		var sp := spark[i] / 255.0
		rgh[i] = int((0.55 if sp < 0.95 else 0.15) * 255.0 + f * 30.0)


## Бетон (или асфальт): пятна и поры, швы опалубки, трещины.
static func _concrete(size: int, s: int, asphalt: bool, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var big := _noise(size, 0.012, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var pore := _noise(size, 0.3 if not asphalt else 0.5, s + 1, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE)
	var crack := _noise(size, 0.01, s + 2, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var fine := _noise(size, 0.5, s + 3, FastNoiseLite.TYPE_VALUE, 1)
	for y in size:
		var seam := 1.0 if (not asphalt and (y % (size / 2) < size / 256 + 1)) else 0.0
		for x in size:
			var i := y * size + x
			var b := big[i] / 255.0
			var p := smoothstep(0.25, 0.1, pore[i] / 255.0)
			var cr := smoothstep(0.03, 0.0, crack[i] / 255.0) * smoothstep(0.45, 0.6, b)
			var f := fine[i] / 255.0
			var h := 0.6 + b * 0.2 + f * 0.1 - p * 0.3 - cr * 0.4 - seam * 0.25
			hgt[i] = h
			var v: float
			if asphalt:
				v = 0.10 + f * 0.08 + b * 0.05 + smoothstep(0.85, 0.95, f) * 0.15
				_put(col, i, v, v, v * 1.02)
				rgh[i] = int((0.88 - cr * 0.1) * 255.0)
			else:
				v = (0.48 + (b - 0.5) * 0.18 + f * 0.05) * (1.0 - p * 0.35) * (1.0 - cr * 0.4) * (1.0 - seam * 0.2)
				_put(col, i, v * 1.0, v * 0.99, v * 0.96)
				rgh[i] = int((0.82 + f * 0.12) * 255.0)


## Кирпич: 4 кирпича в ряд × 16 рядов на метр, перевязка со сдвигом, сколы, разный обжиг.
static func _brick(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var fine := _noise(size, 0.35, s, FastNoiseLite.TYPE_SIMPLEX, 2)
	var chip := _noise(size, 0.08, s + 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var soot := _noise(size, 0.015, s + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	var rows := 16
	var cols := 4
	var rh := float(size) / rows
	var cw := float(size) / cols
	var mort := maxf(1.5, size / 256.0 * 2.0)
	for y in size:
		var row := int(y / rh)
		var fy := fmod(float(y), rh)
		for x in size:
			var i := y * size + x
			var xs := fmod(float(x) + (cw * 0.5 if row % 2 == 1 else 0.0), float(size))
			var c := int(xs / cw)
			var fx := fmod(xs, cw)
			var ed := minf(minf(fx, cw - fx), minf(fy, rh - fy))
			var ch := chip[i] / 255.0
			var f := fine[i] / 255.0
			var in_brick := smoothstep(mort * 0.6, mort * 1.4 + (ch - 0.5) * mort * 2.0, ed)
			var hb := _hash(row, c % cols)
			var h := in_brick * (0.7 + f * 0.15 + hb * 0.1) + (1.0 - in_brick) * (0.2 + f * 0.1)
			hgt[i] = h
			var dk := 0.75 + hb * 0.35 - smoothstep(0.6, 0.8, soot[i] / 255.0) * 0.3
			var br := Vector3(0.50, 0.22, 0.15) * dk * (0.9 + f * 0.2)
			if hb > 0.85:
				br = Vector3(0.36, 0.18, 0.14) * (0.9 + f * 0.2)   # пережжённый
			var mo := Vector3(0.52, 0.50, 0.46) * (0.85 + f * 0.2)
			var cc := mo.lerp(br, in_brick)
			_put(col, i, cc.x, cc.y, cc.z)
			rgh[i] = int(lerpf(0.95, 0.82 + f * 0.1, in_brick) * 255.0)


## Штукатурка: песчаная зернистость, волосяные трещины, пятна сырости.
static func _plaster(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var big := _noise(size, 0.01, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var sand := _noise(size, 0.6, s + 1, FastNoiseLite.TYPE_VALUE, 1)
	var crack := _noise(size, 0.02, s + 2, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var damp := _noise(size, 0.02, s + 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	for i in size * size:
		var b := big[i] / 255.0
		var sd := sand[i] / 255.0
		var cr := smoothstep(0.025, 0.0, crack[i] / 255.0) * smoothstep(0.5, 0.65, damp[i] / 255.0)
		var h := 0.6 + b * 0.25 + sd * 0.1 - cr * 0.4
		hgt[i] = h
		var dm := smoothstep(0.55, 0.75, damp[i] / 255.0) * 0.25
		var v := (0.66 + (b - 0.5) * 0.1 + sd * 0.04) * (1.0 - dm) * (1.0 - cr * 0.5)
		_put(col, i, v * 1.02, v * 0.98, v * 0.9)
		rgh[i] = int((0.88 + sd * 0.1) * 255.0)


## Ржавый металл: профлист (волна), пятна ржавчины поверх серой стали, потёки.
static func _rust(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray, met: PackedByteArray) -> void:
	var blot := _noise(size, 0.02, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5)
	var fine := _noise(size, 0.3, s + 1, FastNoiseLite.TYPE_VALUE, 2)
	var streak := _noise(size, 0.05, s + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3, -1, FastNoiseLite.FRACTAL_FBM, 1.0, 0.12)
	for y in size:
		for x in size:
			var i := y * size + x
			var wave := sin(x * TAU * 8.0 / size) * 0.5 + 0.5
			var f := fine[i] / 255.0
			var rust := smoothstep(0.45, 0.6, blot[i] / 255.0 * 0.7 + streak[i] / 255.0 * 0.45 + f * 0.1 - 0.1)
			var h := wave * 0.7 + f * 0.1 + rust * 0.15
			hgt[i] = h
			var steel := Vector3(0.42, 0.43, 0.44) * (0.85 + f * 0.25)
			var rc := Vector3(0.42, 0.20, 0.09).lerp(Vector3(0.26, 0.12, 0.06), f) * (0.9 + wave * 0.15)
			var cc := steel.lerp(rc, rust)
			_put(col, i, cc.x, cc.y, cc.z)
			rgh[i] = int(lerpf(0.45, 0.92, rust) * 255.0)
			met[i] = int((1.0 - rust) * 0.85 * 255.0)


## Кора: вертикальные борозды (растянутый шум), чешуйки, мох снизу задаёт шейдер. Относительный цвет.
static func _bark(size: int, s: int, hgt: PackedFloat32Array, col: PackedByteArray, rgh: PackedByteArray) -> void:
	var furrow := _noise(size, 0.035, s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, -1, FastNoiseLite.FRACTAL_RIDGED, 1.0, 0.15)
	var plate := _noise(size, 0.05, s + 1, FastNoiseLite.TYPE_CELLULAR, 1, FastNoiseLite.RETURN_DISTANCE2_DIV, FastNoiseLite.FRACTAL_FBM, 1.0, 0.4)
	var fine := _noise(size, 0.3, s + 2, FastNoiseLite.TYPE_VALUE, 1)
	for i in size * size:
		var fu := furrow[i] / 255.0
		var pl := 1.0 - plate[i] / 255.0
		var f := fine[i] / 255.0
		var h := fu * 0.6 + pl * 0.3 + f * 0.1
		hgt[i] = h
		var v := 0.22 + h * 0.5 + f * 0.04
		_put(col, i, v * 1.04, v, v * 0.92)
		rgh[i] = int((0.85 + f * 0.12) * 255.0)
