class_name DroneModels
## Процедурные модели дронов: по три варианта коптера и самолёта. Только внешний вид —
## хитбокс и физика общие для типа. Геометрия собирается из примитивов (капсулы, цилиндры,
## торы, профили крыла) в одну сетку с отдельной поверхностью на материал.
## Нос дрона смотрит в −Z, верх — +Y. Меши кэшируются по (тип, модель).

const MATS := ["carbon", "plastic", "skin", "metal", "lens", "payload", "accent"]

static var _mesh_cache := {}
static var _mats := {}
static var _accent_mats := {}


## Результат: {"mesh": ArrayMesh, "props": [{pos, radius, axis: 0 (Y) / 2 (Z), dir}],
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


## Материалы поверхностей сетки по порядку Kit.surfaces (accent — цвет стороны).
static func material(name: String, color := Color.WHITE) -> Material:
	if name == "accent":
		var ck := color.to_html()
		if not _accent_mats.has(ck):
			var a := StandardMaterial3D.new()
			a.albedo_color = color
			a.roughness = 0.5
			a.emission_enabled = true
			a.emission = color
			a.emission_energy_multiplier = 0.6
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
	var carbon := StandardMaterial3D.new()
	carbon.albedo_color = Color(0.07, 0.07, 0.08)
	carbon.metallic = 0.25
	carbon.roughness = 0.45
	carbon.roughness_texture = rough
	carbon.uv1_triplanar = true
	carbon.uv1_scale = Vector3(14, 14, 14)
	carbon.clearcoat_enabled = true
	carbon.clearcoat = 0.6
	carbon.clearcoat_roughness = 0.25
	_mats.carbon = carbon
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.26, 0.27, 0.25)
	plastic.roughness = 0.62
	_mats.plastic = plastic
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.56, 0.58, 0.55)
	skin.roughness = 0.55
	skin.roughness_texture = rough
	skin.uv1_triplanar = true
	skin.uv1_scale = Vector3(3, 3, 3)
	_mats.skin = skin
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.62, 0.64)
	metal.metallic = 0.9
	metal.roughness = 0.28
	_mats.metal = metal
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.02, 0.03, 0.05)
	lens.metallic = 0.6
	lens.roughness = 0.05
	lens.emission_enabled = true
	lens.emission = Color(0.1, 0.25, 0.4)
	lens.emission_energy_multiplier = 0.4
	_mats.lens = lens
	var payload := StandardMaterial3D.new()
	payload.albedo_color = Color(0.31, 0.33, 0.23)
	payload.roughness = 0.8
	_mats.payload = payload


# ---------------- Коптеры ----------------

static func _quad_x(k: Kit) -> Dictionary:
	# Две карбоновые пластины, стойки, X-рама, АКБ с ремешком сверху, камера, антенна, заряд.
	k.box("carbon", _at(Vector3(0, 0, 0)), Vector3(0.20, 0.012, 0.30))
	k.box("carbon", _at(Vector3(0, 0.055, 0)), Vector3(0.16, 0.01, 0.24))
	for x in [-0.07, 0.07]:
		for z in [-0.1, 0.1]:
			k.cyl("metal", _at(Vector3(x, 0.006, z)), 0.007, 0.007, 0.05, 6)
	var props := []
	var nav := []
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var dir := Vector3(sin(a), 0, -cos(a))
		var tip := dir * 0.32
		k.box("carbon", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), dir * 0.17 + Vector3(0, -0.002, 0)), Vector3(0.30, 0.016, 0.034))
		_motor(k, tip, 0.032)
		props.append({"pos": tip + Vector3(0, 0.062, 0), "radius": 0.155, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0})
		if dir.z > 0.0:
			nav.append(tip + Vector3(0, -0.012, 0) + dir * 0.03)
	k.box("plastic", _at(Vector3(0, 0.092, 0.02)), Vector3(0.075, 0.06, 0.15))     # АКБ
	k.box("accent", _at(Vector3(0, 0.093, 0.02)), Vector3(0.082, 0.064, 0.022))   # ремешок
	_fpv_cam(k, Vector3(0, 0.03, -0.15), 0.03)
	k.cyl("metal", Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.06, 0.13)), 0.004, 0.003, 0.13, 5)
	k.ellip("plastic", _at(Vector3(0, 0.06 + 0.13 * cos(0.5), 0.13 + 0.13 * sin(0.5))), Vector3(0.012, 0.02, 0.012), 6, 4)
	_charge(k, Vector3(0, -0.07, 0), 0.05, 0.2)
	return {"props": props, "nav": nav, "strobe": Vector3(0, -0.012, 0.15), "scale": 1.4}


static func _racer(k: Kit) -> Dictionary:
	# Обтекаемый корпус-капсула, короткие лучи, кольцевая защита винтов.
	k.ellip("plastic", _at(Vector3(0, 0.025, 0)), Vector3(0.085, 0.05, 0.17), 14, 8)
	k.ellip("accent", _at(Vector3(0, 0.05, 0.02)), Vector3(0.05, 0.035, 0.13), 10, 6)
	var props := []
	var nav := []
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var dir := Vector3(sin(a), 0, -cos(a))
		var tip := dir * 0.26
		k.box("carbon", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), dir * 0.15), Vector3(0.22, 0.022, 0.04))
		_motor(k, tip, 0.028)
		k.torus("carbon", _at(tip + Vector3(0, 0.05, 0)), 0.15, 0.011, 24, 6)
		for s in 3:
			var b := a + PI + (s - 1) * 0.9
			var sd := Vector3(sin(b), 0, -cos(b))
			k.box("carbon", Transform3D(Basis(Vector3.UP, -b + PI * 0.5), tip + sd * 0.075 + Vector3(0, 0.05, 0)), Vector3(0.14, 0.008, 0.01))
		props.append({"pos": tip + Vector3(0, 0.055, 0), "radius": 0.135, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0})
		if dir.z > 0.0:
			nav.append(tip + dir * 0.16 + Vector3(0, 0.05, 0))
	_fpv_cam(k, Vector3(0, 0.035, -0.17), 0.028)
	k.cyl("metal", Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(0, 0.07, 0.12)), 0.004, 0.003, 0.1, 5)
	_charge(k, Vector3(0, -0.055, 0.0), 0.04, 0.16)
	return {"props": props, "nav": nav, "strobe": Vector3(0, 0.075, 0.12), "scale": 1.4}


static func _hexa(k: Kit) -> Dictionary:
	# Круглая центральная плита, шесть длинных лучей, посадочные опоры, крупный заряд.
	k.cyl("carbon", _at(Vector3(0, 0, 0)), 0.13, 0.13, 0.014, 6)
	k.cyl("carbon", _at(Vector3(0, 0.05, 0)), 0.11, 0.11, 0.012, 6)
	k.ellip("plastic", _at(Vector3(0, 0.08, 0)), Vector3(0.09, 0.045, 0.09), 12, 6)
	k.torus("accent", _at(Vector3(0, 0.07, 0)), 0.09, 0.008, 18, 5)
	var props := []
	var nav := []
	for i in 6:
		var a := i * TAU / 6.0 + PI / 6.0
		var dir := Vector3(sin(a), 0, -cos(a))
		var tip := dir * 0.42
		k.cyl("carbon", Transform3D(Basis(Vector3.UP, -a).rotated(dir.cross(Vector3.UP).normalized(), 0.0) * Basis(Vector3.RIGHT, -PI * 0.5), dir * 0.1 + Vector3(0, 0.008, 0)), 0.013, 0.013, 0.32, 8)
		_motor(k, tip + Vector3(0, 0.0, 0), 0.034)
		props.append({"pos": tip + Vector3(0, 0.065, 0), "radius": 0.17, "axis": 0, "dir": 1.0 if i % 2 == 0 else -1.0})
		if dir.z > 0.3:
			nav.append(tip + Vector3(0, -0.01, 0) + dir * 0.04)
	for s in [-1.0, 1.0]:
		k.cyl("carbon", Transform3D(Basis(Vector3.BACK, s * 0.35), Vector3(s * 0.06, 0.0, 0)), 0.008, 0.008, -0.17, 6)
		k.cyl("carbon", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.12, -0.16, -0.12)), 0.009, 0.009, 0.24, 6)
	_fpv_cam(k, Vector3(0, 0.03, -0.14), 0.032)
	_charge(k, Vector3(0, -0.075, 0), 0.06, 0.24)
	return {"props": props, "nav": nav, "strobe": Vector3(0, 0.125, 0), "scale": 1.3}


static func _motor(k: Kit, p: Vector3, r: float) -> void:
	k.cyl("metal", _at(p + Vector3(0, 0.005, 0)), r, r, 0.035, 12)
	k.cyl("carbon", _at(p + Vector3(0, 0.04, 0)), r * 0.85, r * 0.6, 0.012, 10)
	k.cyl("metal", _at(p + Vector3(0, 0.05, 0)), 0.006, 0.006, 0.015, 6)


static func _fpv_cam(k: Kit, p: Vector3, r: float) -> void:
	k.box("plastic", _at(p), Vector3(r * 1.8, r * 1.8, r * 1.4))
	var b := Basis(Vector3.RIGHT, -PI * 0.5 + deg_to_rad(18.0))
	k.cyl("carbon", Transform3D(b, p + Vector3(0, r * 0.9, -r * 0.6)), r * 0.65, r * 0.6, r * 0.7, 12)
	k.cyl("lens", Transform3D(b, p + Vector3(0, r * 0.9 + r * 0.22, -r * 0.6 - r * 0.67)), r * 0.45, r * 0.4, r * 0.08, 12)


static func _charge(k: Kit, p: Vector3, r: float, len: float) -> void:
	# Цилиндрический заряд с оперением, лежит вдоль корпуса.
	var b := Basis(Vector3.RIGHT, -PI * 0.5)
	k.cyl("payload", Transform3D(b, p + Vector3(0, 0, len * 0.4)), r, r, len * 0.8, 12)
	k.ellip("payload", _at(p + Vector3(0, 0, -len * 0.4)), Vector3(r, r, r * 1.6), 12, 6)
	k.box("accent", _at(p + Vector3(0, -r * 0.05, 0)), Vector3(r * 2.1, r * 2.1, 0.012))
	for f in 4:
		var fb := Basis(Vector3.BACK, f * PI * 0.5 + PI * 0.25)
		k.box("payload", Transform3D(fb, p + Vector3(0, 0, len * 0.42)) * Transform3D(Basis(), Vector3(r * 1.2, 0, 0)), Vector3(r * 1.0, 0.006, len * 0.25))


# ---------------- Самолёты ----------------

static func _classic(k: Kit) -> Dictionary:
	# Фюзеляж-веретено, трапециевидное крыло, классическое оперение, тянущий винт.
	k.ellip("skin", _at(Vector3(0, 0, -0.1)), Vector3(0.13, 0.13, 0.85), 16, 10)
	k.ellip("lens", _at(Vector3(0, 0.07, -0.55)), Vector3(0.07, 0.06, 0.16), 10, 6)
	k.wing("skin", _at(Vector3(0, 0.04, -0.15)), 1.25, 0.46, 0.26, 0.045, 0.08, 0.04, 1.0)
	k.wing("skin", _at(Vector3(0, 0.04, -0.15)), 1.25, 0.46, 0.26, 0.045, 0.08, 0.04, -1.0)
	k.wing("accent", _at(Vector3(0.95, 0.072, -0.07)), 0.3, 0.3, 0.26, 0.012, 0.08 * 0.24, 0.01, 1.0)
	k.wing("accent", _at(Vector3(-0.95, 0.072, -0.07)), 0.3, 0.3, 0.26, 0.012, 0.08 * 0.24, 0.01, -1.0)
	k.wing("skin", _at(Vector3(0, 0.02, 0.6)), 0.45, 0.24, 0.15, 0.025, 0.06, 0.0, 1.0)
	k.wing("skin", _at(Vector3(0, 0.02, 0.6)), 0.45, 0.24, 0.15, 0.025, 0.06, 0.0, -1.0)
	k.fin("accent", _at(Vector3(0, 0.06, 0.58)), 0.36, 0.28, 0.14, 0.025, 0.12)
	k.cyl("metal", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.95)), 0.04, 0.03, 0.06, 10)
	k.ellip("plastic", _at(Vector3(0, 0, -1.0)), Vector3(0.04, 0.04, 0.06), 10, 6)
	_fpv_cam(k, Vector3(0, -0.11, -0.6), 0.035)
	_charge(k, Vector3(0, -0.17, -0.1), 0.055, 0.42)
	return {"props": [{"pos": Vector3(0, 0, -0.99), "radius": 0.28, "axis": 2, "dir": 1.0}],
		"nav": [Vector3(1.25, 0.06, -0.08), Vector3(-1.25, 0.06, -0.08)], "strobe": Vector3(0, 0.42, 0.7), "scale": 1.6}


static func _flying_wing(k: Kit) -> Dictionary:
	# Стреловидное летающее крыло с килями-законцовками и толкающим винтом.
	k.ellip("skin", _at(Vector3(0, 0.02, -0.05)), Vector3(0.16, 0.09, 0.55), 16, 8)
	k.ellip("lens", _at(Vector3(0, 0.07, -0.35)), Vector3(0.07, 0.05, 0.14), 10, 6)
	k.wing("skin", _at(Vector3(0, 0.0, -0.3)), 1.2, 0.72, 0.24, 0.06, 0.62, 0.05, 1.0)
	k.wing("skin", _at(Vector3(0, 0.0, -0.3)), 1.2, 0.72, 0.24, 0.06, 0.62, 0.05, -1.0)
	k.wing("accent", _at(Vector3(0, 0.035, -0.3)), 0.6, 0.12, 0.08, 0.008, 0.31, 0.025, 1.0)
	k.wing("accent", _at(Vector3(0, 0.035, -0.3)), 0.6, 0.12, 0.08, 0.008, 0.31, 0.025, -1.0)
	for s in [-1.0, 1.0]:
		k.fin("skin", _at(Vector3(s * 1.2, 0.05, 0.32)), 0.24, 0.24, 0.14, 0.02, 0.1)
	k.cyl("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.47)), 0.035, 0.03, 0.07, 10)
	_fpv_cam(k, Vector3(0, -0.06, -0.48), 0.032)
	_charge(k, Vector3(0, -0.11, -0.02), 0.06, 0.4)
	return {"props": [{"pos": Vector3(0, 0.02, 0.56), "radius": 0.24, "axis": 2, "dir": -1.0}],
		"nav": [Vector3(1.22, 0.3, 0.4), Vector3(-1.22, 0.3, 0.4)], "strobe": Vector3(0, -0.07, 0.3), "scale": 1.6}


static func _twin_boom(k: Kit) -> Dictionary:
	# Гондола, прямое крыло, две хвостовые балки с П-образным оперением, толкающий винт.
	k.ellip("skin", _at(Vector3(0, 0.02, -0.25)), Vector3(0.14, 0.14, 0.55), 16, 10)
	k.ellip("lens", _at(Vector3(0, 0.1, -0.5)), Vector3(0.08, 0.06, 0.18), 10, 6)
	k.wing("skin", _at(Vector3(0, 0.1, -0.2)), 1.3, 0.38, 0.3, 0.04, 0.03, 0.03, 1.0)
	k.wing("skin", _at(Vector3(0, 0.1, -0.2)), 1.3, 0.38, 0.3, 0.04, 0.03, 0.03, -1.0)
	for s in [-1.0, 1.0]:
		k.cyl("carbon", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * 0.42, 0.1, -0.25)), 0.025, 0.02, 1.3, 10)
		k.fin("skin", _at(Vector3(s * 0.42, 0.12, 0.9)), 0.3, 0.22, 0.14, 0.02, 0.08)
		k.wing("accent", _at(Vector3(s * 1.0, 0.126, -0.17)), 0.3, 0.33, 0.3, 0.01, 0.007, 0.01, s)
	k.wing("skin", _at(Vector3(0, 0.39, 0.93)), 0.42, 0.18, 0.18, 0.02, 0.0, 0.0, 1.0)
	k.wing("skin", _at(Vector3(0, 0.39, 0.93)), 0.42, 0.18, 0.18, 0.02, 0.0, 0.0, -1.0)
	k.cyl("metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.28)), 0.04, 0.03, 0.08, 10)
	_fpv_cam(k, Vector3(0, -0.1, -0.68), 0.036)
	_charge(k, Vector3(0, -0.16, -0.2), 0.06, 0.44)
	return {"props": [{"pos": Vector3(0, 0.02, 0.37), "radius": 0.27, "axis": 2, "dir": 1.0}],
		"nav": [Vector3(1.3, 0.13, -0.15), Vector3(-1.3, 0.13, -0.15)], "strobe": Vector3(0, 0.42, 0.98), "scale": 1.6}


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

	## Консоль крыла от корня (x = 0) к законцовке (x = side·span): трапеция с профилем-«линзой»,
	## стреловидность sweep (сдвиг законцовки назад), поперечное V dihedral (подъём законцовки).
	func wing(mat: String, xf: Transform3D, span: float, root: float, tip: float, thick: float, sweep: float, dihedral: float, side: float) -> void:
		var prof := [Vector2(0.0, 0.0), Vector2(0.12, 0.6), Vector2(0.4, 1.0), Vector2(0.75, 0.55), Vector2(1.0, 0.0),
			Vector2(0.75, -0.3), Vector2(0.4, -0.45), Vector2(0.12, -0.3)]
		var sec := []
		for s in 2:
			var x := span * s * side
			var chord: float = root if s == 0 else tip
			var th: float = thick if s == 0 else thick * tip / root
			var z0 := -root * 0.35 + (sweep if s == 1 else 0.0)
			var y0 := dihedral if s == 1 else 0.0
			var ring := []
			for p in prof:
				ring.append(xf * Vector3(x, y0 + p.y * th * 0.5, z0 + p.x * chord))
			sec.append(ring)
		var m := prof.size()
		for i in m:
			var a: Vector3 = sec[0][i]
			var b: Vector3 = sec[0][(i + 1) % m]
			var c: Vector3 = sec[1][(i + 1) % m]
			var d: Vector3 = sec[1][i]
			var mid := (a + b + c + d) * 0.25
			var center: Vector3 = (sec[0][2] + sec[0][6] + sec[1][2] + sec[1][6]) * 0.25
			var n := (b - a).cross(d - a)
			if n.dot(mid - center) < 0.0:
				n = -n
			quad(mat, a, b, c, d, n)
		for s in 2:
			var cap: Array = sec[s]
			var cc := Vector3.ZERO
			for p in cap:
				cc += p
			cc /= m
			var out := (xf.basis * Vector3(side if s == 1 else -side, 0, 0)).normalized()
			for i in m:
				flat(mat, cc, cap[i], cap[(i + 1) % m], out)

	## Киль: вертикальная трапеция вверх от точки (высота h, хорды у корня и верха).
	func fin(mat: String, xf: Transform3D, h: float, root: float, tip: float, thick: float, sweep: float) -> void:
		var b := Basis(Vector3.BACK, PI * 0.5)
		wing(mat, Transform3D(xf.basis * b, xf.origin), h, root, tip, thick, sweep, 0.0, 1.0)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var names := []
		for mname in DroneModels.MATS:
			if tools.has(mname):
				tools[mname].commit(mesh)
				names.append(mname)
		mesh.set_meta("mats", names)
		return mesh
