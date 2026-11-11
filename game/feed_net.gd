class_name FeedNet
extends RefCounted
## Состояние матча по сети: свой дрон предсказывается тем же симулятором и сверяется
## со снапшотами сервера, чужие — интерполируются с задержкой ~100 мс.

signal game_event(ev: Dictionary)

const INTERP_TICKS := 3.0

var client
var world := WorldSim.new()    # только ландшафт и игроки; шаги делает сервер
var terrain: Terrain
var players: Dictionary
var my_pid := 0
var ping_ms := 0.0

var _snaps: Array = []          # [{tick, drones: {id: DroneState}}]
var _latest_tick := 0
var _render_tick := 0.0
var _time := 0.0
var _sudden := false
var _finished := false
var _winner := 0
var _acc := 0.0
var _seq := 0
var _pending: Array = []        # отправленные, но не подтверждённые вводы
var _pred: DroneState           # предсказанный свой дрон
var _pred_prev: DroneState
var _pred_id := 0
var _err_pos := Vector3.ZERO    # визуальное сглаживание поправок
var _local_tick := 0
var _pending_kind := -1


func start(seed: int, roster: Array, lives: int, me: int) -> void:
	my_pid = me
	world.setup(seed, roster, lives)
	terrain = world.terrain
	players = world.players


func match_time() -> float:
	return _time


func sudden_death() -> bool:
	return _sudden


func finished() -> bool:
	return _finished


func winner() -> int:
	return _winner


func set_kind(k: int) -> void:
	client.send(Proto.ACTION, {"a": "kind", "v": k})


func trap() -> void:
	client.send(Proto.ACTION, {"a": "trap"})


func detonate() -> void:
	client.send(Proto.ACTION, {"a": "detonate"})


func close() -> void:
	pass


func on_snapshot(s: Array) -> void:
	if s.size() < 7:
		return
	var tick := int(s[0])
	if tick <= _latest_tick:
		return
	_latest_tick = tick
	_time = float(s[1])
	_sudden = (int(s[2]) & 1) != 0
	_finished = (int(s[2]) & 2) != 0
	_winner = int(s[6])
	var ds := {}
	if typeof(s[3]) != TYPE_PACKED_BYTE_ARRAY or typeof(s[4]) != TYPE_PACKED_BYTE_ARRAY:
		return
	var db := StreamPeerBuffer.new()
	db.data_array = s[3]
	while db.get_available_bytes() >= 46:
		var d := DroneState.read(db)
		ds[d.id] = d
	var pb := StreamPeerBuffer.new()
	pb.data_array = s[4]
	var tmp := PlayerSim.new()
	while pb.get_available_bytes() >= 18:
		tmp.read(pb)
		if players.has(tmp.pid):
			players[tmp.pid].copy_net(tmp)
	_snaps.append({"tick": tick, "drones": ds})
	while _snaps.size() > 30:
		_snaps.pop_front()
	if _render_tick == 0.0:
		_render_tick = tick - INTERP_TICKS
	# Сверка своего дрона.
	var me: PlayerSim = players.get(my_pid)
	var ack := int(s[5].get(my_pid, 0)) if typeof(s[5]) == TYPE_DICTIONARY else 0
	while _pending.size() > 0 and _pending[0].seq <= ack:
		_pending.pop_front()
	if me == null or me.drone_id == 0 or not ds.has(me.drone_id):
		_pred = null
		_pred_id = 0
		return
	var server_d: DroneState = ds[me.drone_id]
	var old_pos := _pred.pos if _pred != null and _pred_id == server_d.id else server_d.pos
	_pred = server_d.clone()
	_pred_id = server_d.id
	_local_tick = tick
	# Пока дрон без управления или в сети — доверяем серверу без переигровки.
	if server_d.control and server_d.trapped <= 0.0:
		for inp in _pending:
			_step_pred(inp)
	_err_pos += old_pos - _pred.pos
	if _err_pos.length() > 8.0:
		_err_pos = Vector3.ZERO  # слишком далеко — просто телепорт
	_pred_prev = _pred.clone()


func _step_pred(inp: DroneInput) -> void:
	_local_tick += 1
	var t := _local_tick * SimConst.DT
	var ground := terrain.height_at(_pred.pos.x, _pred.pos.z)
	var air := Wind.at(_pred.pos, t, world.seed, ground)
	if _pred.kind == SimConst.Kind.PLANE:
		FlightPlane.step(_pred, inp, SimConst.DT, air)
	else:
		FlightCopter.step(_pred, inp, SimConst.DT, air)


## Самый свежий снапшот дронов (для автопилота).
func latest_drones() -> Dictionary:
	return _snaps[_snaps.size() - 1].drones if _snaps.size() > 0 else {}


func on_events(list: Array) -> void:
	for ev in list:
		if typeof(ev) == TYPE_DICTIONARY and ev.has("t"):
			game_event.emit(ev)


func on_end(d: Dictionary) -> void:
	_finished = true
	_winner = int(d.get("winner", 0))


func update(delta: float, input: DroneInput) -> void:
	_acc += delta
	var steps := 0
	while _acc >= SimConst.DT and steps < 4:
		_acc -= SimConst.DT
		steps += 1
		_seq += 1
		var inp := input.duplicate_input()
		inp.seq = _seq
		_pending.append(inp)
		while _pending.size() > 90:
			_pending.pop_front()
		var bundle := []
		for i in range(maxi(0, _pending.size() - 4), _pending.size()):
			bundle.append(_pending[i].to_array())
		client.send(Proto.INPUT, bundle, false)
		if _pred != null and _pred.control and _pred.trapped <= 0.0:
			_pred_prev = _pred.clone()
			_step_pred(inp)
	if _acc > SimConst.DT:
		_acc = 0.0
	# Часы интерполяции: идём в темпе сервера, мягко подтягиваясь к (последний тик − задержка).
	if _latest_tick > 0:
		_render_tick += delta * SimConst.TICK_RATE
		var target := _latest_tick - INTERP_TICKS
		var drift := target - _render_tick
		if absf(drift) > 15.0:
			_render_tick = target
		else:
			_render_tick += drift * minf(1.0, delta * 2.0)
	_err_pos = _err_pos.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))


func render_drones() -> Dictionary:
	var out := {}
	# Чужие — интерполяция между снапшотами вокруг _render_tick.
	var a: Dictionary = {}
	var b: Dictionary = {}
	for i in range(_snaps.size() - 1, -1, -1):
		if _snaps[i].tick <= _render_tick:
			a = _snaps[i]
			if i + 1 < _snaps.size():
				b = _snaps[i + 1]
			break
	if a.is_empty() and _snaps.size() > 0:
		a = _snaps[0]
	if not a.is_empty():
		var t := 0.0
		if not b.is_empty():
			t = clampf((_render_tick - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
		for id in a.drones:
			var da: DroneState = a.drones[id]
			if not b.is_empty() and b.drones.has(id):
				out[id] = Interp.lerp_state(da, b.drones[id], t)
			elif b.is_empty():
				out[id] = da
		if not b.is_empty():
			for id in b.drones:
				if not out.has(id) and not a.drones.has(id):
					out[id] = b.drones[id]
	# Свой — предсказание.
	if _pred != null:
		var alpha := clampf(_acc / SimConst.DT, 0.0, 1.0)
		var d: DroneState = Interp.lerp_state(_pred_prev if _pred_prev != null else _pred, _pred, alpha)
		d.pos += _err_pos
		out[_pred_id] = d
	return out
