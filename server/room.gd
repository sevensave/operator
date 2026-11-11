class_name Room
extends RefCounted
## Комната: лобби (игроки, готовность, хост, чат, настройки) и матч (симуляция, боты, снапшоты).

const BOT_NAMES := ["Сокол", "Пчела", "Филин", "Шмель", "Стриж", "Грач", "Кедр", "Ёрш", "Клён", "Сыч"]
const RETURN_DELAY := 6.0

var code := ""
var title := ""
var public := true
var slots := 8
var lives := 3
var bots := true
var host := 0
var members: Array = []        # pid в порядке входа
var info := {}                 # pid -> {name, color, style, kind, ready}
var chat: Array = []           # последние сообщения
var status := "lobby"          # lobby | match
var results: Array = []        # итоги прошлого матча
var send: Callable             # send(pid, type, payload, reliable)

var world: WorldSim
var bot_ai := {}               # pid -> BotAI
var inbuf := {}                # pid -> Array[DroneInput]
var last_in := {}              # pid -> DroneInput
var acks := {}                 # pid -> последний применённый seq
var _end_timer := -1.0
var _bot_pid := -1
var created := 0.0


func _init(p_code: String, p_send: Callable) -> void:
	code = p_code
	send = p_send
	created = Time.get_unix_time_from_system()


func humans() -> Array:
	return members.duplicate()


func is_empty() -> bool:
	return members.is_empty()


func summary() -> Dictionary:
	return {"code": code, "title": title, "host": info[host].name if info.has(host) else "",
		"players": members.size(), "slots": slots, "status": status}


func _free_color() -> int:
	var used := {}
	for pid in info:
		used[info[pid].color] = true
	for c in SimConst.MAX_PLAYERS:
		if not used.has(c):
			return c
	return 0


func _unique_name(n: String) -> String:
	var taken := {}
	for pid in info:
		taken[info[pid].name] = true
	if not taken.has(n):
		return n
	for i in range(2, 20):
		var cand := "%s %d" % [n.substr(0, 13), i]
		if not taken.has(cand):
			return cand
	return n


## Возвращает "" или текст ошибки.
func add_member(pid: int, name: String) -> String:
	if members.size() >= slots:
		return "Лобби заполнено"
	if status != "lobby":
		return "Матч уже идёт — дождитесь конца"
	members.append(pid)
	info[pid] = {"name": _unique_name(name), "color": _free_color(), "style": 0, "model": 0, "kind": 0, "ready": false}
	if host == 0 or not info.has(host):
		host = pid
	system_chat("%s заходит в лобби" % info[pid].name)
	broadcast_state()
	return ""


func remove_member(pid: int) -> void:
	if not info.has(pid):
		return
	var n: String = info[pid].name
	members.erase(pid)
	info.erase(pid)
	inbuf.erase(pid)
	if status == "match" and world != null:
		world.eliminate_player(pid)
		_flush_events()
	if host == pid:
		host = members[0] if members.size() > 0 else 0
		if host != 0:
			system_chat("%s теперь хост" % info[host].name)
	system_chat("%s выходит" % n)
	broadcast_state()


func system_chat(text: String) -> void:
	_add_chat({"from": 0, "name": "", "text": text, "color": -1})


func _add_chat(m: Dictionary) -> void:
	chat.append(m)
	if chat.size() > 40:
		chat.pop_front()
	for pid in members:
		send.call(pid, Proto.CHAT_MSG, m, true)


func on_chat(pid: int, text: String) -> void:
	if text == "" or not info.has(pid):
		return
	_add_chat({"from": pid, "name": info[pid].name, "text": text, "color": info[pid].color})


func state_for(_pid: int) -> Dictionary:
	var list := []
	for pid in members:
		var i: Dictionary = info[pid]
		list.append({"pid": pid, "name": i.name, "color": i.color, "style": i.style, "model": i.model, "kind": i.kind, "ready": i.ready})
	return {"code": code, "title": title, "public": public, "slots": slots, "lives": lives, "bots": bots,
		"host": host, "players": list, "status": status, "results": results, "chat": chat}


func broadcast_state() -> void:
	for pid in members:
		send.call(pid, Proto.ROOM, state_for(pid), true)


func set_ready(pid: int, r: bool) -> void:
	if info.has(pid) and status == "lobby":
		info[pid].ready = r
		broadcast_state()


func set_loadout(pid: int, style: int, kind: int, model := 0) -> void:
	if info.has(pid):
		info[pid].style = clampi(style, 0, SimConst.SHELTER_STYLES.size() - 1)
		info[pid].model = clampi(model, 0, SimConst.MODEL_COUNT - 1)
		info[pid].kind = clampi(kind, 0, 1)
		if status == "match" and world != null:
			world.set_kind(pid, info[pid].kind)
		broadcast_state()


func apply_settings(pid: int, d: Dictionary) -> String:
	if pid != host:
		return "Настройки меняет только хост"
	if status != "lobby":
		return "Нельзя менять настройки во время матча"
	if d.has("title"):
		var t := Proto.clean_text(d.title, 32)
		if t != "":
			title = t
	if d.has("public"):
		public = bool(d.public)
	if d.has("slots"):
		slots = clampi(int(d.slots), maxi(2, members.size()), SimConst.MAX_PLAYERS)
	if d.has("lives"):
		lives = clampi(int(d.lives), 1, 5)
	if d.has("bots"):
		bots = bool(d.bots)
	broadcast_state()
	return ""


func kick(by: int, pid: int) -> String:
	if by != host:
		return "Исключать может только хост"
	if pid == host or not info.has(pid):
		return "Нельзя исключить этого игрока"
	send.call(pid, Proto.KICKED, {"text": "Хост исключил вас из лобби"}, true)
	remove_member(pid)
	return ""


func start(by: int) -> String:
	if by != host:
		return "Матч запускает хост"
	if status != "lobby":
		return "Матч уже идёт"
	for pid in members:
		if pid != host and not info[pid].ready:
			return "Не все игроки готовы"
	var total := members.size()
	if bots:
		total = slots
	if total < 2:
		return "Нужно хотя бы двое: позовите друга или включите ботов"
	var roster := []
	for pid in members:
		var i: Dictionary = info[pid]
		roster.append({"pid": pid, "name": i.name, "color": i.color, "style": i.style, "model": i.model, "kind": i.kind, "bot": false})
	bot_ai.clear()
	var used_colors := {}
	for r in roster:
		used_colors[r.color] = true
	var bi := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var taken := {}
	for pid in info:
		taken[info[pid].name] = true
	var free_names := BOT_NAMES.filter(func(n): return not taken.has(n))
	while roster.size() < total:
		var c := 0
		while used_colors.has(c):
			c += 1
		used_colors[c] = true
		var bpid := _bot_pid
		_bot_pid -= 1
		roster.append({"pid": bpid, "name": free_names[bi % free_names.size()] + " (бот)", "color": c,
			"style": rng.randi() % 4, "model": rng.randi() % SimConst.MODEL_COUNT, "kind": rng.randi() % 2, "bot": true})
		bot_ai[bpid] = BotAI.new(bpid, rng.randf_range(0.45, 0.85), rng.randi())
		bi += 1
	world = WorldSim.new()
	var seed := rng.randi() % 1000000
	world.setup(seed, roster, lives)
	inbuf.clear()
	last_in.clear()
	acks.clear()
	for pid in members:
		inbuf[pid] = []
		last_in[pid] = DroneInput.new()
		acks[pid] = 0
	status = "match"
	_end_timer = -1.0
	for pid in members:
		send.call(pid, Proto.MATCH_START, {"seed": seed, "roster": roster, "lives": lives, "me": pid}, true)
	broadcast_state()
	return ""


## Пачка вводов от клиента: последние несколько команд для устойчивости к потерям.
func on_input(pid: int, arr) -> void:
	if status != "match" or not inbuf.has(pid) or typeof(arr) != TYPE_ARRAY:
		return
	var buf: Array = inbuf[pid]
	var newest := int(acks.get(pid, 0))
	if buf.size() > 0:
		newest = buf[buf.size() - 1].seq
	for a in arr.slice(0, 8):
		if typeof(a) != TYPE_ARRAY:
			continue
		var inp := DroneInput.from_array(a)
		if inp.seq > newest:
			buf.append(inp)
			newest = inp.seq
	# Клиент убежал вперёд — догоняем, выкидывая старое.
	while buf.size() > 6:
		buf.pop_front()


func on_action(pid: int, d: Dictionary) -> void:
	if status != "match" or world == null:
		return
	match str(d.get("a", "")):
		"trap":
			world.trigger_trap(pid)
		"detonate":
			world.detonate(pid)
		"kind":
			world.set_kind(pid, int(d.get("v", 0)))
			if info.has(pid):
				info[pid].kind = clampi(int(d.get("v", 0)), 0, 1)


func tick() -> void:
	if status != "match" or world == null:
		return
	if _end_timer >= 0.0:
		_end_timer -= SimConst.DT
		if _end_timer <= 0.0:
			_back_to_lobby()
		return
	var inputs := {}
	for pid in members:
		var buf: Array = inbuf.get(pid, [])
		if buf.size() > 0:
			var inp: DroneInput = buf.pop_front()
			last_in[pid] = inp
			acks[pid] = inp.seq
		inputs[pid] = last_in.get(pid, DroneInput.new())
	for pid in bot_ai:
		inputs[pid] = bot_ai[pid].think(world)
	world.step(inputs)
	_flush_events()
	if world.tick % 3 != 2:  # 20 Гц
		_send_snapshot()
	if world.finished:
		_send_snapshot()
		_finish()


func _flush_events() -> void:
	var ev := world.take_events()
	if ev.is_empty():
		return
	for pid in members:
		send.call(pid, Proto.EVENTS, ev, true)


func _send_snapshot() -> void:
	var db := StreamPeerBuffer.new()
	for d in world.drones.values():
		d.write(db)
	var pb := StreamPeerBuffer.new()
	for p in world.players.values():
		p.write(pb)
	var drones := db.data_array
	var players := pb.data_array
	var flags := (1 if world.sudden_death else 0) | (2 if world.finished else 0)
	var snap := [world.tick, world.time, flags, drones, players, acks.duplicate(), world.winner]
	for pid in members:
		send.call(pid, Proto.SNAP, snap, false)


func _finish() -> void:
	var table := []
	for p in world.players.values():
		table.append({"pid": p.pid, "name": p.name, "color": p.color, "place": p.place if p.place > 0 else 1,
			"hits": p.hits, "rams": p.rams, "lives": maxi(p.lives, 0), "bot": p.bot})
	table.sort_custom(func(a, b): return a.place < b.place)
	results = table
	for pid in members:
		send.call(pid, Proto.MATCH_END, {"winner": world.winner, "table": table}, true)
	_end_timer = RETURN_DELAY
	var wn := "ничья"
	if world.players.has(world.winner):
		wn = world.players[world.winner].name
	system_chat("Матч окончен: %s" % ("победил " + wn if world.winner != 0 else wn))


func _back_to_lobby() -> void:
	status = "lobby"
	world = null
	bot_ai.clear()
	for pid in info:
		info[pid].ready = false
	broadcast_state()
