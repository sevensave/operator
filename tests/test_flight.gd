extends RefCounted
## Физика полёта обоих типов дронов.

var t


func _copter(alt := 50.0) -> DroneState:
	var d := DroneState.new()
	d.kind = SimConst.Kind.COPTER
	d.pos = Vector3(0, alt, 0)
	return d


func _plane(speed := 30.0) -> DroneState:
	var d := DroneState.new()
	d.kind = SimConst.Kind.PLANE
	d.pos = Vector3(0, 200, 0)
	d.vel = Vector3(0, 0, -speed)
	d.throttle = 0.6
	return d


func _run(d: DroneState, inp: DroneInput, seconds: float, air := Vector3.ZERO) -> void:
	var n := int(seconds * SimConst.TICK_RATE)
	for i in n:
		if d.kind == SimConst.Kind.PLANE:
			FlightPlane.step(d, inp, SimConst.DT, air)
		else:
			FlightCopter.step(d, inp, SimConst.DT, air)


func test_copter_hovers_with_neutral_sticks() -> void:
	var d := _copter()
	_run(d, DroneInput.new(), 10.0)
	t.near(d.pos.y, 50.0, 1.5, "коптер держит высоту без ввода")
	t.check(d.vel.length() < 0.5, "коптер почти неподвижен: %s" % d.vel)


func test_copter_top_speed() -> void:
	var d := _copter(100.0)
	var inp := DroneInput.new()
	inp.pitch = 1.0
	_run(d, inp, 15.0)
	var hs := Vector2(d.vel.x, d.vel.z).length()
	t.check(hs > 22.0 and hs < 32.0, "скорость коптера ~28 м/с, получили %.1f" % hs)
	t.check(d.vel.z < 0.0, "летит вперёд (−Z)")
	inp.boost = true
	_run(d, inp, 10.0)
	var hs2 := Vector2(d.vel.x, d.vel.z).length()
	t.check(hs2 > hs + 3.0, "форсаж быстрее: %.1f > %.1f" % [hs2, hs])


func test_copter_climb_and_turn() -> void:
	var d := _copter()
	var inp := DroneInput.new()
	inp.throttle = 1.0
	_run(d, inp, 3.0)
	t.check(d.pos.y > 70.0, "набор высоты: %.1f" % d.pos.y)
	inp = DroneInput.new()
	inp.yaw = 1.0
	_run(d, inp, 0.5)
	var f := d.forward()
	t.check(f.x > 0.3, "рыск вправо поворачивает нос на +X: %s" % f)


func test_copter_falls_without_control() -> void:
	var d := _copter()
	d.control = false
	_run(d, DroneInput.new(), 2.0)
	t.check(d.pos.y < 40.0, "без управления падает: %.1f" % d.pos.y)


func test_copter_battery_drains_faster_with_boost() -> void:
	var a := _copter()
	var b := _copter()
	var inp := DroneInput.new()
	inp.pitch = 0.5
	_run(a, inp, 20.0)
	inp.boost = true
	_run(b, inp, 20.0)
	t.check(a.battery < 1.0 and b.battery < a.battery, "форсаж ест заряд: %.3f < %.3f" % [b.battery, a.battery])
	t.check(a.battery > 0.8, "20 с полёта не съедают батарею: %.3f" % a.battery)


func test_copter_acro_rates() -> void:
	var d := _copter()
	var inp := DroneInput.new()
	inp.acro = true
	inp.roll = 1.0
	inp.throttle = 0.0
	_run(d, inp, 0.25)
	var right := d.rot * Vector3.RIGHT
	t.check(right.y < -0.3, "акро: крен вправо опускает правый борт: %s" % right)


func test_plane_holds_flight() -> void:
	var d := _plane()
	_run(d, DroneInput.new(), 20.0)
	var v := d.vel.length()
	t.check(v > 22.0 and v < 55.0, "самолёт летит сам: %.1f м/с" % v)
	t.check(absf(d.pos.y - 200.0) < 40.0, "держит высоту в аркаде: %.1f" % d.pos.y)


func test_plane_top_speed() -> void:
	var d := _plane(40.0)
	var inp := DroneInput.new()
	inp.throttle = 1.0
	_run(d, inp, 25.0)
	var v := d.vel.length()
	t.check(v > 42.0 and v < 58.0, "максимальная скорость ~50: %.1f" % v)


func test_plane_cannot_hover_and_stalls() -> void:
	var d := _plane(20.0)
	var inp := DroneInput.new()
	inp.throttle = -1.0
	inp.pitch = -1.0   # тянем на себя на малом газу
	var min_y := d.pos.y
	_run(d, inp, 8.0)
	t.check(d.pos.y < 200.0, "на малом газу и задранном носе самолёт теряет высоту: %.1f" % d.pos.y)
	t.check(d.vel.length() > 8.0, "самолёт не зависает: %.1f" % d.vel.length())


func test_plane_turns_wider_than_copter() -> void:
	var p := _plane(45.0)
	var inp := DroneInput.new()
	inp.roll = 1.0
	_run(p, inp, 0.5)
	inp.roll = 0.0
	inp.pitch = -1.0
	_run(p, inp, 4.0)
	t.check(p.vel.length() > 15.0, "в вираже самолёт держит скорость")
	t.check(absf(p.pos.x) > 20.0, "вираж уводит в сторону: %.1f" % p.pos.x)


func test_wind_pushes_hovering_copter() -> void:
	var d := _copter()
	_run(d, DroneInput.new(), 5.0, Vector3(6, 0, 0))
	t.check(d.pos.x > 5.0, "ветер сносит висящий коптер: %.1f" % d.pos.x)


func test_input_pack_roundtrip() -> void:
	var i := DroneInput.new()
	i.seq = 1234
	i.throttle = 0.5
	i.pitch = -1.0
	i.roll = 0.25
	i.yaw = 1.0
	i.boost = true
	var j := DroneInput.from_array(i.to_array())
	t.check(j.seq == 1234 and j.boost and not j.acro, "seq и флаги")
	t.near(j.throttle, 0.5, 0.01, "газ")
	t.near(j.pitch, -1.0, 0.01, "тангаж")
	t.near(j.roll, 0.25, 0.01, "крен")
