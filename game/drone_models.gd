class_name DroneModels
## Процедурные модели дронов: по три варианта коптера и самолёта. Только внешний вид —
## хитбокс и физика общие для типа. Геометрия собирается из плит по контуру, тел вращения,
## труб, лофтов и профилей крыла в одну сетку с отдельной поверхностью на материал.
## Нос дрона смотрит в −Z, верх — +Y. Меши кэшируются по (тип, модель).

const MATS := ["carbon", "plastic", "skin", "metal", "dark", "lens", "payload", "accent"]

static var _mesh_cache := {}
static var _mats := {}
static var _accent_mats := {}


## Результат: {"mesh": ArrayMesh, "props": [{pos, radius, axis: 0 (Y) / 2 (Z), dir, blades}],
##  "nav": [позиции огней цвета стороны], "strobe": позиция строба, "scale": масштаб узла}
static func build(kind: int, model: int) -> Dictionary:
	var key := kind * 10 + clampi(model, 0, SimConst.MODEL_COUNT - 1)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	var info := {}
	if kind == SimConst.Kind.COPTER:
		match key % 10:
			1: info = _racer(k)
			2: info = _hexa(k)
			_: info = _quad_x(k)
	else:
		match key % 10:
			1: info = _flying_wing(k)
			2: info = _twin_boom(k)
			_: info = _classic(k)
	info.mesh = k.commit()
	_mesh_cache[key] = info
	return info


## Материалы поверхностей сетки по порядку Kit.surfaces (accent — окраска в цвет стороны).
static func material(name: String, color := Color.WHITE) -> Material:
	if name == "accent":
		var ck := color.to_html()
		if not _accent_mats.has(ck):
			var a := StandardMaterial3D.new()
			a.albedo_color = color.lerp(Color(0.5, 0.5, 0.5), 0.12)
			a.roughness = 0.42
			a.metallic = 0.1
			a.clearcoat_enabled = true
			a.clearcoat = 0.5
			a.clearcoat_roughness = 0.3
			a.emission_enabled = true     # чуть светится, чтобы цвет читался в сумерках
			a.emission = color
			a.emission_energy_multiplier = 0.12
			_accent_mats[ck] = a
		return _accent_mats[ck]
	if _mats.is_empty():
		_init_mats()
	return _mats[name]


static func _init_mats() -> void:
	var rough := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	rough.noise = n
	rough.width = 128
	rough.height = 128
	rough.seamless = true
	var weave := _weave_textures()
	var carbon := StandardMaterial3D.new()
	carbon.albedo_color = Color(0.36, 0.37, 0.40)
	carbon.albedo_texture = weave[0]
	carbon.normal_enabled = true
	carbon.normal_texture = weave[1]
	carbon.normal_scale = 0.6
	carbon.metallic = 0.2
	carbon.roughness = 0.42
	carbon.roughness_texture = rough
	carbon.uv1_triplanar = true
	carbon.uv1_scale = Vector3(14, 14, 14)
	carbon.clearcoat_enabled = true
	carbon.clearcoat = 0.6
	carbon.clearcoat_roughness = 0.25
	_mats.carbon = carbon
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.2, 0.21, 0.225)
	plastic.roughness = 0.6
	_mats.plastic = plastic
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.66, 0.69, 0.70)
	skin.roughness = 0.5
	skin.roughness_texture = rough
	skin.uv1_triplanar = true
	skin.uv1_scale = Vector3(3, 3, 3)
	_mats.skin = skin
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.72, 0.73, 0.75)
	metal.metallic = 0.9
	metal.roughness = 0.3
	_mats.metal = metal
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.205, 0.225)
	dark.metallic = 0.55
	dark.roughness = 0.36
	_mats.dark = dark
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.02, 0.03, 0.05)
	lens.metallic = 0.6
	lens.roughness = 0.05
	lens.emission_enabled = true
	lens.emission = Color(0.1, 0.25, 0.4)
	lens.emission_energy_multiplier = 0.4
	_mats.lens = lens
	var payload := StandardMaterial3D.new()
	payload.albedo_color = Color(0.34, 0.37, 0.25)
	payload.roughness = 0.75
	_mats.payload = payload
	# Износ: пыль пятнами и царапины поверх всех «рабочих» поверхностей (кроме линзы и металла).
	var dust := _dust_textures()
	for key in ["carbon", "plastic", "skin", "dark", "payload"]:
		var m: StandardMaterial3D = _mats[key]
		m.detail_enabled = true
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		m.detail_albedo = dust[0]
		m.detail_mask = dust[1]
		m.uv2_triplanar = true
		m.uv2_scale = Vector3(4, 4, 4)


## Плетение карбона «твил 2×2»: тёмные и светлые пряди, рельеф по прядям. [albedo, normal]
static func _weave_textures() -> Array:
	var size := 128
	var tow := 16
	var hgt := PackedFloat32Array()
	hgt.resize(size * size)
	var col := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var i := x / tow
			var j := y / tow
			var over := ((i + j) / 2) % 2 == 0      # нить по x поверх или по y
			var fx := float(x % tow) / tow
			var fy := float(y % tow) / tow
			var across := fy if over else fx           # поперёк пряди — выпуклость
			var h := sin(across * PI)
			hgt[y * size + x] = h
			var sheen := 0.32 + 0.38 * h * (1.0 if over else 0.75)
			col.set_pixel(x, y, Color(sheen, sheen, sheen * 1.04))
	var nrm := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := hgt[y * size + (x + 1) % size] - hgt[y * size + (x + size - 1) % size]
			var dy := hgt[((y + 1) % size) * size + x] - hgt[((y + size - 1) % size) * size + x]
			var n := Vector3(-dx * 1.5, dy * 1.5, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	col.generate_mipmaps()
	nrm.generate_mipmaps(true)
	return [ImageTexture.create_from_image(col), ImageTexture.create_from_image(nrm)]


## Пыль и царапины: [цвет пыли с альфой царапин, маска пятен].
static func _dust_textures() -> Array:
	var size := 256
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	n.fractal_octaves = 4
	n.seed = 21
	var mask := n.get_seamless_image(size, size)
	var alb := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for y in size:
		for x in size:
			var m := mask.get_pixel(x, y).r
			alb.set_pixel(x, y, Color(0.46, 0.42, 0.36, smoothstep(0.6, 0.85, m) * 0.35))
	# Царапины: тонкие светлые штрихи.
	for k in 60:
		var a := Vector2(rng.randf() * size, rng.randf() * size)
		var d := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8, 30)
		for t in 30:
			var p := a + d * t / 30.0
			alb.set_pixel(posmod(int(p.x), size), posmod(int(p.y), size), Color(0.75, 0.74, 0.72, 0.6))
	var mk := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := clampf(mask.get_pixel(x, y).r * 1.4 - 0.2, 0.0, 1.0)
			mk.set_pixel(x, y, Color(v, v, v))
	alb.generate_mipmaps()
	mk.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(mk)]


# ---------------- Коптеры ----------------

## Луч рамы: сужается к концу и заканчивается круглой площадкой под мотор.
static func _arm(k: Kit, ang: float, len: float, w0: float, w1: float, pad: float, y: float, thick := 0.012) -> Vector3:
	var dir := Vector2(sin(ang), -cos(ang))
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([side * w0, dir * (len - pad) + side * w1])
	for i in 9:
		var a := -PI * 0.5 + PI * i / 8.0
		pts.append(dir * len + (dir * cos(a) - side * sin(a)) * pad * (1.0 if i > 0 and i < 8 else 0.9))
	pts.append(dir * (len - pad) - side * w1)
	pts.append(-side * w0)
	pts.append(-dir * w0 * 0.6)
	k.plate("carbon", _at(Vector3(0, y, 0)), pts, thick)
	return Vector3(dir.x * len, y, dir.y * len)


## Прямоугольная плита со срезанными углами (x × z).
static func _deck(k: Kit, mat: String, y: float, sx: float, sz: float, cut: float, thick: float, z0 := 0.0) -> void:
	var hx := sx * 0.5
	var hz := sz * 0.5
	k.plate(mat, _at(Vector3(0, y, z0)), PackedVector2Array([Vector2(-hx + cut, -hz), Vector2(hx - cut, -hz), Vector2(hx, -hz + cut),
		Vector2(hx, hz - cut), Vector2(hx - cut, hz), Vector2(-hx + cut, hz), Vector2(-hx, hz - cut), Vector2(-hx, -hz + cut)]), thick)


static func _quad_x(k: Kit) -> Dictionary:
	# Фристайл-пятёрка: X-рама, две плиты на анодированных стойках, АКБ сверху, заряд снизу.
	var props := []
	var nav := []
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var tip := _arm(k, a, 0.31, 0.034, 0.017, 0.036, 0.0)
		_motor(k, tip + Vector3(0, 0.006, 0), 0.031)
		props.append({"pos": tip + Vector3(0, 0.062, 0), "radius": 0.155, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0, "blades": 3})
		if tip.z > 0.0:
			nav.append(tip + Vector3(0, -0.012, 0))
	_deck(k, "carbon", 0.011, 0.105, 0.30, 0.022, 0.006)
	_deck(k, "carbon", 0.068, 0.088, 0.25, 0.02, 0.005, 0.01)
	for x: float in [-0.036, 0.036]:
		for z: float in [-0.1, 0.0, 0.115]:
			k.tube("accent", Vector3(x, 0.013, z), Vector3(x, 0.066, z), 0.0055, 0.0055, 8)
	k.rbox("plastic", _at(Vector3(0, 0.034, 0.03)), Vector3(0.05, 0.03, 0.05), 0.004)      # полётный стек
	k.rbox("dark", _at(Vector3(0, 0.03, 0.095)), Vector3(0.044, 0.02, 0.04), 0.003)        # видеопередатчик
	k.rbox("accent", _at(Vector3(0, 0.04, -0.098)), Vector3(0.058, 0.04, 0.02), 0.004)     # крепление камеры
	_fpv_cam(k, Vector3(0, 0.04, -0.118), 0.017)
	k.rbox("plastic", _at(Vector3(0, 0.094, 0.015)), Vector3(0.074, 0.044, 0.165), 0.008)  # АКБ
	k.rbox("accent", _at(Vector3(0, 0.1165, 0.03)), Vector3(0.05, 0.002, 0.09), 0.0005)    # наклейка
	k.rbox("dark", _at(Vector3(0, 0.094, -0.03)), Vector3(0.079, 0.049, 0.022), 0.003)     # ремешок
	_antenna(k, Vector3(0, 0.07, 0.125), Vector3(0, 0.165, 0.2))
	_charge(k, Vector3(0, -0.052, 0.0), 0.042, 0.22)
	return {"props": props, "nav": nav, "strobe": Vector3(0, 0.074, 0.138), "scale": 1.4}


static func _racer(k: Kit) -> Dictionary:
	# Синевуп: обтекаемый корпус в цвет стороны и четыре кольцевых канала вокруг винтов.
	k.loft("accent", _at(Vector3(0, 0.03, 0)), [[-0.175, 0.0, 0.0, 0.0], [-0.155, 0.04, 0.022, 0.0], [-0.09, 0.07, 0.04, 0.004],
		[0.02, 0.078, 0.046, 0.008], [0.12, 0.058, 0.036, 0.006], [0.17, 0.03, 0.02, 0.002], [0.185, 0.0, 0.0, 0.0]], 16)
	_deck(k, "carbon", 0.0, 0.13, 0.30, 0.03, 0.008)
	k.rbox("dark", _at(Vector3(0, 0.014, 0)), Vector3(0.1, 0.02, 0.22), 0.004)
	var props := []
	var nav := []
	var rr := 0.14
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var tip := _arm(k, a, 0.25, 0.03, 0.02, 0.03, 0.0, 0.008)
		_motor(k, tip + Vector3(0, 0.004, 0), 0.027)
		# Кольцевой канал: наружная стенка, скруглённая губа, внутренняя стенка.
		k.lathe("dark", _at(tip + Vector3(0, -0.006, 0)), [Vector2(rr, 0.0), Vector2(rr + 0.012, 0.0), Vector2(rr + 0.017, 0.03),
			Vector2(rr + 0.016, 0.062), Vector2(rr + 0.008, 0.07), Vector2(rr + 0.001, 0.062), Vector2(rr, 0.0)], 28, true)
		k.lathe("accent", _at(tip + Vector3(0, 0.05, 0)), [Vector2(rr + 0.0165, 0.0), Vector2(rr + 0.0185, 0.001),
			Vector2(rr + 0.0185, 0.011), Vector2(rr + 0.0165, 0.012)], 28, false)
		for sidx in 3:
			var b := a + PI + (sidx - 1) * 1.25
			k.tube("plastic", tip + Vector3(sin(b), 0, -cos(b)) * 0.028 + Vector3(0, 0.004, 0), tip + Vector3(sin(b), 0, -cos(b)) * (rr + 0.004) + Vector3(0, 0.004, 0), 0.0045, 0.0045, 6)
		props.append({"pos": tip + Vector3(0, 0.054, 0), "radius": 0.132, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0, "blades": 3})
		if tip.z > 0.0:
			nav.append(tip + Vector3(sin(a), 0, -cos(a)) * (rr + 0.02) + Vector3(0, 0.03, 0))
	k.rbox("dark", _at(Vector3(0, 0.044, -0.158)), Vector3(0.05, 0.036, 0.03), 0.005)
	_fpv_cam(k, Vector3(0, 0.046, -0.172), 0.016)
	_antenna(k, Vector3(0, 0.06, 0.14), Vector3(0, 0.14, 0.2))
	_charge(k, Vector3(0, -0.044, 0.0), 0.036, 0.18)
	return {"props": props, "nav": nav, "strobe": Vector3(0, 0.078, 0.06), "scale": 1.4}


static func _hexa(k: Kit) -> Dictionary:
	# Тяжёлая гекса: шестигранные плиты, купол, трубчатые лучи с хомутами, шасси-полозья.
	var hexagon := PackedVector2Array()
	for i in 6:
		hexagon.append(Vector2(cos(i * TAU / 6.0), sin(i * TAU / 6.0)))
	var big := PackedVector2Array()
	var small := PackedVector2Array()
	for p in hexagon:
		big.append(p * 0.135)
		small.append(p * 0.115)
	k.plate("carbon", _at(Vector3(0, 0.0, 0)), big, 0.008)
	k.plate("carbon", _at(Vector3(0, 0.056, 0)), small, 0.006)
	k.lathe("dark", _at(Vector3(0, 0.004, 0)), [Vector2(0.085, 0.0), Vector2(0.085, 0.05)], 18, false)
	k.lathe("accent", _at(Vector3(0, 0.059, 0)), [Vector2(0.092, 0.0), Vector2(0.09, 0.016), Vector2(0.078, 0.036), Vector2(0.052, 0.052),
		Vector2(0.02, 0.06), Vector2(0.0, 0.061)], 20, true)
	k.tube("dark", Vector3(0, 0.115, 0.03), Vector3(0, 0.16, 0.03), 0.004, 0.004, 6)
	k.lathe("plastic", _at(Vector3(0, 0.16, 0.03)), [Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.028, 0.006), Vector2(0.02, 0.014), Vector2(0.0, 0.015)], 14, true)
	var props := []
	var nav := []
	for i in 6:
		var a := i * TAU / 6.0 + PI / 6.0
		var dir := Vector3(sin(a), 0, -cos(a))
		var tip := dir * 0.42 + Vector3(0, 0.028, 0)
		k.tube("carbon", dir * 0.07 + Vector3(0, 0.028, 0), tip, 0.0125, 0.0125, 10)
		k.tube("accent", dir * 0.122 + Vector3(0, 0.028, 0), dir * 0.158 + Vector3(0, 0.028, 0), 0.0165, 0.0165, 10)
		k.lathe("dark", _at(tip + Vector3(0, -0.016, 0)), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.034, 0.008), Vector2(0.034, 0.026), Vector2(0.0, 0.026)], 12, false)
		_motor(k, tip + Vector3(0, 0.01, 0), 0.034)
		props.append({"pos": tip + Vector3(0, 0.068, 0), "radius": 0.17, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0, "blades": 2})
		if dir.z > 0.3:
			nav.append(tip + Vector3(0, -0.022, 0))
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.07, 0.07]:
			k.tube("carbon", Vector3(s * 0.075, -0.002, z), Vector3(s * 0.165, -0.2, z * 1.4), 0.008, 0.008, 8)
		k.tube("carbon", Vector3(s * 0.165, -0.2, -0.17), Vector3(s * 0.165, -0.2, 0.17), 0.009, 0.009, 8)
		for z: float in [-0.17, 0.17]:
			k.ellip("plastic", _at(Vector3(s * 0.165, -0.2, z)), Vector3(0.013, 0.013, 0.02), 8, 5)
	k.ellip("dark", _at(Vector3(0, -0.035, -0.135)), Vector3(0.034, 0.034, 0.034), 12, 8)   # подвес камеры
	_fpv_cam(k, Vector3(0, -0.035, -0.158), 0.016, 0.0)
	_charge(k, Vector3(0, -0.085, 0.01), 0.058, 0.27)
	return {"props": props, "nav": nav, "strobe": Vector3(0, 0.178, 0.03), "scale": 1.3}


## Бесколлекторный мотор: основание, колокол с фаской, цветное кольцо, вал с гайкой.
static func _motor(k: Kit, p: Vector3, r: float) -> void:
	k.lathe("dark", _at(p), [Vector2(0.0, 0.0), Vector2(r * 0.78, 0.0), Vector2(r * 0.78, 0.007), Vector2(r, 0.009),
		Vector2(r, 0.028), Vector2(r * 0.84, 0.036), Vector2(r * 0.34, 0.037), Vector2(0.0, 0.037)], 16, false)
	k.lathe("accent", _at(p + Vector3(0, 0.0125, 0)), [Vector2(r, 0.0), Vector2(r * 1.03, 0.0005), Vector2(r * 1.03, 0.006), Vector2(r, 0.0065)], 16, false)
	k.lathe("metal", _at(p + Vector3(0, 0.037, 0)), [Vector2(0.0, 0.0), Vector2(0.0065, 0.0), Vector2(0.0065, 0.014), Vector2(0.004, 0.02), Vector2(0.0, 0.02)], 8, false)


## Курсовая камера: корпус, тубус объектива, линза. tilt — наклон вверх, рад.
static func _fpv_cam(k: Kit, p: Vector3, r: float, tilt := 0.35) -> void:
	var fwd := Vector3(0, sin(tilt), -cos(tilt))
	k.rbox("plastic", Transform3D(Basis(Vector3.RIGHT, tilt), p), Vector3(r * 2.2, r * 2.2, r * 1.6), r * 0.25)
	k.tube("dark", p + fwd * r * 0.7, p + fwd * r * 1.7, r * 0.82, r * 0.74, 14)
	k.tube("lens", p + fwd * r * 1.7, p + fwd * r * 1.78, r * 0.6, r * 0.5, 14)


## Антенна видеопередатчика: штырь и «грибок».
static func _antenna(k: Kit, a: Vector3, b: Vector3) -> void:
	k.tube("dark", a, b, 0.0035, 0.003, 6)
	var d := (b - a).normalized()
	k.tube("plastic", b - d * 0.004, b + d * 0.022, 0.014, 0.014, 10)


## Заряд под брюхом: оживальный нос, корпус, взрыватель, хвостовик с оперением, хомуты.
static func _charge(k: Kit, p: Vector3, r: float, len: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), p + Vector3(0, 0, len * 0.5))   # ось +Y тела → −Z (к носу)
	k.lathe("payload", xf, [Vector2(0.0, 0.0), Vector2(r * 0.55, 0.0), Vector2(r * 0.8, len * 0.06), Vector2(r, len * 0.16), Vector2(r, len * 0.68),
		Vector2(r * 0.9, len * 0.8), Vector2(r * 0.62, len * 0.92), Vector2(r * 0.3, len * 0.985)], 14, true)
	k.lathe("metal", xf * _at(Vector3(0, len * 0.98, 0)), [Vector2(r * 0.3, 0.0), Vector2(r * 0.3, len * 0.05), Vector2(r * 0.16, len * 0.09), Vector2(0.0, len * 0.095)], 10, false)
	for t: float in [0.3, 0.58]:
		k.lathe("dark", xf * _at(Vector3(0, len * t, 0)), [Vector2(r, 0.0), Vector2(r * 1.05, 0.001), Vector2(r * 1.05, len * 0.045), Vector2(r, len * 0.046)], 14, false)
	k.lathe("accent", xf * _at(Vector3(0, len * 0.72, 0)), [Vector2(r * 0.97, 0.0), Vector2(r * 1.0, 0.001), Vector2(r * 0.94, len * 0.05), Vector2(r * 0.9, len * 0.051)], 14, false)
	for f in 4:
		var fb := Basis(Vector3.BACK, f * PI * 0.5 + PI * 0.25)
		k.box("payload", Transform3D(fb, p + Vector3(0, 0, len * 0.44)) * _at(Vector3(r * 0.95, 0, 0)), Vector3(r * 0.9, 0.004, len * 0.2))


# ---------------- Самолёты ----------------

## Обтекатель винта (кок) и кольцо мотора. dir = −1 — тянущий винт на носу, +1 — толкающий сзади.
static func _spinner(k: Kit, p: Vector3, r: float, dir: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * dir), p)
	k.lathe("dark", xf * _at(Vector3(0, -r * 1.3, 0)), [Vector2(r * 1.05, 0.0), Vector2(r * 1.05, r * 1.3)], 14, false)
	k.lathe("accent", xf, [Vector2(r, 0.0), Vector2(r * 0.95, r * 0.6), Vector2(r * 0.7, r * 1.3), Vector2(r * 0.35, r * 1.8), Vector2(0.0, r * 2.0)], 14, true)


## Оптическая турель под носом.
static func _turret(k: Kit, p: Vector3, r: float) -> void:
	k.lathe("dark", _at(p + Vector3(0, r * 0.5, 0)), [Vector2(r * 0.8, 0.0), Vector2(r * 0.8, r * 0.9)], 12, false)
	k.ellip("plastic", _at(p), Vector3(r, r, r), 14, 9)
	k.tube("lens", p + Vector3(0, -r * 0.2, -r * 0.82), p + Vector3(0, -r * 0.22, -r * 1.02), r * 0.45, r * 0.4, 12)


static func _classic(k: Kit) -> Dictionary:
	# Высокоплан с тянущим винтом: веретённый фюзеляж, трапециевидное крыло, классическое оперение.
	k.loft("skin", _at(Vector3.ZERO), [[-0.86, 0.05, 0.05, 0.0], [-0.74, 0.085, 0.09, 0.0], [-0.45, 0.11, 0.125, 0.0], [-0.05, 0.108, 0.122, 0.0],
		[0.3, 0.078, 0.09, 0.012], [0.6, 0.042, 0.052, 0.028], [0.82, 0.016, 0.026, 0.04]], 18)
	k.loft("accent", _at(Vector3.ZERO), [[0.33, 0.0765, 0.088, 0.013], [0.4, 0.0685, 0.0795, 0.017]], 18, false)
	_spinner(k, Vector3(0, 0, -0.86), 0.045, -1.0)
	k.ellip("dark", _at(Vector3(0, 0.1, -0.5)), Vector3(0.05, 0.035, 0.17), 12, 6)            # обтекатель антенны
	for s: float in [-1.0, 1.0]:
		k.wing(["skin", "skin", "accent"], _at(Vector3(0, 0.09, 0.0)), [[0.0, 0.42, 0.058, -0.3, 0.0], [0.09, 0.42, 0.058, -0.3, 0.004],
			[1.0, 0.29, 0.036, -0.22, 0.06], [1.25, 0.24, 0.026, -0.19, 0.078]], s)
		k.wing(["skin"], _at(Vector3(0, 0.045, 0.0)), [[0.0, 0.25, 0.028, 0.56, 0.0], [0.46, 0.15, 0.018, 0.63, 0.0]], s)
		k.tube("dark", Vector3(s * 0.34, -0.03, -0.2), Vector3(s * 0.34, -0.03, 0.08), 0.014, 0.01, 8)   # пилоны-обтекатели
	k.fin(["skin", "accent"], _at(Vector3(0, 0.05, 0.0)), [[0.0, 0.3, 0.026, 0.5, 0.0], [0.24, 0.2, 0.02, 0.62, 0.0], [0.36, 0.15, 0.016, 0.68, 0.0]])
	_turret(k, Vector3(0, -0.12, -0.56), 0.05)
	_charge(k, Vector3(0, -0.17, -0.08), 0.052, 0.42)
	k.tube("dark", Vector3(0, -0.11, -0.2), Vector3(0, -0.13, -0.2), 0.02, 0.02, 8)
	k.tube("dark", Vector3(0, -0.1, 0.05), Vector3(0, -0.13, 0.05), 0.02, 0.02, 8)
	return {"props": [{"pos": Vector3(0, 0, -0.9), "radius": 0.28, "axis": 2, "dir": 1.0, "blades": 2}],
		"nav": [Vector3(1.26, 0.168, -0.07), Vector3(-1.26, 0.168, -0.07)], "strobe": Vector3(0, 0.42, 0.76), "scale": 1.6}


static func _flying_wing(k: Kit) -> Dictionary:
	# Стреловидное летающее крыло: центроплан-наплыв, законцовки-кили, толкающий винт.
	k.loft("skin", _at(Vector3.ZERO), [[-0.52, 0.0, 0.0, 0.0], [-0.47, 0.045, 0.035, 0.0], [-0.3, 0.1, 0.07, 0.005], [0.0, 0.135, 0.085, 0.01],
		[0.3, 0.1, 0.065, 0.012], [0.46, 0.05, 0.04, 0.012]], 18)
	k.ellip("dark", _at(Vector3(0, 0.075, -0.2)), Vector3(0.055, 0.03, 0.16), 12, 6)
	for s: float in [-1.0, 1.0]:
		k.wing(["skin", "skin", "accent"], _at(Vector3(0, 0.0, 0.0)), [[0.06, 0.66, 0.075, -0.34, 0.0], [0.5, 0.46, 0.05, -0.08, 0.012],
			[0.98, 0.3, 0.03, 0.2, 0.036], [1.2, 0.22, 0.02, 0.33, 0.05]], s)
		k.fin(["skin", "accent"], _at(Vector3(s * 1.2, 0.05, 0.0)), [[0.0, 0.22, 0.02, 0.33, 0.0], [0.15, 0.17, 0.016, 0.4, 0.0], [0.24, 0.13, 0.012, 0.45, 0.0]])
	k.lathe("dark", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.012, 0.44)), [Vector2(0.045, 0.0), Vector2(0.04, 0.07)], 12, false)
	_spinner(k, Vector3(0, 0.012, 0.535), 0.03, 1.0)
	_turret(k, Vector3(0, -0.07, -0.34), 0.042)
	_charge(k, Vector3(0, -0.12, 0.02), 0.055, 0.4)
	k.tube("dark", Vector3(0, -0.06, -0.08), Vector3(0, -0.075, -0.08), 0.02, 0.02, 8)
	k.tube("dark", Vector3(0, -0.06, 0.14), Vector3(0, -0.075, 0.14), 0.02, 0.02, 8)
	return {"props": [{"pos": Vector3(0, 0.012, 0.52), "radius": 0.24, "axis": 2, "dir": -1.0, "blades": 2}],
		"nav": [Vector3(1.2, 0.3, 0.52), Vector3(-1.2, 0.3, 0.52)], "strobe": Vector3(0, 0.1, 0.3), "scale": 1.6}


static func _twin_boom(k: Kit) -> Dictionary:
	# Двухбалочный разведчик: гондола, прямое крыло, балки с П-образным оперением, толкающий винт.
	k.loft("skin", _at(Vector3.ZERO), [[-0.74, 0.0, 0.0, -0.01], [-0.69, 0.05, 0.05, -0.01], [-0.5, 0.115, 0.115, 0.0], [-0.15, 0.135, 0.14, 0.01],
		[0.14, 0.11, 0.12, 0.02], [0.3, 0.06, 0.07, 0.025]], 18)
	k.loft("accent", _at(Vector3.ZERO), [[-0.02, 0.134, 0.139, 0.014], [0.05, 0.126, 0.132, 0.017]], 18, false)
	k.lathe("dark", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.025, 0.29)), [Vector2(0.055, 0.0), Vector2(0.045, 0.06)], 12, false)
	_spinner(k, Vector3(0, 0.025, 0.375), 0.032, 1.0)
	for s: float in [-1.0, 1.0]:
		k.wing(["skin", "skin", "accent"], _at(Vector3(0, 0.135, 0.0)), [[0.0, 0.38, 0.055, -0.36, 0.0], [0.42, 0.36, 0.05, -0.35, 0.008],
			[1.04, 0.31, 0.036, -0.32, 0.024], [1.3, 0.27, 0.028, -0.3, 0.032]], s)
		k.tube("carbon", Vector3(s * 0.42, 0.12, -0.3), Vector3(s * 0.42, 0.12, 1.02), 0.024, 0.016, 10)
		k.ellip("carbon", _at(Vector3(s * 0.42, 0.12, -0.3)), Vector3(0.024, 0.024, 0.06), 10, 6)
		k.fin(["skin", "accent"], _at(Vector3(s * 0.42, 0.12, 0.0)), [[0.0, 0.24, 0.022, 0.8, 0.0], [0.2, 0.19, 0.018, 0.86, 0.0], [0.3, 0.16, 0.014, 0.89, 0.0]])
		k.wing(["skin"], _at(Vector3(0, 0.4, 0.0)), [[0.0, 0.17, 0.02, 0.88, 0.0], [0.44, 0.17, 0.02, 0.88, 0.0]], s)
		k.tube("dark", Vector3(s * 0.09, -0.1, -0.3), Vector3(s * 0.16, -0.2, -0.3), 0.008, 0.008, 6)   # шасси-лыжи
		k.tube("dark", Vector3(s * 0.16, -0.2, -0.42), Vector3(s * 0.16, -0.2, -0.12), 0.01, 0.01, 6)
	_turret(k, Vector3(0, -0.125, -0.5), 0.05)
	_charge(k, Vector3(0, -0.175, -0.12), 0.05, 0.4)
	k.tube("dark", Vector3(0, -0.11, -0.22), Vector3(0, -0.135, -0.22), 0.02, 0.02, 8)
	k.tube("dark", Vector3(0, -0.105, 0.0), Vector3(0, -0.135, 0.0), 0.02, 0.02, 8)
	return {"props": [{"pos": Vector3(0, 0.025, 0.36), "radius": 0.27, "axis": 2, "dir": 1.0, "blades": 3}],
		"nav": [Vector3(1.31, 0.17, -0.16), Vector3(-1.31, 0.17, -0.16)], "strobe": Vector3(0, 0.425, 0.97), "scale": 1.6}


static func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


## Сборщик сетки: по SurfaceTool на материал, нормали задаются явно,
## обход треугольника подбирается под внешнюю нормаль (работает и с зеркалом).
class Kit:
	var tools := {}

	func _st(mat: String) -> SurfaceTool:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		return tools[mat]

	func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		var st := _st(mat)
		var out := na + nb + nc
		if (b - a).cross(c - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		st.set_normal(na)
		st.add_vertex(a)
		st.set_normal(nb)
		st.add_vertex(b)
		st.set_normal(nc)
		st.add_vertex(c)

	func flat(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
		var nn := n.normalized()
		tri(mat, a, b, c, nn, nn, nn)

	func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		flat(mat, a, b, c, n)
		flat(mat, a, c, d, n)

	func box(mat: String, xf: Transform3D, size: Vector3) -> void:
		var h := size * 0.5
		var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
			[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
		for f in faces:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var c := n * h
			var du := u * h
			var dv := v * h
			var p := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
			var wn := (xf.basis * n).normalized()
			quad(mat, xf * p[0], xf * p[1], xf * p[2], xf * p[3], wn)

	## Усечённый конус вдоль локальной +Y от 0 до h (h < 0 — вниз) с крышками.
	func cyl(mat: String, xf: Transform3D, r0: float, r1: float, h: float, seg: int) -> void:
		var bas := xf.basis
		var slope := (r0 - r1) / absf(h) if absf(h) > 0.0001 else 0.0
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var p0 := xf * (d0 * r0)
			var p1 := xf * (d1 * r0)
			var q0 := xf * (d0 * r1 + Vector3(0, h, 0))
			var q1 := xf * (d1 * r1 + Vector3(0, h, 0))
			var n0 := (bas * (d0 + Vector3(0, slope * signf(h), 0))).normalized()
			var n1 := (bas * (d1 + Vector3(0, slope * signf(h), 0))).normalized()
			tri(mat, p0, q0, p1, n0, n0, n1)
			tri(mat, p1, q0, q1, n1, n0, n1)
			var up := (bas * Vector3(0, signf(h), 0)).normalized()
			var c0 := xf * Vector3.ZERO
			var c1 := xf * Vector3(0, h, 0)
			flat(mat, c0, p1, p0, -up)
			if r1 > 0.0:
				flat(mat, c1, q0, q1, up)

	## Эллипсоид с гладкими нормалями.
	func ellip(mat: String, xf: Transform3D, r: Vector3, seg_u: int, seg_v: int) -> void:
		var pts := []
		var nrm := []
		for j in seg_v + 1:
			var th := PI * j / seg_v
			for i in seg_u + 1:
				var ph := TAU * i / seg_u
				var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				pts.append(xf * (u * r))
				nrm.append((xf.basis * Vector3(u.x / r.x, u.y / r.y, u.z / r.z)).normalized())
		var w := seg_u + 1
		for j in seg_v:
			for i in seg_u:
				var a := j * w + i
				var b := a + 1
				var c := a + w
				var d := c + 1
				if j > 0:
					tri(mat, pts[a], pts[b], pts[c], nrm[a], nrm[b], nrm[c])
				if j < seg_v - 1:
					tri(mat, pts[b], pts[d], pts[c], nrm[b], nrm[d], nrm[c])

	## Тор в локальной плоскости XZ.
	func torus(mat: String, xf: Transform3D, big_r: float, small_r: float, seg: int, seg2: int) -> void:
		for i in seg:
			for j in seg2:
				var q := []
				var nn := []
				for di in 2:
					for dj in 2:
						var a := TAU * (i + di) / seg
						var b := TAU * (j + dj) / seg2
						var ring := Vector3(cos(a), 0, sin(a))
						var n := ring * cos(b) + Vector3(0, sin(b), 0)
						q.append(xf * (ring * big_r + n * small_r))
						nn.append((xf.basis * n).normalized())
				tri(mat, q[0], q[1], q[2], nn[0], nn[1], nn[2])
				tri(mat, q[1], q[3], q[2], nn[1], nn[3], nn[2])

	## Скруглённая (с фасками) коробка.
	func rbox(mat: String, xf: Transform3D, size: Vector3, bevel: float) -> void:
		var h := size * 0.5
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
		var bas := xf.basis
		var signs: Array[float] = [-1.0, 1.0]
		for sx in signs:
			for sy in signs:
				for sz in signs:
					var vx := xf * Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
					var vy := xf * Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
					var vz := xf * Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
					flat(mat, vx, vy, vz, bas * Vector3(sx, sy, sz))
		for s in signs:
			quad(mat, xf * Vector3(s * h.x, -h.y + b, -h.z + b), xf * Vector3(s * h.x, h.y - b, -h.z + b),
				xf * Vector3(s * h.x, h.y - b, h.z - b), xf * Vector3(s * h.x, -h.y + b, h.z - b), bas * Vector3(s, 0, 0))
			quad(mat, xf * Vector3(-h.x + b, s * h.y, -h.z + b), xf * Vector3(h.x - b, s * h.y, -h.z + b),
				xf * Vector3(h.x - b, s * h.y, h.z - b), xf * Vector3(-h.x + b, s * h.y, h.z - b), bas * Vector3(0, s, 0))
			quad(mat, xf * Vector3(-h.x + b, -h.y + b, s * h.z), xf * Vector3(h.x - b, -h.y + b, s * h.z),
				xf * Vector3(h.x - b, h.y - b, s * h.z), xf * Vector3(-h.x + b, h.y - b, s * h.z), bas * Vector3(0, 0, s))
		for s1 in signs:
			for s2 in signs:
				quad(mat, xf * Vector3(s1 * h.x, s2 * (h.y - b), -h.z + b), xf * Vector3(s1 * h.x, s2 * (h.y - b), h.z - b),
					xf * Vector3(s1 * (h.x - b), s2 * h.y, h.z - b), xf * Vector3(s1 * (h.x - b), s2 * h.y, -h.z + b), bas * Vector3(s1, s2, 0))
				quad(mat, xf * Vector3(s1 * h.x, -h.y + b, s2 * (h.z - b)), xf * Vector3(s1 * h.x, h.y - b, s2 * (h.z - b)),
					xf * Vector3(s1 * (h.x - b), h.y - b, s2 * h.z), xf * Vector3(s1 * (h.x - b), -h.y + b, s2 * h.z), bas * Vector3(s1, 0, s2))
				quad(mat, xf * Vector3(-h.x + b, s1 * h.y, s2 * (h.z - b)), xf * Vector3(h.x - b, s1 * h.y, s2 * (h.z - b)),
					xf * Vector3(h.x - b, s1 * (h.y - b), s2 * h.z), xf * Vector3(-h.x + b, s1 * (h.y - b), s2 * h.z), bas * Vector3(0, s1, s2))

	## Плита по контуру в локальной плоскости XZ (точки — (x, z)), толщина по Y вокруг нуля.
	func plate(mat: String, xf: Transform3D, outline: PackedVector2Array, thick: float) -> void:
		var up := (xf.basis * Vector3.UP).normalized()
		var idx := Geometry2D.triangulate_polygon(outline)
		var h := thick * 0.5
		for i in range(0, idx.size(), 3):
			var a := outline[idx[i]]
			var b := outline[idx[i + 1]]
			var c := outline[idx[i + 2]]
			flat(mat, xf * Vector3(a.x, h, a.y), xf * Vector3(b.x, h, b.y), xf * Vector3(c.x, h, c.y), up)
			flat(mat, xf * Vector3(a.x, -h, a.y), xf * Vector3(b.x, -h, b.y), xf * Vector3(c.x, -h, c.y), -up)
		var area := 0.0
		var n := outline.size()
		for i in n:
			area += outline[i].cross(outline[(i + 1) % n])
		for i in n:
			var a := outline[i]
			var b := outline[(i + 1) % n]
			var e := (b - a).normalized()
			var o := Vector2(e.y, -e.x) * signf(area)
			quad(mat, xf * Vector3(a.x, -h, a.y), xf * Vector3(b.x, -h, b.y), xf * Vector3(b.x, h, b.y), xf * Vector3(a.x, h, a.y), xf.basis * Vector3(o.x, 0, o.y))

	## Тело вращения вокруг локальной оси Y. Профиль — точки (радиус, высота), обход так,
	## чтобы наружная сторона была справа (снизу вверх по внешней стенке). smooth — сглаживать
	## нормали вдоль профиля (обтекаемые формы) или оставить грани (точёные детали).
	func lathe(mat: String, xf: Transform3D, prof: Array, seg: int, smooth := false) -> void:
		var m := prof.size()
		var seg_n: Array[Vector2] = []
		for i in m - 1:
			var t: Vector2 = prof[i + 1] - prof[i]
			seg_n.append(Vector2(t.y, -t.x).normalized() if t.length() > 0.000001 else Vector2.RIGHT)
		var bas := xf.basis
		for i in m - 1:
			var p0: Vector2 = prof[i]
			var p1: Vector2 = prof[i + 1]
			var n0: Vector2 = seg_n[i]
			var n1: Vector2 = seg_n[i]
			if smooth:
				if i > 0:
					n0 = (seg_n[i - 1] + seg_n[i]).normalized()
				if i < m - 2:
					n1 = (seg_n[i] + seg_n[i + 1]).normalized()
			for j in seg:
				var a0 := TAU * j / seg
				var a1 := TAU * (j + 1) / seg
				var d0 := Vector3(cos(a0), 0, sin(a0))
				var d1 := Vector3(cos(a1), 0, sin(a1))
				var v00 := xf * (d0 * p0.x + Vector3(0, p0.y, 0))
				var v01 := xf * (d1 * p0.x + Vector3(0, p0.y, 0))
				var v10 := xf * (d0 * p1.x + Vector3(0, p1.y, 0))
				var v11 := xf * (d1 * p1.x + Vector3(0, p1.y, 0))
				var m00 := (bas * (d0 * n0.x + Vector3(0, n0.y, 0))).normalized()
				var m01 := (bas * (d1 * n0.x + Vector3(0, n0.y, 0))).normalized()
				var m10 := (bas * (d0 * n1.x + Vector3(0, n1.y, 0))).normalized()
				var m11 := (bas * (d1 * n1.x + Vector3(0, n1.y, 0))).normalized()
				if p0.x > 0.00001:
					tri(mat, v00, v10, v01, m00, m10, m01)
				if p1.x > 0.00001:
					tri(mat, v01, v10, v11, m01, m10, m11)

	## Труба (усечённый конус) между двумя точками с торцами.
	func tube(mat: String, a: Vector3, b: Vector3, r0: float, r1: float, seg: int) -> void:
		var y := (b - a).normalized()
		var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var len := a.distance_to(b)
		lathe(mat, Transform3D(Basis(x, y, x.cross(y)), a), [Vector2(0.0, 0.0), Vector2(r0, 0.0), Vector2(r1, len), Vector2(0.0, len)], seg, false)

	## Лофт вдоль Z из эллиптических сечений [z, rx, ry, сдвиг по y] с гладкими нормалями.
	func loft(mat: String, xf: Transform3D, secs: Array, seg: int, caps := true) -> void:
		var m := secs.size()
		var pts := []
		var nrm := []
		for i in m:
			var s: Array = secs[i]
			var prev: Array = secs[maxi(i - 1, 0)]
			var next: Array = secs[mini(i + 1, m - 1)]
			var dz: float = maxf(next[0] - prev[0], 0.0001)
			var slope: float = -((next[1] + next[2]) - (prev[1] + prev[2])) * 0.5 / dz
			var ring_p := []
			var ring_n := []
			for j in seg:
				var a := TAU * j / seg
				var rx: float = maxf(s[1], 0.0)
				var ry: float = maxf(s[2], 0.0)
				ring_p.append(xf * Vector3(rx * cos(a), s[3] + ry * sin(a), s[0]))
				var n := Vector3(cos(a) / maxf(rx, 0.001), sin(a) / maxf(ry, 0.001), 0.0).normalized()
				if rx < 0.0005:
					n = Vector3(0, 0, -1.0 if i == 0 else 1.0)
				else:
					n = (n + Vector3(0, 0, slope)).normalized()
				ring_n.append((xf.basis * n).normalized())
			pts.append(ring_p)
			nrm.append(ring_n)
		for i in m - 1:
			for j in seg:
				var j1 := (j + 1) % seg
				if secs[i][1] > 0.0005:
					tri(mat, pts[i][j], pts[i + 1][j], pts[i][j1], nrm[i][j], nrm[i + 1][j], nrm[i][j1])
				if secs[i + 1][1] > 0.0005:
					tri(mat, pts[i][j1], pts[i + 1][j], pts[i + 1][j1], nrm[i][j1], nrm[i + 1][j], nrm[i + 1][j1])
		if not caps:
			return
		for e: int in [0, m - 1]:
			if secs[e][1] <= 0.0005:
				continue
			var c: Vector3 = xf * Vector3(0, secs[e][3], secs[e][0])
			var out := (xf.basis * Vector3(0, 0, -1.0 if e == 0 else 1.0)).normalized()
			for j in seg:
				flat(mat, c, pts[e][j], pts[e][(j + 1) % seg], out)

	## Консоль крыла из сечений [размах x, хорда, толщина, z передней кромки, y] от корня к законцовке.
	## side = ±1 — правая/левая. mats[i] — материал панели между сечениями i и i+1.
	func wing(mats: Array, xf: Transform3D, secs: Array, side: float) -> void:
		var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.025, 0.36), Vector2(0.09, 0.6), Vector2(0.25, 0.72), Vector2(0.45, 0.66),
			Vector2(0.72, 0.38), Vector2(1.0, 0.02), Vector2(0.72, -0.14), Vector2(0.45, -0.24), Vector2(0.25, -0.28), Vector2(0.09, -0.24), Vector2(0.025, -0.16)]
		var pn := prof.size()
		var rings := []
		var norms := []
		for s: Array in secs:
			var ring := []
			var nr := []
			for i in pn:
				var p := prof[i]
				ring.append(xf * Vector3(s[0] * side, s[4] + p.y * s[2], s[3] + p.x * s[1]))
				var a := prof[(i + pn - 1) % pn]
				var b := prof[(i + 1) % pn]
				var t := Vector2((b.x - a.x) * s[1], (b.y - a.y) * s[2])   # (dz, dy)
				nr.append((xf.basis * Vector3(0, t.x, -t.y)).normalized())
			rings.append(ring)
			norms.append(nr)
		for s in secs.size() - 1:
			var mat: String = mats[mini(s, mats.size() - 1)]
			for i in pn:
				var i1 := (i + 1) % pn
				tri(mat, rings[s][i], rings[s + 1][i], rings[s][i1], norms[s][i], norms[s + 1][i], norms[s][i1])
				tri(mat, rings[s][i1], rings[s + 1][i], rings[s + 1][i1], norms[s][i1], norms[s + 1][i], norms[s + 1][i1])
		for e: int in [0, secs.size() - 1]:
			var cap: Array = rings[e]
			var cc := Vector3.ZERO
			for p in cap:
				cc += p
			cc /= pn
			var out := (xf.basis * Vector3(side if e > 0 else -side, 0, 0)).normalized()
			var mat: String = mats[mini(maxi(e - 1, 0), mats.size() - 1)]
			for i in pn:
				flat(mat, cc, cap[i], cap[(i + 1) % pn], out)

	## Киль: те же сечения, что у крыла, но «размах» идёт вверх от точки.
	func fin(mats: Array, xf: Transform3D, secs: Array) -> void:
		wing(mats, Transform3D(xf.basis * Basis(Vector3.BACK, PI * 0.5), xf.origin), secs, 1.0)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var names := []
		for mname in DroneModels.MATS:
			if tools.has(mname):
				tools[mname].commit(mesh)
				names.append(mname)
		mesh.set_meta("mats", names)
		return mesh
