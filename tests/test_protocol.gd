extends RefCounted
## Протокол и правила комнаты: лобби, хост, готовность, матч до победителя и возврат в лобби.

var t
var sent: Array = []


func _send(pid: int, type: int, payload, reliable: bool) -> void:
	# Через упаковку, как в сети, чтобы поймать неупаковываемые данные.
	var bytes := Proto.pack(type, payload)
	var back := Proto.unpack(bytes)
	sent.append([pid, back[0], back[1], reliable, bytes.size()])


func _last(pid: int, type: int):
	for i in range(sent.size() - 1, -1, -1):
		if sent[i][0] == pid and sent[i][1] == type:
			return sent[i][2]
	return null


func test_pack_roundtrip_and_garbage() -> void:
	var b := Proto.pack(Proto.CHAT, {"text": "привет"})
	var m := Proto.unpack(b)
	t.check(m.size() == 2 and m[0] == Proto.CHAT and m[1].text == "привет", "упаковка туда-обратно")
	t.check(Proto.unpack(PackedByteArray([1, 2, 3])).is_empty(), "мусор отбрасывается")
	t.check(Proto.unpack(var_to_bytes("строка")).is_empty(), "не массив — отбрасывается")
	t.check(Proto.unpack(var_to_bytes([1, 2, 3])).is_empty(), "неверная длина — отбрасывается")
	t.check(Proto.clean_text("  a\u0007b  ", 10) == "ab", "управляющие символы вычищаются")


func test_names_cleaned() -> void:
	var S = load("res://game/settings.gd")
	t.check(S.clean_name("  Сокол-1  ") == "Сокол-1", "кириллица и дефис")
	t.check(S.clean_name("<b>Ёжик</b>") == "bЁжикb", "теги вычищаются")
	t.check(S.clean_name("абвгдеёжзийклмнопрст").length() == 16, "обрезка до 16")
	t.check(not S.name_valid("a"), "1 символ — мало")


func test_lobby_flow() -> void:
	sent.clear()
	var r := Room.new("123456", _send)
	r.title = "Тест"
	r.slots = 4
	r.bots = true
	t.check(r.add_member(10, "Сокол") == "", "хост вошёл")
	t.check(r.add_member(11, "Сокол") == "", "второй вошёл")
	t.check(r.info[11].name == "Сокол 2", "дубликат имени получает суффикс: %s" % r.info[11].name)
	t.check(r.host == 10, "первый — хост")
	t.check(r.info[10].color != r.info[11].color, "разные цвета")
	t.check(r.start(11) != "", "не хост не запускает")
	t.check(r.start(10) != "", "без готовности не запускается")
	r.set_ready(11, true)
	r.on_chat(11, "го")
	var ch = _last(10, Proto.CHAT_MSG)
	t.check(ch != null and ch.text == "го", "чат доходит до всех")
	t.check(r.apply_settings(11, {"lives": 5}) != "", "настройки — только хост")
	t.check(r.apply_settings(10, {"lives": 2, "slots": 3}) == "" and r.lives == 2 and r.slots == 3, "хост меняет настройки")
	t.check(r.kick(10, 11) == "" and not r.info.has(11), "хост исключил игрока")
	t.check(_last(11, Proto.KICKED) != null, "исключённому пришло уведомление")
	r.add_member(12, "Грач")
	r.remove_member(10)
	t.check(r.host == 12, "хост перешёл следующему")


func test_model_is_clamped_and_reaches_roster() -> void:
	sent.clear()
	var r := Room.new("654321", _send)
	r.slots = 4
	r.bots = true
	r.add_member(20, "Сокол")
	r.add_member(21, "Грач")
	r.set_loadout(20, 1, 0, 99)
	r.set_loadout(21, 0, 1, -7)
	t.check(r.info[20].model == SimConst.MODEL_COUNT - 1 and r.info[21].model == 0, "модель клампится сервером")
	r.set_ready(21, true)
	t.check(r.start(20) == "", "матч стартовал")
	var ms = _last(21, Proto.MATCH_START)
	t.check(ms != null, "MATCH_START дошёл")
	if ms == null:
		return
	var models := {}
	for e in ms.roster:
		models[int(e.pid)] = int(e.get("model", -1))
	t.check(models.get(20) == 2 and models.get(21) == 0, "модель игроков в ростере: %s" % models)
	for pid in models:
		t.check(models[pid] >= 0 and models[pid] < SimConst.MODEL_COUNT, "модель в допустимых пределах (%d)" % pid)
	t.check(r.world.players[20].model == 2, "модель доходит до PlayerSim")


func test_match_runs_to_winner_and_back_to_lobby() -> void:
	sent.clear()
	var r := Room.new("654321", _send)
	r.slots = 4
	r.lives = 1
	r.bots = true
	r.add_member(1, "Человек")
	t.check(r.start(1) == "", "один человек + боты — можно начать")
	t.check(r.status == "match", "матч идёт")
	var ms = _last(1, Proto.MATCH_START)
	t.check(ms != null and ms.roster.size() == 4, "в составе 4 участника")
	t.check(r.add_member(2, "Опоздавший") != "", "во время матча войти нельзя")
	# За человека играет автопилот, ввод идёт через тот же путь, что и по сети.
	var pilot := BotAI.new(1, 0.8, 5)
	var max_ticks := 12 * 60 * SimConst.TICK_RATE
	var snaps := 0
	for i in max_ticks:
		if r.world != null:
			var inp := pilot.think(r.world)
			inp.seq = i + 1
			r.on_input(1, [inp.to_array()])
		r.tick()
		if r.status == "lobby":
			break
	for s in sent:
		if s[1] == Proto.SNAP:
			snaps += 1
			t.check(s[4] < 1200, "снапшот помещается в UDP-пакет: %d байт" % s[4])
	t.check(r.status == "lobby", "после матча комната вернулась в лобби")
	t.check(r.results.size() == 4, "есть таблица итогов")
	var end = _last(1, Proto.MATCH_END)
	t.check(end != null, "пришёл конец матча")
	t.check(snaps > 100, "снапшоты шли: %d" % snaps)
	t.check(r.acks[1] > 0, "ввод человека применялся")


func test_input_bundle_dedup() -> void:
	sent.clear()
	var r := Room.new("111111", _send)
	r.add_member(1, "А")
	r.add_member(2, "Б")
	r.set_ready(2, true)
	r.start(1)
	r.on_input(1, [[1, 0, 0, 0, 0, 0], [2, 0, 0, 0, 0, 0]])
	r.on_input(1, [[1, 0, 0, 0, 0, 0], [2, 0, 0, 0, 0, 0], [3, 0, 0, 0, 0, 0]])
	t.check(r.inbuf[1].size() == 3, "повторы не дублируются: %d" % r.inbuf[1].size())
	r.on_input(1, "мусор")
	r.on_input(99, [[1, 0, 0, 0, 0, 0]])
	r.tick()
	t.check(r.acks[1] == 1, "применён первый ввод")


func test_snapshot_packing_compact() -> void:
	var w := WorldSim.new()
	var roster := []
	for i in 8:
		roster.append({"pid": -i - 1, "name": "Б%d" % i, "color": i})
	w.setup(9, roster, 3)
	for i in 60:
		w.step({})
	var db := StreamPeerBuffer.new()
	for d in w.drones.values():
		d.write(db)
	t.check(db.data_array.size() == 46 * 8, "дрон — 46 байт: всего %d" % db.data_array.size())
	var rb := StreamPeerBuffer.new()
	rb.data_array = db.data_array
	var first: DroneState = w.drones.values()[0]
	var back := DroneState.read(rb)
	t.check(back.id == first.id and back.owner == first.owner, "id и владелец")
	t.check(back.pos.distance_to(first.pos) < 0.001, "позиция точно")
	t.check(back.rot.angle_to(first.rot) < 0.01, "поворот почти точно")
	var pb := StreamPeerBuffer.new()
	for p in w.players.values():
		p.write(pb)
	t.check(pb.data_array.size() == 18 * 8, "игрок — 18 байт")
	var snap := Proto.pack(Proto.SNAP, [w.tick, w.time, 0, db.data_array, pb.data_array, {1: 100, 2: 200}, 0])
	t.check(snap.size() < 1000, "снапшот на 8 дронов < 1000 байт: %d" % snap.size())
