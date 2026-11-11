class_name PilotAssist
## Помощь пилоту: удержание высоты над рельефом, упреждение и рулёжка к точке, автозахват.
## Общая для клиента (помощь игроку) и сервера (боты). Только статические функции:
## на вход — состояние дрона и рельеф, на выход — обычный DroneInput или газ.

## Крейсерская скорость по типу: ниже неё своя скорость для упреждения не считается.
const CRUISE_SPEED := [30.0, 42.0]
const LEAD_MAX := 3.0             # упреждение не дальше, с
const PURSUE_SPEED := 45.0        # желаемая скорость коптера в погоне (больше предела — полный ход)
const PURSUE_FLOOR := [3.0, 10.0] # погоня не ниже, м над рельефом (самолёт быстро не остановит снижение)
## Самолёт в погоне тянет и кренится не в полную силу: автозахват ему даётся тяжелее, чем коптеру.
const PLANE_PULL := 0.7
const PLANE_ROLL_GAIN := 1.2
const ALT_MIN_AGL := 5.0          # помощь высоты держит не ниже, м над рельефом впереди
const OBSTACLE_MARGIN := 3.0      # с каким запасом вбок дерево или постройка считаются на пути, м
const OBSTACLE_CLEAR := 2.5       # на сколько выше верхушки проходить, м
const PROBE_STEP := 6.0           # шаг просмотра вперёд, м


## Газ аркады коптера с помощью высоты: не ниже min_agl над рельефом на 1–3 с впереди
## (по скорости) и подскок над деревьями и постройками. Только поднимает: если запас есть,
## газ возвращается как был.
static func alt_hold_throttle(d: DroneState, throttle: float, terrain: Terrain, min_agl := ALT_MIN_AGL) -> float:
	var need := climb_need(d, terrain, min_agl)
	if need <= 0.3:
		return throttle
	return maxf(throttle, FlightCopter.throttle_for_vspeed(minf(need, FlightCopter.CLIMB_SPEED)))


## Пара к alt_hold_throttle: склон впереди круче, чем коптер успевает набрать, —
## придерживаем ручку «от себя», чтобы скорость упала и подъём успел. Назад не тянет сильнее игрока.
static func alt_hold_pitch(d: DroneState, pitch: float, terrain: Terrain, min_agl := ALT_MIN_AGL) -> float:
	var ratio := climb_need(d, terrain, min_agl) / FlightCopter.CLIMB_SPEED
	if ratio <= 1.0:
		return pitch
	return minf(pitch, clampf(1.0 - (ratio - 1.0) * 3.0, -1.0, 1.0))


## Какая вертикальная скорость нужна (м/с), чтобы на 1–3 с впереди (по скорости) остаться
## не ниже min_agl над рельефом и пройти над деревьями и постройками.
static func climb_need(d: DroneState, terrain: Terrain, min_agl := ALT_MIN_AGL) -> float:
	var hv := Vector3(d.vel.x, 0.0, d.vel.z)
	var spd := hv.length()
	var horizon := clampf(spd / 10.0, 1.0, 3.0)
	var need := (terrain.height_at(d.pos.x, d.pos.z) + min_agl - d.pos.y) * 1.5
	var here := terrain.obstacle_top(d.pos.x, d.pos.z, OBSTACLE_MARGIN)
	if here > -INF:
		need = maxf(need, (here + OBSTACLE_CLEAR - d.pos.y) * 1.5)
	if spd < 0.5:
		return need
	var dir := hv / spd
	var s := PROBE_STEP
	while s <= spd * horizon:
		var k := s / spd
		var x := d.pos.x + dir.x * s
		var z := d.pos.z + dir.z * s
		need = maxf(need, (terrain.height_at(x, z) + min_agl - d.pos.y) / maxf(k, 0.5))
		var top := terrain.obstacle_top(x, z, OBSTACLE_MARGIN)
		if top > -INF:
			need = maxf(need, (top + OBSTACLE_CLEAR - d.pos.y) / maxf(k, 0.4))
		s += PROBE_STEP
	return need


## Точка встречи с целью: где окажется цель через t, если лететь к ней по прямой со своей
## скоростью (не ниже крейсерской). Упреждение не дальше LEAD_MAX; не догнать — чистая погоня.
static func lead_point(me: DroneState, target: DroneState) -> Vector3:
	var r := target.pos - me.pos
	var v := target.vel
	var s := maxf(me.vel.length(), CRUISE_SPEED[me.kind])
	# |r + v·t| = s·t  →  (v·v − s²)·t² + 2·(r·v)·t + r·r = 0
	var a := v.dot(v) - s * s
	var b := 2.0 * r.dot(v)
	var c := r.dot(r)
	var t := -1.0
	if absf(a) < 0.0001:
		if b < 0.0:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			elif t1 > 0.0 or t2 > 0.0:
				t = maxf(t1, t2)
	if t <= 0.0:
		return target.pos
	return target.pos + v * minf(t, LEAD_MAX)


## Рулёжка к точке: flat — куда лететь по горизонтали (длина — дистанция), alt — нужная высота,
## aim_y — высота самой цели (самолёт у цели ныряет к ней). speed — желаемая скорость коптера,
## weave — петляние вбок (−1..1), wobble — небрежность крена. Форсаж выбирает вызывающий.
static func steer_to(d: DroneState, flat: Vector3, alt: float, aim_y: float, speed: float, weave := 0.0, wobble := 0.0) -> DroneInput:
	var inp := DroneInput.new()
	var dist := flat.length()
	if d.kind == SimConst.Kind.COPTER:
		var fwd := d.forward()
		fwd.y = 0
		fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0, fwd.x)
		var want_dir := flat.normalized() if dist > 0.5 else fwd
		var heading_err := atan2(fwd.cross(want_dir).y, fwd.dot(want_dir))
		inp.yaw = clampf(-heading_err * 2.0, -1, 1)
		var v_des := want_dir * speed + right * weave * 10.0
		var v_fwd := d.vel.dot(fwd)
		var v_right := d.vel.dot(right)
		inp.pitch = clampf((v_des.dot(fwd) - v_fwd) * 0.12, -1, 1)
		inp.roll = clampf((v_des.dot(right) - v_right) * 0.12 + wobble, -1, 1)
		inp.throttle = vthrottle((alt - d.pos.y) * 0.3 - d.vel.y * 0.05)
		if absf(heading_err) > 1.2:
			inp.pitch *= 0.3
	else:
		var fwd := d.forward()
		var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
		var want_dir := flat.normalized() if dist > 0.5 else flat_fwd
		var heading_err := atan2(flat_fwd.cross(want_dir).y, flat_fwd.dot(want_dir))
		var right := d.rot * Vector3.RIGHT
		var bank := asin(clampf(-right.y, -1, 1))   # >0 — крен вправо
		var bank_des := clampf(-heading_err * 1.4 + weave * 0.4, -0.85, 0.85)
		inp.roll = clampf((bank_des - bank) * 2.2, -1, 1)
		var vdir := d.vel.normalized() if d.vel.length() > 1.0 else fwd
		var fpa := asin(clampf(vdir.y, -1, 1))
		var climb_des := clampf((alt - d.pos.y) * 0.03, -0.35, 0.4)
		if dist < 90.0:
			climb_des = clampf(atan2(aim_y - d.pos.y, dist), -1.0, 0.3)
		var p_cmd := (fpa - climb_des) * 1.8
		if absf(bank) > 0.35:
			p_cmd = minf(p_cmd, 0.0) - absf(bank) * 0.5  # в крене только тянем на себя
		inp.pitch = clampf(p_cmd, -0.8, 0.7)
		inp.throttle = 1.0
	return inp


## Автозахват: курс на точку встречи с чужим дроном на форсаже, не ниже PURSUE_FLOOR над
## рельефом. Не подрывает: сбивает неконтактный взрыватель или сам игрок.
static func pursue(d: DroneState, target: DroneState, terrain: Terrain) -> DroneInput:
	var aim := lead_point(d, target)
	var hv := Vector3(d.vel.x, 0.0, d.vel.z)
	var g := terrain.height_at(d.pos.x, d.pos.z)
	for k in [1.0, 2.0]:
		g = maxf(g, terrain.height_at(d.pos.x + hv.x * k, d.pos.z + hv.z * k))
	g = maxf(g, terrain.height_at(aim.x, aim.z))
	var alt := maxf(aim.y, g + PURSUE_FLOOR[d.kind])
	var inp: DroneInput
	if d.kind == SimConst.Kind.COPTER:
		var to := aim - d.pos
		inp = steer_to(d, Vector3(to.x, 0.0, to.z), alt, alt, PURSUE_SPEED)
		inp.throttle = alt_hold_throttle(d, inp.throttle, terrain, PURSUE_FLOOR[d.kind])
	else:
		inp = _plane_lift_on(d, Vector3(aim.x, alt, aim.z))
	inp.boost = true
	return inp


## Самолёт в погоне: креном кладём подъёмную силу на цель и тянем по углу от носа.
## Цель ниже и почти по курсу — не переворачиваемся, а отдаём ручку.
static func _plane_lift_on(d: DroneState, aim: Vector3) -> DroneInput:
	var inp := DroneInput.new()
	inp.throttle = 1.0
	var to := aim - d.pos
	if to.length() < 0.5:
		return inp
	var local := d.rot.inverse() * to.normalized()   # x — вправо, y — вверх, −z — нос
	var off := acos(clampf(-local.z, -1.0, 1.0))      # угол цели от носа
	var roll_err := atan2(local.x, local.y)           # 0 — цель над головой в плоскости тангажа
	if local.y < 0.0 and absf(local.x) < -local.y and off < 0.6:
		roll_err = atan2(local.x, -local.y)
		inp.pitch = clampf(off * 3.0, 0.0, 0.6)
	else:
		inp.pitch = -clampf(off * 3.0, 0.0, PLANE_PULL) * maxf(0.25, cos(clampf(roll_err, -PI / 2.0, PI / 2.0)))
	if off < 0.05:
		roll_err *= off / 0.05   # цель по носу — крен не дёргаем
	inp.roll = clampf(roll_err * PLANE_ROLL_GAIN, -1.0, 1.0)
	return inp


## Боты и рулёжка настроены на линейный газ (±1 → ±10 м/с); аркада снижается нелинейно —
## переводим команду в ту же вертикальную скорость.
static func vthrottle(cmd: float) -> float:
	return FlightCopter.throttle_for_vspeed(clampf(cmd, -1.0, 1.0) * 10.0)
