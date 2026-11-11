class_name BotAI
extends RefCounted
## Бот-оператор: выбирает цель, летит низко над рельефом, петляет у чужих укрытий,
## перехватывает дроны у своего укрытия и ставит сеть. Даёт тот же DroneInput, что и человек.

var pid := 0
var skill := 0.7
var plane_share := 0.35
var rng := RandomNumberGenerator.new()
var target_pid := 0
var _retarget := 0.0
var _weave_phase := 0.0
var _last_drone := 0
var _intercept_id := 0
var keep_kind := false   # не менять тип дрона между вылетами (съёмка с --kind)


func _init(p_pid: int, p_skill: float, p_seed: int) -> void:
	pid = p_pid
	skill = p_skill
	rng.seed = p_seed
	_weave_phase = rng.randf() * TAU


func think(w: WorldSim) -> DroneInput:
	var inp := DroneInput.new()
	var me: PlayerSim = w.players.get(pid)
	if me == null or me.eliminated:
		return inp
	var home := w.shelter_center(me)

	# Сеть: чужой дрон близко к укрытию.
	if me.trap_cd <= 0.0 and not w.sudden_death:
		for d in w.drones.values():
			if d.owner != pid and d.pos.distance_to(home) < SimConst.TRAP_RADIUS * 0.85 and rng.randf() < 0.05 * skill:
				w.trigger_trap(pid)
				break

	var d: DroneState = w.drone_of(pid)
	if d == null:
		# Решаем, что запустить следующим.
		if me.respawn_t > 0.0 and me.respawn_t < 0.2 and not keep_kind:
			w.set_kind(pid, SimConst.Kind.PLANE if rng.randf() < plane_share else SimConst.Kind.COPTER)
		return inp
	if d.id != _last_drone:
		_last_drone = d.id
		_retarget = 0.0
		_intercept_id = 0

	# Цель меняем только между вылетами или если она выбыла.
	if _retarget <= 0.0 or not w.players.has(target_pid) or w.players[target_pid].eliminated:
		_pick_target(w, me)
		_retarget = 1.0

	# Перехват: если коптер и чужой дрон летит к нам — таран.
	var aim := Vector3.ZERO
	var intercept := false
	if d.kind == SimConst.Kind.COPTER:
		for o in w.drones.values():
			if o.owner == pid:
				continue
			if o.pos.distance_to(home) < 160.0 and o.pos.distance_to(d.pos) < 220.0:
				aim = PilotAssist.lead_point(d, o)
				intercept = true
				break
	if not intercept:
		if target_pid == 0:
			return _hover(d, w)
		aim = w.shelter_center(w.players[target_pid])

	var to := aim - d.pos
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var ground := w.terrain.height_at(d.pos.x, d.pos.z)
	var hv := Vector3(d.vel.x, 0, d.vel.z)
	var ahead := d.pos + hv * 1.6
	var ground_ahead := w.terrain.height_at(ahead.x, ahead.z)
	# Самолёт не зависает и набирает медленнее — смотрит дальше (до 5 с), коптер — на 3 с.
	var horizon := 5.0 if d.kind == SimConst.Kind.PLANE else 3.0
	var ground_far := ground_ahead
	var steep := 0.0   # самый крутой требуемый набор впереди (м подъёма на м пути)
	for k in [2.4, 3.2, 4.0, 5.0]:
		if k > horizon:
			break
		var gk := w.terrain.height_at(d.pos.x + hv.x * k, d.pos.z + hv.z * k)
		ground_far = maxf(ground_far, gk)
		var run := maxf(hv.length() * k, 1.0)
		steep = maxf(steep, (gk + 12.0 - d.pos.y) / run)
	var g := maxf(ground, maxf(ground_ahead, ground_far - 4.0))
	var cruise := 24.0 if dist > 260.0 else 11.0
	if d.signal_q < 0.35 and dist > 200.0:
		cruise = 40.0   # слабая связь — поднимаемся за прямой видимостью
	var alt := g + cruise
	# Деревья и постройки впереди — подскок.
	for k in [0.5, 1.0, 1.6]:
		var probe: Vector3 = d.pos + d.vel * k
		if w.terrain.collide(probe, 3.0) != "":
			alt = maxf(alt, d.pos.y + 14.0)
			break
	# Край карты — разворот к центру.
	if Vector2(d.pos.x, d.pos.z).length() > SimConst.MAP_HALF - 80.0 and not intercept:
		aim = Vector3(0, aim.y, 0)
		to = aim - d.pos
		flat = Vector3(to.x, 0, to.z)
		dist = flat.length()
	# Стена впереди круче, чем успеем набрать, — уходим вбок, туда, где ниже.
	var climb_ok := 0.3 if d.kind == SimConst.Kind.PLANE else 0.8
	if steep > climb_ok and not intercept and dist > 90.0 and hv.length() > 5.0:
		var dir := hv.normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var look := hv.length() * 2.5
		var gl := w.terrain.height_at(d.pos.x + (dir.x - side.x) * look, d.pos.z + (dir.z - side.z) * look)
		var gr := w.terrain.height_at(d.pos.x + (dir.x + side.x) * look, d.pos.z + (dir.z + side.z) * look)
		var turn := side if gr < gl else -side
		flat = (dir + turn * clampf(steep / climb_ok - 0.6, 0.4, 1.5)).normalized() * dist
	if dist < 70.0 or intercept:
		alt = lerpf(aim.y, alt, clampf((dist - 15.0) / 60.0, 0.0, 1.0))
	if intercept:
		alt = maxf(aim.y, g + 3.0)

	if not intercept and target_pid != 0:
		var blast: float = SimConst.BLAST_RADIUS[d.kind]
		if d.pos.distance_to(aim) < SimConst.SHELTER_HIT_RADIUS + blast * 0.6 and w.players[target_pid].grace <= 0.0:
			w.detonate(pid)
			return inp
	var t := w.time
	var weave := 0.0
	if dist < SimConst.TURRET_RANGE + 40.0 and not intercept and not w.sudden_death:
		weave = sin(t * 2.4 + _weave_phase) * (0.5 + 0.4 * skill)
	var sloppy := (1.0 - skill) * 0.25

	var speed := 30.0
	if intercept:
		speed = 34.0
	elif steep > 0.3:
		speed *= clampf(0.3 / steep, 0.3, 1.0)   # крутой склон впереди — притормаживаем и набираем
	inp = PilotAssist.steer_to(d, flat, alt, aim.y, speed, weave, sin(t * 3.0 + pid) * sloppy)
	if d.kind == SimConst.Kind.COPTER:
		inp.boost = (dist < 160.0 and dist > 25.0) or intercept
	else:
		inp.boost = dist < 220.0
	return inp


func _hover(d: DroneState, w: WorldSim) -> DroneInput:
	var inp := DroneInput.new()
	var g := w.terrain.height_at(d.pos.x, d.pos.z)
	inp.throttle = _vthrottle((g + 20.0 - d.pos.y) * 0.3)
	return inp


static func _vthrottle(cmd: float) -> float:
	return PilotAssist.vthrottle(cmd)


func _pick_target(w: WorldSim, me: PlayerSim) -> void:
	var best := 0
	var best_score := -INF
	var home := w.shelter_pos(me)
	for p in w.players.values():
		if p.pid == pid or p.eliminated:
			continue
		var dist := home.distance_to(w.shelter_pos(p))
		# Ближе и слабее — интереснее, плюс случайность, чтобы боты не толпились.
		var score: float = -dist * 0.004 - p.lives * 0.6 + rng.randf() * 1.6
		if score > best_score:
			best_score = score
			best = p.pid
	target_pid = best
