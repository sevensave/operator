extends RefCounted
## Помощь пилоту: удержание высоты, упреждение, автозахват.

var t

const FACE_X := -PI / 2.0   # рыск, при котором нос смотрит на +X


func _drone(kind: int, pos: Vector3, vel: Vector3) -> DroneState:
	var d := DroneState.new()
	d.kind = kind
	d.pos = pos
	d.vel = vel
	return d


func test_lead_point_crossing_target_is_ahead() -> void:
	var me := _drone(SimConst.Kind.COPTER, Vector3.ZERO, Vector3.ZERO)
	var tg := _drone(SimConst.Kind.COPTER, Vector3(0, 0, -80), Vector3(20, 0, 0))
	var p := PilotAssist.lead_point(me, tg)
	t.check(p.x > tg.pos.x + 10.0, "упреждение впереди цели по ходу: %s" % p)
	t.check(p.x <= tg.pos.x + 20.0 * PilotAssist.LEAD_MAX + 0.01, "упреждение не дальше %.0f с: %s" % [PilotAssist.LEAD_MAX, p])
	t.near(p.z, tg.pos.z, 0.01, "поперёк курса цель не смещается")
	# Своя скорость в зачёт: быстрее — упреждение короче.
	var fast := _drone(SimConst.Kind.COPTER, Vector3.ZERO, Vector3(0, 0, -60))
	var p2 := PilotAssist.lead_point(fast, tg)
	t.check(p2.x < p.x and p2.x > tg.pos.x, "быстрый перехватчик целится ближе: %.1f < %.1f" % [p2.x, p.x])
	# Встречная цель: точка встречи между нами.
	var head := _drone(SimConst.Kind.COPTER, Vector3(0, 0, -100), Vector3(0, 0, 20))
	var p3 := PilotAssist.lead_point(me, head)
	t.check(p3.z > -100.0 and p3.z < 0.0, "встречная цель — точка между нами: %s" % p3)


func test_lead_point_unreachable_target_is_pure_pursuit() -> void:
	var me := _drone(SimConst.Kind.COPTER, Vector3.ZERO, Vector3(0, 0, -20))
	var tg := _drone(SimConst.Kind.PLANE, Vector3(0, 0, -100), Vector3(0, 0, -50))
	var p := PilotAssist.lead_point(me, tg)
	t.check(p.is_equal_approx(tg.pos), "не догнать — летим на саму цель: %s" % p)


## Прогон в мире: перехватчик pid 1 на автозахвате, цель pid 2 летит своим вводом.
func _chase(kind_a: int, kind_b: int, a_pos: Vector3, a_vel: Vector3, b_pos: Vector3, b_vel: Vector3, b_inp: DroneInput, seconds: float, b_fn := Callable()) -> Dictionary:
	var w := WorldSim.new()
	w.setup(4242, [{"pid": 1, "name": "А", "color": 0, "kind": kind_a}, {"pid": 2, "name": "Б", "color": 1, "kind": kind_b}], 3)
	for i in 60:
		w.step({})
	var a := w.drone_of(1)
	var b := w.drone_of(2)
	for d in [a, b]:
		d.rot = Quaternion(Vector3.UP, FACE_X)
		d.age = 5.0
	a.pos = a_pos
	a.vel = a_vel
	b.pos = b_pos
	b.vel = b_vel
	if b.kind == SimConst.Kind.PLANE:
		b.throttle = 1.0
	w.take_events()
	var rammed := false
	var lost := false
	var closest := 1e9
	var ticks := 0
	var prev_d := a.pos.distance_to(b.pos)
	var grow := 0.0
	for k in int(seconds * SimConst.TICK_RATE):
		a = w.drone_of(1)
		b = w.drone_of(2)
		if a == null or b == null:
			break
		var dd := a.pos.distance_to(b.pos)
		closest = minf(closest, dd)
		# Как в клиенте (MatchView._update_lock): дальше 600 м или отрыв растёт 3 с — захват сорван.
		grow = grow + SimConst.DT if dd > prev_d else 0.0
		prev_d = dd
		if dd > 600.0 or grow >= 3.0:
			lost = true
			break
		w.step({1: PilotAssist.pursue(a, b, w.terrain), 2: b_inp if not b_fn.is_valid() else b_fn.call(k)})
		ticks += 1
		for e in w.take_events():
			if e.t == "ram":
				rammed = true
	return {"rammed": rammed, "lost": lost, "time": ticks * SimConst.DT, "closest": closest, "w": w}


func test_copter_pursuit_downs_straight_copter() -> void:
	var tr := Terrain.new()
	tr.generate(4242)
	var y := maxf(tr.height_at(0, 0), tr.height_at(0, -150)) + 70.0
	var inp := DroneInput.new()
	inp.pitch = 0.6   # летит прямо по +X, ~25 м/с
	var r := _chase(0, 0, Vector3(0, y, 0), Vector3.ZERO, Vector3(0, y + 10.0, -150), Vector3(22, 0, 0), inp, 25.0)
	t.check(r.rammed, "коптер на автозахвате сбил коптер со 150 м (ближе всего %.1f м)" % r.closest)
	t.check(r.time < 15.0, "за разумное время: %.1f с" % r.time)
	print("      коптер → коптер: перехват за %.1f с" % r.time)


func test_copter_cannot_catch_fleeing_plane() -> void:
	var tr := Terrain.new()
	tr.generate(4242)
	var y := 0.0
	for x in range(-220, 400, 20):
		y = maxf(y, tr.height_at(x, 0))
	y += 80.0
	var inp := DroneInput.new()
	inp.throttle = 1.0
	var r := _chase(0, 1, Vector3(-200, y, 0), Vector3(30, 0, 0), Vector3(-120, y, 0), Vector3(46, 0, 0), inp, 8.0)
	var w: WorldSim = r.w
	var a := w.drone_of(1)
	var b := w.drone_of(2)
	t.check(not r.rammed and a != null and b != null, "самолёт на полном газу ушёл от коптера")
	if a != null and b != null:
		t.check(a.pos.distance_to(b.pos) > 120.0, "отрыв растёт: %.0f м" % a.pos.distance_to(b.pos))


## Ищем склон: от старта по прямой рельеф поднимается на 20+ м за 200 м, но не круче,
## чем коптер успевает набирать на полном ходу.
func _find_slope(tr: Terrain) -> Array:
	for gx in range(-400, 401, 40):
		for gz in range(-400, 401, 40):
			for a in 8:
				var dir := Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0))
				var h0 := tr.height_at(gx, gz)
				var prev := h0
				var ok := true
				var top := h0
				for s in range(10, 201, 10):
					var h := tr.height_at(gx + dir.x * s, gz + dir.z * s)
					if (h - prev) / 10.0 > 0.3:
						ok = false
						break
					prev = h
					top = maxf(top, h)
				if ok and top - h0 > 20.0:
					return [Vector3(gx, h0, gz), dir]
	return []


func _fly_at_slope(tr: Terrain, start: Vector3, dir: Vector3, assist: bool) -> String:
	var d := _drone(SimConst.Kind.COPTER, start + Vector3(0, 6.0, 0), dir * 28.0)
	d.rot = Quaternion(Vector3.UP, atan2(-dir.x, -dir.z))
	var inp := DroneInput.new()
	inp.pitch = 1.0   # полный ход вперёд, газ не трогаем
	for k in 10 * SimConst.TICK_RATE:
		var i := inp.duplicate_input()
		if assist:
			i.throttle = PilotAssist.alt_hold_throttle(d, i.throttle, tr)
			i.pitch = PilotAssist.alt_hold_pitch(d, i.pitch, tr)
		var ground := tr.height_at(d.pos.x, d.pos.z)
		FlightCopter.step(d, i, SimConst.DT, Vector3.ZERO)
		var hit := tr.collide(d.pos, d.radius())
		if hit != "":
			return hit
		if assist and d.pos.y - ground > 40.0:
			return "high"
	return ""


func test_alt_assist_climbs_over_slope() -> void:
	var found := []
	var tr := Terrain.new()
	for sd in [MapPreset.seed_with_relief(500, 3), MapPreset.seed_with_relief(500, 2), MapPreset.seed_with_relief(500, 0)]:
		tr.generate(sd)
		found = _find_slope(tr)
		if not found.is_empty():
			break
	t.check(not found.is_empty(), "нашёлся склон для проверки")
	if found.is_empty():
		return
	t.check(_fly_at_slope(tr, found[0], found[1], false) != "", "без помощи коптер с нулевым газом врезается в склон")
	var hit := _fly_at_slope(tr, found[0], found[1], true)
	t.check(hit == "", "с помощью высоты коптер проходит склон: %s" % hit)


func test_alt_assist_only_lifts() -> void:
	var tr := Terrain.new()
	tr.generate(4242)
	var g := tr.height_at(0, 0)
	var high := _drone(SimConst.Kind.COPTER, Vector3(0, g + 80.0, 0), Vector3.ZERO)
	t.near(PilotAssist.alt_hold_throttle(high, 0.05, tr), 0.05, 0.0001, "высоко — газ не трогаем")
	t.near(PilotAssist.alt_hold_throttle(high, -0.08, tr), -0.08, 0.0001, "вниз не мешаем")
	var low := _drone(SimConst.Kind.COPTER, Vector3(0, g + 1.5, 0), Vector3.ZERO)
	t.check(PilotAssist.alt_hold_throttle(low, 0.0, tr) > 0.2, "у самой земли — подъём")
	t.near(PilotAssist.alt_hold_throttle(low, 0.9, tr), 0.9, 0.0001, "ручной газ сильнее — остаётся")


func test_copter_locks_easier_than_plane() -> void:
	var tr := Terrain.new()
	tr.generate(4242)
	var y := tr.height_at(0, 0) + 90.0
	var hits := [0, 0]
	for pk in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		for i in 12:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(120, 250)
			var ph := rng.randf() * TAU
			var fn := func(k: int) -> DroneInput:
				var q := DroneInput.new()
				q.pitch = 0.6
				q.roll = sin(k / 30.0 * 1.6 + ph) * 0.8   # цель петляет
				return q
			var bpos := Vector3(cos(ang) * dist, y + rng.randf_range(-15, 15), sin(ang) * dist)
			var r := _chase(pk, 0, Vector3(0, y, 0), Vector3(38, 0, 0) if pk == 1 else Vector3.ZERO, bpos, Vector3(22, 0, 0), DroneInput.new(), 20.0, fn)
			if r.rammed:
				hits[pk] += 1
	t.check(hits[0] >= 9, "коптер на автозахвате сбивает петляющий коптер чаще всего: %d/12" % hits[0])
	t.check(hits[1] < hits[0] and hits[1] >= 2, "самолёт промахивается чаще коптера, но не безнадёжен: %d/12 против %d/12" % [hits[1], hits[0]])
	print("      автозахват петляющего коптера: коптер %d/12, самолёт %d/12" % [hits[0], hits[1]])
