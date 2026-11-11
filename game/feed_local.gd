class_name FeedLocal
extends RefCounted
## Источник состояния матча для тренировки: симуляция крутится прямо в клиенте вместе с ботами.
## Интерфейс общий с FeedNet: terrain, players, my_pid, render_drones(), события.

signal game_event(ev: Dictionary)

var world := WorldSim.new()
var terrain: Terrain
var players: Dictionary
var my_pid := 1
var bots := {}
var acc := 0.0
var _prev := {}   # id -> DroneState на прошлом тике
var _cur := {}
var _pending_kind := -1
var _pending_trap := false
var _pending_detonate := false
var ping_ms := 0.0
var autopilot: BotAI   # для проверки: своим дроном управляет бот


func start(seed: int, roster: Array, lives: int, my: int) -> void:
	my_pid = my
	world.setup(seed, roster, lives)
	terrain = world.terrain
	players = world.players
	var i := 0
	for p in world.players.values():
		if p.bot:
			bots[p.pid] = BotAI.new(p.pid, 0.45 + 0.1 * (i % 5), seed + p.pid)
		i += 1


func match_time() -> float:
	return world.time


func sudden_death() -> bool:
	return world.sudden_death


func finished() -> bool:
	return world.finished


func winner() -> int:
	return world.winner


func set_kind(k: int) -> void:
	_pending_kind = k


func trap() -> void:
	_pending_trap = true


func detonate() -> void:
	_pending_detonate = true


func update(delta: float, input: DroneInput) -> void:
	acc += delta
	var steps := 0
	while acc >= SimConst.DT and steps < 4:
		acc -= SimConst.DT
		steps += 1
		if _pending_kind >= 0:
			world.set_kind(my_pid, _pending_kind)
			_pending_kind = -1
		if _pending_trap:
			world.trigger_trap(my_pid)
			_pending_trap = false
		if _pending_detonate:
			world.detonate(my_pid)
			_pending_detonate = false
		var inputs := {my_pid: input if autopilot == null else autopilot.think(world)}
		for pid in bots:
			inputs[pid] = bots[pid].think(world)
		_prev = _cur
		world.step(inputs)
		_cur = {}
		for d in world.drones.values():
			_cur[d.id] = d.clone()
		for ev in world.take_events():
			game_event.emit(ev)
	if acc > SimConst.DT:
		acc = 0.0


## Интерполированные состояния дронов на текущий кадр.
func render_drones() -> Dictionary:
	var a := clampf(acc / SimConst.DT, 0.0, 1.0)
	var out := {}
	for id in _cur:
		var c: DroneState = _cur[id]
		if _prev.has(id):
			out[id] = Interp.lerp_state(_prev[id], c, a)
		else:
			out[id] = c
	return out


func close() -> void:
	pass
