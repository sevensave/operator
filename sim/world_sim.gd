class_name WorldSim
extends RefCounted
## Авторитетная симуляция матча: дроны, связь, ветер, защита укрытий, жизни и победа.
## На сервере крутится в комнате, в тренировке — локально в той же «комнате».

var terrain := Terrain.new()
var seed := 0
var tick := 0
var time := 0.0
var lives_start := 3
var players := {}          # pid -> PlayerSim
var drones := {}           # id -> DroneState
var sudden_death := false
var finished := false
var winner := 0            # pid победителя, 0 — ничья/нет (у ботов pid < 0)
var events: Array = []     # события последнего шага

var _next_drone := 1
var _history := {}         # pid -> Array[DroneInput] (для задержки управления)
var _los := {}             # drone id -> bool (кэш прямой видимости до своей антенны)
var _neutral := {}         # drone id -> true: запутался в сети, взрыв не считается


func setup(p_seed: int, roster: Array, lives: int) -> void:
	seed = p_seed
	terrain.generate(p_seed)
	lives_start = lives
	players.clear()
	drones.clear()
	var order := _spread_slots(roster.size())
	for i in roster.size():
		var r: Dictionary = roster[i]
		var p := PlayerSim.new()
		p.pid = int(r.get("pid", i + 1))
		p.name = str(r.get("name", "Оператор"))
		p.color = int(r.get("color", i))
		p.style = int(r.get("style", 0))
		p.kind = int(r.get("kind", 0))
		p.bot = bool(r.get("bot", false))
		p.shelter = order[i]
		p.lives = lives
		p.respawn_t = 1.0 + 0.1 * i
		players[p.pid] = p


## Разносим игроков по кольцу равномерно.
static func _spread_slots(n: int) -> Array:
	var out := []
	var total := SimConst.MAX_PLAYERS
	for i in n:
		out.append(int(floor(float(i) * total / maxi(n, 1))) % total)
	return out


func shelter_pos(p: PlayerSim) -> Vector3:
	return terrain.shelters[p.shelter]


func shelter_center(p: PlayerSim) -> Vector3:
	return terrain.shelters[p.shelter] + Vector3(0, 2.5, 0)


func mast_pos(p: PlayerSim) -> Vector3:
	return terrain.shelters[p.shelter] + Vector3(0, SimConst.MAST_HEIGHT, 0)


func alive_players() -> Array:
	var out := []
	for p in players.values():
		if not p.eliminated:
			out.append(p)
	return out


func drone_of(pid: int) -> DroneState:
	var p: PlayerSim = players.get(pid)
	if p == null or p.drone_id == 0:
		return null
	return drones.get(p.drone_id)


func set_kind(pid: int, kind: int) -> void:
	if players.has(pid):
		players[pid].kind = clampi(kind, 0, 1)


func trigger_trap(pid: int) -> bool:
	var p: PlayerSim = players.get(pid)
	if p == null or p.eliminated or p.trap_cd > 0.0 or sudden_death:
		return false
	p.trap_t = SimConst.TRAP_TIME
	p.trap_cd = SimConst.TRAP_COOLDOWN
	events.append({"t": "trap", "pid": pid, "pos": shelter_center(p)})
	return true


## Подрыв своего дрона по команде оператора.
func detonate(pid: int) -> void:
	var d := drone_of(pid)
	if d != null and d.age > 0.6 and d.trapped <= 0.0:
		_explode(d, "detonate", 0)
		_check_victory()


## Один тик симуляции. inputs: pid -> DroneInput.
func step(inputs: Dictionary) -> void:
	if finished:
		return
	var dt := SimConst.DT
	tick += 1
	time += dt
	if not sudden_death and time >= SimConst.SUDDEN_DEATH_AT:
		sudden_death = true
		events.append({"t": "sudden"})
		for p in players.values():
			p.trap_t = 0.0

	_update_players(dt)

	var prev := {}
	for d in drones.values():
		prev[d.id] = d.pos
		var p: PlayerSim = players[d.owner]
		var inp: DroneInput = inputs.get(d.owner)
		if inp == null:
			inp = DroneInput.new()
		_push_history(d.owner, inp)
		_update_signal(d, p)
		d.age += dt
		if d.trapped > 0.0:
			d.trapped -= dt
			d.vel *= exp(-7.0 * dt)
			d.pos += d.vel * dt
			d.angvel = d.angvel.lerp(Vector3(0.0, 2.0, 0.0), dt)
			if d.trapped <= 0.0:
				d.trapped = 0.0
				d.battery = 0.0
				_neutral[d.id] = true
			continue
		var eff := _effective_input(d, inp)
		var ground := terrain.height_at(d.pos.x, d.pos.z)
		var air := Wind.at(d.pos, time, seed, ground)
		if d.kind == SimConst.Kind.PLANE:
			FlightPlane.step(d, eff, dt, air)
		else:
			FlightCopter.step(d, eff, dt, air)
		_update_defenses(d, p, dt)

	_check_collisions(prev)
	_check_victory()


func _update_players(dt: float) -> void:
	for p in players.values():
		if p.eliminated:
			continue
		p.grace = maxf(0.0, p.grace - dt)
		p.trap_cd = maxf(0.0, p.trap_cd - dt)
		if p.trap_t > 0.0:
			p.trap_t = maxf(0.0, p.trap_t - dt)
			_apply_trap(p)
		if p.stock < SimConst.STOCK_MAX:
			p.regen_t += dt
			if p.regen_t >= SimConst.STOCK_REGEN:
				p.regen_t = 0.0
				p.stock += 1
		else:
			p.regen_t = 0.0
		if p.drone_id == 0:
			p.respawn_t = maxf(0.0, p.respawn_t - dt)
			if p.respawn_t <= 0.0 and p.stock > 0:
				_spawn(p)


func _spawn(p: PlayerSim) -> void:
	var d := DroneState.new()
	d.id = _next_drone
	_next_drone += 1
	d.owner = p.pid
	d.kind = p.kind
	var base := shelter_pos(p)
	var to_center := Vector3(-base.x, 0.0, -base.z).normalized()
	var yaw := atan2(-to_center.x, -to_center.z)
	d.rot = Quaternion(Vector3.UP, yaw)
	if d.kind == SimConst.Kind.PLANE:
		d.pos = base + Vector3(0, 16, 0) + to_center * 6.0
		d.vel = to_center * 27.0
		d.throttle = 0.75
	else:
		d.pos = base + Vector3(0, 5.0, 0) + to_center * 3.0
	drones[d.id] = d
	p.drone_id = d.id
	p.stock -= 1
	p.launched += 1
	_history[p.pid] = []
	events.append({"t": "spawn", "pid": p.pid, "id": d.id, "kind": d.kind})


func _push_history(pid: int, inp: DroneInput) -> void:
	if not _history.has(pid):
		_history[pid] = []
	var h: Array = _history[pid]
	h.append(inp)
	if h.size() > 16:
		h.pop_front()


func _effective_input(d: DroneState, inp: DroneInput) -> DroneInput:
	var delay := SignalModel.input_delay_ticks(d.signal_q)
	var h: Array = _history.get(d.owner, [])
	var src: DroneInput = inp
	if delay > 0 and h.size() > 0:
		src = h[maxi(0, h.size() - 1 - delay)]
	var noise := SignalModel.control_noise(d.signal_q)
	if noise <= 0.0:
		return src
	var e := src.duplicate_input()
	var ph := time * 9.0 + d.id * 1.7
	e.pitch = clampf(e.pitch + sin(ph) * noise, -1, 1)
	e.roll = clampf(e.roll + sin(ph * 1.3 + 2.0) * noise, -1, 1)
	e.yaw = clampf(e.yaw + sin(ph * 0.7 + 4.0) * noise * 0.5, -1, 1)
	return e


func enemy_shelters(owner: int) -> Array:
	var out := []
	for p in players.values():
		if p.pid != owner and not p.eliminated:
			out.append(shelter_center(p))
	return out


func _update_signal(d: DroneState, p: PlayerSim) -> void:
	var mast := mast_pos(p)
	if tick % 3 == d.id % 3 or not _los.has(d.id):
		_los[d.id] = terrain.line_of_sight(mast, d.pos)
	var q := SignalModel.distance_quality(mast.distance_to(d.pos), d.kind)
	if not _los[d.id]:
		q *= SignalModel.LOS_PENALTY
	d.jammed = false
	if not sudden_death:
		var jf := SignalModel.jam_factor(d.pos, enemy_shelters(d.owner))
		d.jammed = jf < 0.98
		q *= jf
	d.signal_q = lerpf(d.signal_q, q, 0.35)
	if d.signal_q < SignalModel.NOLINK:
		d.nolink += SimConst.DT
	else:
		d.nolink = maxf(0.0, d.nolink - SimConst.DT * 2.0)
	var had := d.control
	d.control = d.battery > 0.0 and d.nolink < SimConst.NOLINK_FALL and d.trapped <= 0.0
	if had and not d.control and d.battery > 0.0:
		events.append({"t": "nolink", "pid": d.owner, "id": d.id})


func _update_defenses(d: DroneState, owner: PlayerSim, dt: float) -> void:
	if sudden_death:
		d.lock = maxf(0.0, d.lock - Defenses.LOCK_DECAY * dt)
		return
	var agl := terrain.agl(d.pos)
	var best := 0.0
	for p in players.values():
		if p.pid == owner.pid or p.eliminated:
			continue
		var e := Defenses.exposure(d, agl, shelter_center(p), terrain)
		best = maxf(best, e)
	if best > 0.0:
		d.lock = minf(1.0, d.lock + best * Defenses.LOCK_GAIN * dt)
	else:
		d.lock = maxf(0.0, d.lock - Defenses.LOCK_DECAY * dt)


func _apply_trap(p: PlayerSim) -> void:
	var c := shelter_center(p)
	for d in drones.values():
		if d.owner == p.pid or d.trapped > 0.0:
			continue
		if d.pos.distance_to(c) < SimConst.TRAP_RADIUS:
			d.trapped = p.trap_t
			events.append({"t": "caught", "pid": p.pid, "victim": d.owner, "id": d.id})


func _check_collisions(prev: Dictionary) -> void:
	var dead := {}  # id -> [cause, other_owner]
	var list: Array = drones.values()
	# Дрон + дрон: проверка по отрезкам за тик, чтобы не проскочить на скорости.
	for i in list.size():
		var a: DroneState = list[i]
		for j in range(i + 1, list.size()):
			var b: DroneState = list[j]
			var rr := a.radius() + b.radius()
			if _swept_hit(prev[a.id], a.pos, prev[b.id], b.pos, rr):
				dead[a.id] = ["ram", b.owner]
				dead[b.id] = ["ram", a.owner]
	for d in list:
		if dead.has(d.id):
			continue
		if d.lock >= 1.0:
			dead[d.id] = ["turret", 0]
			continue
		var hit := terrain.collide(d.pos, d.radius())
		if hit != "":
			dead[d.id] = [hit, 0]
			continue
		for p in players.values():
			if p.pid != d.owner and not p.eliminated and d.pos.distance_to(shelter_center(p)) < SimConst.SHELTER_HIT_RADIUS * 0.6:
				dead[d.id] = ["shelter", 0]
				break
	for id in dead.keys():
		_explode(drones[id], dead[id][0], dead[id][1])


static func _swept_hit(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, r: float) -> bool:
	var d0 := a0 - b0
	var dv := (a1 - b1) - d0
	var t := 0.0
	var vv := dv.length_squared()
	if vv > 0.000001:
		t = clampf(-d0.dot(dv) / vv, 0.0, 1.0)
	return (d0 + dv * t).length() < r


func _explode(d: DroneState, cause: String, other: int) -> void:
	drones.erase(d.id)
	_los.erase(d.id)
	var neutral: bool = _neutral.has(d.id) or cause == "turret"
	_neutral.erase(d.id)
	var owner: PlayerSim = players[d.owner]
	owner.drone_id = 0
	owner.respawn_t = SimConst.RESPAWN_DELAY
	events.append({"t": "boom", "pid": d.owner, "id": d.id, "pos": d.pos, "kind": d.kind, "cause": cause, "by": other})
	if cause == "ram" and players.has(other):
		owner.rams += 1
		if d.owner < other:
			events.append({"t": "ram", "a": d.owner, "b": other})
	if neutral:
		return
	var blast: float = SimConst.BLAST_RADIUS[d.kind]
	for p in players.values():
		if p.pid == d.owner or p.eliminated or p.grace > 0.0:
			continue
		if d.pos.distance_to(shelter_center(p)) < SimConst.SHELTER_HIT_RADIUS + blast:
			p.lives -= 1
			p.grace = SimConst.LIFE_GRACE
			owner.hits += 1
			events.append({"t": "hit", "victim": p.pid, "by": d.owner, "lives": p.lives})
			if p.lives <= 0:
				_eliminate(p)


func _eliminate(p: PlayerSim) -> void:
	p.eliminated = true
	p.place = alive_players().size() + 1
	if p.drone_id != 0 and drones.has(p.drone_id):
		var d: DroneState = drones[p.drone_id]
		drones.erase(d.id)
		events.append({"t": "boom", "pid": p.pid, "id": d.id, "pos": d.pos, "kind": d.kind, "cause": "out", "by": 0})
	p.drone_id = 0
	events.append({"t": "out", "pid": p.pid, "place": p.place})


func eliminate_player(pid: int) -> void:
	if players.has(pid) and not players[pid].eliminated:
		_eliminate(players[pid])
		_check_victory()


func _check_victory() -> void:
	if finished or players.size() < 1:
		return
	var alive := alive_players()
	var need := 1 if players.size() > 1 else 0
	if alive.size() <= need:
		finished = true
		if alive.size() == 1:
			winner = alive[0].pid
			alive[0].place = 1
		else:
			winner = 0
		events.append({"t": "end", "winner": winner})


func take_events() -> Array:
	var e := events
	events = []
	return e
