class_name NetClient
extends Node
## Соединение клиента с сервером: приветствие, лобби, матч. Сигналы — для экранов UI.

signal online(my_id: int)
signal offline(reason: String)
signal rooms_listed(list: Array)
signal room_state(state: Dictionary)
signal chat(msg: Dictionary)
signal error_msg(text: String)
signal match_started(info: Dictionary)
signal match_ended(info: Dictionary)
signal kicked(text: String)

var transport: Transport
var my_id := 0
var my_name := ""
var state := "idle"     # idle | connecting | online
var room: Dictionary = {}
var feed: FeedNet
var _ping_t := 0.0
var _connect_timeout := 0.0


func connect_server(name: String) -> void:
	if state != "idle":
		return
	my_name = name
	transport = Transport.new()
	var err := transport.connect_to(NetConfig.host(), NetConfig.port())
	if err != OK:
		state = "idle"
		offline.emit("Не удалось подключиться: %s" % error_string(err))
		return
	state = "connecting"
	_connect_timeout = 6.0
	transport.connected.connect(_on_connected)
	transport.connection_failed.connect(func(): _drop("Сервер недоступен"))
	transport.peer_disconnected.connect(func(_id): _drop("Соединение с сервером потеряно"))
	transport.packet.connect(_on_packet)


func _on_connected() -> void:
	send(Proto.HELLO, {"name": my_name, "ver": NetConfig.PROTOCOL_VERSION, "game": NetConfig.GAME_VERSION})


func _drop(reason: String) -> void:
	if state == "idle":
		return
	state = "idle"
	room = {}
	if transport:
		transport.close()
	transport = null
	offline.emit(reason)


func disconnect_server() -> void:
	if transport:
		transport.close()
	transport = null
	state = "idle"
	room = {}


func send(type: int, payload = {}, reliable := true) -> void:
	if transport:
		transport.send(1, Proto.pack(type, payload), reliable)


func _process(delta: float) -> void:
	if transport == null:
		return
	transport.poll()
	if state == "connecting":
		_connect_timeout -= delta
		if _connect_timeout <= 0.0:
			_drop("Сервер не отвечает")
			return
	if state == "online":
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			send(Proto.PING, {"t": Time.get_ticks_msec()}, false)


func _on_packet(_from: int, data: PackedByteArray) -> void:
	var msg := Proto.unpack(data)
	if msg.is_empty():
		return
	var p = msg[1]
	match msg[0]:
		Proto.WELCOME:
			var d := Proto.dict(p)
			my_id = int(d.get("id", 0))
			my_name = str(d.get("name", my_name))
			state = "online"
			online.emit(my_id)
		Proto.ROOMS:
			rooms_listed.emit(p if typeof(p) == TYPE_ARRAY else [])
		Proto.ROOM:
			room = Proto.dict(p)
			room_state.emit(room)
		Proto.CHAT_MSG:
			chat.emit(Proto.dict(p))
		Proto.ERROR:
			error_msg.emit(str(Proto.dict(p).get("text", "Ошибка")))
		Proto.KICKED:
			room = {}
			kicked.emit(str(Proto.dict(p).get("text", "")))
		Proto.MATCH_START:
			var d := Proto.dict(p)
			feed = FeedNet.new()
			feed.client = self
			feed.start(int(d.seed), d.roster, int(d.lives), int(d.me))
			match_started.emit(d)
		Proto.SNAP:
			if feed and typeof(p) == TYPE_ARRAY:
				feed.on_snapshot(p)
		Proto.EVENTS:
			if feed and typeof(p) == TYPE_ARRAY:
				feed.on_events(p)
		Proto.MATCH_END:
			if feed:
				feed.on_end(Proto.dict(p))
			match_ended.emit(Proto.dict(p))
		Proto.PONG:
			var t := int(Proto.dict(p).get("t", 0))
			if feed:
				feed.ping_ms = lerpf(feed.ping_ms if feed.ping_ms > 0 else float(Time.get_ticks_msec() - t), float(Time.get_ticks_msec() - t), 0.3)
