extends SceneTree
## Headless-клиент для проверки сети: подключается к серверу, создаёт лобби или входит по коду,
## играет автопилотом через тот же протокол, что и игра, и печатает итог.
## godot --headless --path . -s res://tools/robot_client.gd -- --name=Робот --create --slots=8 --code-file=/tmp/code
## godot --headless --path . -s res://tools/robot_client.gd -- --name=Робот2 --code-file=/tmp/code

var net: NetClient
var args := {}
var rw := RemoteWorld.new()
var pilot: BotAI
var timeout := 900.0
var started := false
var done := false
var snaps := 0
var events := 0
var ready_sent := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		args[s.substr(0, i) if i >= 0 else s] = s.substr(i + 1) if i >= 0 else ""
	timeout = float(args.get("timeout", "900"))
	var settings: Node = load("res://game/settings.gd").new()
	settings.name = "Settings"
	root.add_child(settings)
	net = NetClient.new()
	root.add_child(net)
	rw.client = net
	net.online.connect(_on_online)
	net.offline.connect(func(r): _fail("offline: " + r))
	net.error_msg.connect(func(t): print("[%s] ошибка сервера: %s" % [_n(), t]))
	net.room_state.connect(_on_room)
	net.match_started.connect(func(_i):
		started = true
		pilot = BotAI.new(net.my_id, 0.8, net.my_id)
		net.feed.game_event.connect(func(_e): events += 1)
		print("[%s] матч начался, участников %d" % [_n(), net.feed.players.size()]))
	net.match_ended.connect(_on_end)
	net.chat.connect(func(m): if str(m.get("text", "")).begins_with("на связи"): print("[%s] чат: %s" % [_n(), m.text]))
	net.connect_server(args.get("name", "Робот"))


func _n() -> String:
	return args.get("name", "Робот")


func _on_online(id: int) -> void:
	print("[%s] на связи, id %d" % [_n(), id])
	if args.has("create"):
		net.send(Proto.CREATE, {"title": args.get("title", "Смоук"), "public": true, "slots": int(args.get("slots", "8")),
			"lives": int(args.get("lives", "2")), "bots": true})
	else:
		var code := ""
		for i in 200:
			if FileAccess.file_exists(args.get("code-file", "")):
				code = FileAccess.get_file_as_string(args["code-file"]).strip_edges()
				if code.length() == 6:
					break
			OS.delay_msec(100)
		net.send(Proto.LIST)
		net.send(Proto.JOIN, {"code": code})


func _on_room(st: Dictionary) -> void:
	if args.has("create") and args.has("code-file"):
		var f := FileAccess.open(args["code-file"], FileAccess.WRITE)
		f.store_string(str(st.code))
		f.close()
	var humans: Array = st.get("players", [])
	if str(st.get("status", "")) != "lobby":
		return
	if done:
		return
	if not args.has("create") and not ready_sent:
		ready_sent = true
		net.send(Proto.CHAT, {"text": "на связи, готов к вылету"})
		net.send(Proto.LOADOUT, {"style": 2, "kind": 1})
		net.send(Proto.READY, {"ready": true})
	if args.has("create") and not started:
		var need := int(args.get("humans", "1"))
		var all_ready := true
		for p in humans:
			if int(p.pid) != net.my_id and not p.ready:
				all_ready = false
		if humans.size() >= need and all_ready:
			net.send(Proto.START)


func _on_end(info: Dictionary) -> void:
	var w := int(info.get("winner", 0))
	var wn := "ничья"
	for r in info.get("table", []):
		if int(r.pid) == w:
			wn = r.name
	print("[%s] МАТЧ ОКОНЧЕН: победитель %s; снапшотов %d, событий %d, время %.0f с" % [_n(), wn, snaps, events, net.feed.match_time() if net.feed else 0.0])
	for r in info.get("table", []):
		print("    %d. %s попаданий %d таранов %d" % [int(r.place), r.name, int(r.hits), int(r.rams)])
	done = true
	if not args.has("stay"):
		quit(0)


func _fail(msg: String) -> void:
	printerr("[%s] %s" % [_n(), msg])
	quit(2)


func _process(delta: float) -> bool:
	timeout -= delta
	if timeout <= 0.0:
		_fail("таймаут")
		return true
	if net.feed != null and started and not done:
		var f: FeedNet = net.feed
		snaps = f._latest_tick
		rw.sync_from(f)
		var inp := pilot.think(rw)
		f.update(delta, inp)
	return false
