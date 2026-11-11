extends Node
## Выделенный сервер «Оператора»: комнаты по 6-значному коду внутри одного процесса.
## Запуск: godot --headless --path . -- --server [--port=27630]
## или собранный бинарь: Operator --headless -- --server

var transport := Transport.new()
var clients := {}     # peer id -> {name, room, chat_t, hello}
var rooms := {}       # code -> Room
var rng := RandomNumberGenerator.new()
var _stats_t := 0.0
var _tick_us := 0
var _ticks := 0
var port := 0
var _exit_when_empty := false
var _had_clients := false
var _max_tick_us := 0


func _ready() -> void:
	rng.randomize()
	Engine.physics_ticks_per_second = SimConst.TICK_RATE
	Engine.max_fps = 0
	port = NetConfig.server_port()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
	_exit_when_empty = OS.get_cmdline_user_args().has("--exit-when-empty")
	var err := transport.listen(port)
	if err != OK:
		printerr("Не удалось открыть порт %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	transport.peer_connected.connect(_on_connect)
	transport.peer_disconnected.connect(_on_disconnect)
	transport.packet.connect(_on_packet)
	print("Оператор: сервер слушает UDP %d (протокол %d)" % [port, NetConfig.PROTOCOL_VERSION])


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	transport.poll()
	for code in rooms.keys():
		var r: Room = rooms[code]
		r.tick()
		if r.is_empty():
			rooms.erase(code)
			print("комната %s закрыта" % code)
	var dt_us := Time.get_ticks_usec() - t0
	_tick_us += dt_us
	_max_tick_us = maxi(_max_tick_us, dt_us)
	_ticks += 1
	if clients.size() > 0:
		_had_clients = true
	elif _exit_when_empty and _had_clients:
		print("все отключились: средний тик %.3f мс, максимум %.2f мс (бюджет %.1f мс)" % [avg_tick_ms(), _max_tick_us / 1000.0, 1000.0 / SimConst.TICK_RATE])
		get_tree().quit(0)
	_stats_t += delta
	if _stats_t >= 60.0:
		print("игроков %d, комнат %d, средний тик %.2f мс" % [clients.size(), rooms.size(), _tick_us / 1000.0 / maxi(_ticks, 1)])
		_stats_t = 0.0
		_tick_us = 0
		_ticks = 0


func avg_tick_ms() -> float:
	return _tick_us / 1000.0 / maxi(_ticks, 1)


func _on_connect(id: int) -> void:
	clients[id] = {"name": "", "room": "", "chat_t": 0.0, "hello": false}


func _on_disconnect(id: int) -> void:
	_leave_room(id)
	clients.erase(id)


func _send(id: int, type: int, payload, reliable := true) -> void:
	transport.send(id, Proto.pack(type, payload), reliable)


func _error(id: int, text: String) -> void:
	_send(id, Proto.ERROR, {"text": text})


func _on_packet(id: int, data: PackedByteArray) -> void:
	var msg := Proto.unpack(data)
	if msg.is_empty() or not clients.has(id):
		return
	var c: Dictionary = clients[id]
	var type: int = msg[0]
	var p = msg[1]
	if type == Proto.PING:
		_send(id, Proto.PONG, Proto.dict(p), false)
		return
	if type != Proto.HELLO and not c.hello:
		return
	var room: Room = rooms.get(c.room)
	match type:
		Proto.HELLO:
			var d := Proto.dict(p)
			# Симуляция общая: клиент другой версии игры рассинхронится, даже если протокол тот же.
			if int(d.get("ver", 0)) != NetConfig.PROTOCOL_VERSION \
					or Proto.clean_text(d.get("game", ""), 16) != NetConfig.GAME_VERSION:
				_error(id, "Версия игры не совпадает с сервером — обновите игру в лаунчере")
				return
			var n := _clean_name(d.get("name", ""))
			c.name = n
			c.hello = true
			_send(id, Proto.WELCOME, {"id": id, "name": n})
		Proto.RENAME:
			c.name = _clean_name(Proto.dict(p).get("name", ""))
		Proto.LIST:
			var list := []
			for r in rooms.values():
				if r.public:
					list.append(r.summary())
			list.sort_custom(func(a, b): return a.status < b.status)
			_send(id, Proto.ROOMS, list.slice(0, 50))
		Proto.CREATE:
			_leave_room(id)
			var d := Proto.dict(p)
			var code := _new_code()
			var r := Room.new(code, _send)
			r.title = Proto.clean_text(d.get("title", ""), 32)
			if r.title == "":
				r.title = "Лобби %s" % c.name
			r.public = bool(d.get("public", true))
			r.slots = clampi(int(d.get("slots", 8)), 2, SimConst.MAX_PLAYERS)
			r.lives = clampi(int(d.get("lives", 3)), 1, 5)
			r.bots = bool(d.get("bots", true))
			rooms[code] = r
			c.room = code
			r.add_member(id, c.name)
			print("комната %s создана (%s)" % [code, r.title])
		Proto.JOIN:
			var code := Proto.clean_text(Proto.dict(p).get("code", ""), 6)
			var r: Room = rooms.get(code)
			if r == null:
				_error(id, "Лобби с кодом %s не найдено" % code)
				return
			if c.room == code:
				r.broadcast_state()
				return
			_leave_room(id)
			var err := r.add_member(id, c.name)
			if err != "":
				_error(id, err)
				return
			c.room = code
		Proto.LEAVE:
			_leave_room(id)
		Proto.READY:
			if room:
				room.set_ready(id, bool(Proto.dict(p).get("ready", false)))
		Proto.LOADOUT:
			if room:
				var d := Proto.dict(p)
				room.set_loadout(id, int(d.get("style", 0)), int(d.get("kind", 0)), int(d.get("model", 0)))
		Proto.CHAT:
			if room:
				var now := Time.get_ticks_msec() / 1000.0
				if now - float(c.chat_t) < 0.4:
					return
				c.chat_t = now
				room.on_chat(id, Proto.clean_text(Proto.dict(p).get("text", ""), Proto.MAX_CHAT))
		Proto.START:
			if room:
				var err := room.start(id)
				if err != "":
					_error(id, err)
		Proto.KICK:
			if room:
				var target := int(Proto.dict(p).get("pid", 0))
				var err := room.kick(id, target)
				if err != "":
					_error(id, err)
				elif clients.has(target):
					clients[target].room = ""
		Proto.SETTINGS:
			if room:
				var err := room.apply_settings(id, Proto.dict(p))
				if err != "":
					_error(id, err)
		Proto.INPUT:
			if room:
				room.on_input(id, p)
		Proto.ACTION:
			if room:
				room.on_action(id, Proto.dict(p))


func _leave_room(id: int) -> void:
	if not clients.has(id):
		return
	var code: String = clients[id].room
	if code != "" and rooms.has(code):
		rooms[code].remove_member(id)
	clients[id].room = ""


func _new_code() -> String:
	for i in 1000:
		var code := "%06d" % rng.randi_range(0, 999999)
		if not rooms.has(code):
			return code
	return "%06d" % rng.randi_range(0, 999999)


func _clean_name(raw) -> String:
	var n := ""
	if typeof(raw) == TYPE_STRING:
		n = load("res://game/settings.gd").clean_name(raw)
	if n.length() < 2:
		n = "Оператор %d" % rng.randi_range(10, 99)
	return n
