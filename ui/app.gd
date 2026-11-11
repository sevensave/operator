extends Node
## Экраны клиента: позывной → меню → лобби (создание, список, код) → матч → лобби с итогами.
## Тренировка — матч с ботами прямо в клиенте, без сервера.

var net: NetClient
var ui: Control                # текущий экран
var ui_layer: CanvasLayer
var toast: Label
var backdrop: Node3D           # облёт долины за меню
var match_view: MatchView
var feed
var _after_online := Callable()
var _toast_t := 0.0
var _list_t := 0.0
var _lobby := {}               # ссылки на виджеты экрана лобби
var _results_seen := false
var _training_end_t := -1.0


func _ready() -> void:
	net = NetClient.new()
	net.name = "Net"
	add_child(net)
	net.online.connect(_on_online)
	net.offline.connect(_on_offline)
	net.error_msg.connect(func(t): show_toast(t))
	net.rooms_listed.connect(_on_rooms)
	net.room_state.connect(_on_room_state)
	net.chat.connect(_on_chat)
	net.kicked.connect(func(t):
		show_toast(t)
		_leave_match_view()
		show_menu())
	net.match_started.connect(_on_match_started)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	toast = UiTheme.label("", 20, UiTheme.TEXT)
	toast.theme = UiTheme.theme()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position.y -= 60
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 6)
	var tl := CanvasLayer.new()
	tl.layer = 20
	add_child(tl)
	tl.add_child(toast)
	_build_backdrop()
	if Settings.player_name == "" or not Settings.name_valid(Settings.player_name):
		show_name(true)
	else:
		show_menu()
	_debug_flags()


## Флаги для автоматической проверки: --create-lobby, --join-code-file=путь, --autopilot, --ready.
func _debug_flags() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		args[s.substr(0, i) if i >= 0 else s] = s.substr(i + 1) if i >= 0 else ""
	if args.has("name"):
		Settings.player_name = args.name
	if args.has("create-lobby"):
		_online(func(): net.send(Proto.CREATE, {"title": "Проверка", "public": true, "slots": 6, "lives": 2, "bots": true}))
	elif args.has("join-code-file"):
		_online(func():
			var code := FileAccess.get_file_as_string(args["join-code-file"]).strip_edges()
			net.send(Proto.JOIN, {"code": code})
			if args.has("ready"):
				net.send(Proto.READY, {"ready": true}))


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if backdrop and backdrop.visible:
		var cam: Camera3D = backdrop.get_node("Cam")
		var a := Time.get_ticks_msec() / 1000.0 * 0.03
		cam.position = Vector3(cos(a) * 380.0, 120.0, sin(a) * 380.0)
		cam.look_at(Vector3(0, 10, 0), Vector3.UP)
	if ui and ui.name == "List":
		_list_t -= delta
		if _list_t <= 0.0:
			_list_t = 3.0
			net.send(Proto.LIST)
	if _training_end_t > 0.0:
		_training_end_t -= delta
		if _training_end_t <= 0.0:
			_training_end_t = -1.0
			_leave_match_view()
			show_menu()


func show_toast(t: String) -> void:
	toast.text = t
	toast.size.x = 1200
	toast.position.x = (get_viewport().get_visible_rect().size.x - 1200) / 2
	_toast_t = 4.0
	toast.modulate.a = 1.0


# ---------- Фон меню ----------

func _build_backdrop() -> void:
	backdrop = Node3D.new()
	add_child(backdrop)
	var t := Terrain.new()
	t.generate(20251111)
	WorldBuilder.build(t, backdrop, mini(Settings.quality, 1))
	for i in 8:
		var col: Color = SimConst.PLAYER_COLORS[i]
		var s := ShelterBuilder.build(i % 4, col, "", i)
		s.position = t.shelters[i]
		s.get_node("Label").visible = false
		backdrop.add_child(s)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 60
	cam.far = 4000
	backdrop.add_child(cam)
	cam.current = true


func _show_backdrop(on: bool) -> void:
	backdrop.visible = on
	backdrop.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		(backdrop.get_node("Cam") as Camera3D).current = true


# ---------- Каркас экранов ----------

func _screen(name: String, width := 560) -> VBoxContainer:
	if ui:
		ui.queue_free()
	_lobby = {}
	var root := Control.new()
	root.name = name
	root.theme = UiTheme.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.04, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	ui_layer.add_child(root)
	ui = root
	return box


func _title(box: VBoxContainer, text: String, sub := "") -> void:
	box.add_child(UiTheme.label(text, 34, UiTheme.ACCENT))
	if sub != "":
		var l := UiTheme.label(sub, 17, UiTheme.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)


func _row(box: Container, label: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := UiTheme.label(label, 19)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	box.add_child(h)


func _options(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, 0, items.size() - 1))
	return o


# ---------- Позывной ----------

func show_name(first: bool) -> void:
	_show_backdrop(true)
	var box := _screen("Name", 520)
	_title(box, "Позывной" if first else "Сменить позывной",
		"Так вас будут видеть в лобби, над укрытием и в ленте событий. 2–16 символов: буквы, цифры, пробел, дефис.")
	var edit := LineEdit.new()
	edit.text = Settings.player_name
	edit.placeholder_text = "Например, Сокол"
	edit.max_length = 16
	edit.custom_minimum_size.y = 48
	edit.add_theme_font_size_override("font_size", 24)
	box.add_child(edit)
	var hint := UiTheme.label("", 16, UiTheme.WARN)
	box.add_child(hint)
	var ok := UiTheme.button("Продолжить", func(): _save_name(edit.text, hint))
	box.add_child(ok)
	edit.text_submitted.connect(func(t): _save_name(t, hint))
	if not first:
		box.add_child(UiTheme.button("Назад", show_menu))
	edit.call_deferred("grab_focus")


func _save_name(raw: String, hint: Label) -> void:
	var n := Settings.clean_name(raw)
	if n.length() < 2:
		hint.text = "Нужно хотя бы 2 допустимых символа"
		return
	Settings.player_name = n
	Settings.save()
	if net.state == "online":
		net.send(Proto.RENAME, {"name": n})
	show_menu()


# ---------- Главное меню ----------

func show_menu() -> void:
	_show_backdrop(true)
	var box := _screen("Menu", 460)
	var t := UiTheme.label("ОПЕРАТОР", 56, UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := UiTheme.label("Удержи укрытие. Последний на связи — победил.", 17, UiTheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var who := HBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_child(UiTheme.label("Позывной: %s" % Settings.player_name, 19))
	var ch := Button.new()
	ch.text = "Изменить"
	ch.pressed.connect(func(): show_name(false))
	who.add_child(ch)
	box.add_child(who)
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.button("Создать лобби", func(): _online(show_create)))
	box.add_child(UiTheme.button("Список лобби", func(): _online(show_list)))
	box.add_child(UiTheme.button("Войти по коду", func(): _online(show_code)))
	box.add_child(UiTheme.button("Тренировка с ботами", show_training))
	box.add_child(UiTheme.button("Настройки", show_settings))
	box.add_child(UiTheme.button("Выход", func(): get_tree().quit()))
	var ver := UiTheme.label("v%s · сервер %s" % [NetConfig.GAME_VERSION, NetConfig.host()], 14, UiTheme.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ver)


func _online(next: Callable) -> void:
	if net.state == "online":
		next.call()
		return
	_after_online = next
	var box := _screen("Connecting", 460)
	_title(box, "Подключение…", "Сервер %s:%d" % [NetConfig.host(), NetConfig.port()])
	box.add_child(UiTheme.button("Отмена", func():
		net.disconnect_server()
		show_menu()))
	net.connect_server(Settings.player_name)


func _on_online(_id: int) -> void:
	if _after_online.is_valid():
		var cb := _after_online
		_after_online = Callable()
		cb.call()


func _on_offline(reason: String) -> void:
	_after_online = Callable()
	show_toast(reason)
	if match_view and feed is FeedNet:
		_leave_match_view()
	if ui == null or ui.name != "Menu":
		show_menu()


# ---------- Создание лобби ----------

func show_create() -> void:
	var box := _screen("Create", 600)
	_title(box, "Новое лобби")
	var title := LineEdit.new()
	title.text = "Лобби %s" % Settings.player_name
	title.max_length = 32
	_row(box, "Название", title)
	var pub := _options(["Открытое — видно в списке", "Закрытое — только по коду"], 0)
	_row(box, "Доступ", pub)
	var slots := _options(range(2, 9), 6)
	_row(box, "Мест", slots)
	var lives := _options(range(1, 6), 2)
	_row(box, "Жизней у укрытия", lives)
	var bots := CheckButton.new()
	bots.text = "Заполнить пустые места ботами"
	bots.button_pressed = true
	box.add_child(bots)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.button("Создать", func():
		net.send(Proto.CREATE, {"title": title.text, "public": pub.selected == 0, "slots": slots.selected + 2,
			"lives": lives.selected + 1, "bots": bots.button_pressed}), 200))
	h.add_child(UiTheme.button("Назад", show_menu, 200))
	box.add_child(h)


# ---------- Список лобби ----------

func show_list() -> void:
	var box := _screen("List", 760)
	_title(box, "Открытые лобби", "Список обновляется сам каждые несколько секунд.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "Rows"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)
	_lobby.rows = list
	list.add_child(UiTheme.label("Загрузка…", 18, UiTheme.DIM))
	var h := HBoxContainer.new()
	h.add_child(UiTheme.button("Обновить", func(): net.send(Proto.LIST), 200))
	h.add_child(UiTheme.button("Создать своё", show_create, 200))
	h.add_child(UiTheme.button("Назад", show_menu, 200))
	box.add_child(h)
	_list_t = 0.0


func _on_rooms(list: Array) -> void:
	if ui == null or ui.name != "List" or not _lobby.has("rows"):
		return
	var rows: VBoxContainer = _lobby.rows
	for c in rows.get_children():
		c.queue_free()
	if list.is_empty():
		rows.add_child(UiTheme.label("Открытых лобби пока нет — создайте своё или войдите по коду.", 18, UiTheme.DIM))
		return
	for r in list:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var h := HBoxContainer.new()
		var t := UiTheme.label(str(r.get("title", "")), 20)
		t.custom_minimum_size.x = 260
		t.clip_text = true
		h.add_child(t)
		var host := UiTheme.label("хост: %s" % str(r.get("host", "")), 17, UiTheme.DIM)
		host.custom_minimum_size.x = 180
		host.clip_text = true
		h.add_child(host)
		h.add_child(UiTheme.label("%d/%d" % [int(r.get("players", 0)), int(r.get("slots", 0))], 18))
		var playing: bool = str(r.get("status", "")) == "match"
		var st := UiTheme.label("идёт матч" if playing else "ожидание", 17, UiTheme.WARN if playing else UiTheme.ACCENT)
		st.custom_minimum_size.x = 110
		h.add_child(st)
		var code := str(r.get("code", ""))
		var b := Button.new()
		b.text = "Войти"
		b.disabled = playing or int(r.get("players", 0)) >= int(r.get("slots", 0))
		b.pressed.connect(func(): net.send(Proto.JOIN, {"code": code}))
		h.add_child(b)
		rows.add_child(h)


# ---------- Вход по коду ----------

func show_code() -> void:
	var box := _screen("Code", 460)
	_title(box, "Войти по коду", "Шесть цифр — их показывает экран лобби у хоста.")
	var edit := LineEdit.new()
	edit.max_length = 6
	edit.placeholder_text = "000000"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size.y = 60
	edit.add_theme_font_size_override("font_size", 36)
	box.add_child(edit)
	var go := func(t: String):
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits.length() != 6:
			show_toast("Код — это 6 цифр")
			return
		net.send(Proto.JOIN, {"code": digits})
	edit.text_submitted.connect(go)
	box.add_child(UiTheme.button("Войти", func(): go.call(edit.text)))
	box.add_child(UiTheme.button("Назад", show_menu))
	edit.call_deferred("grab_focus")


# ---------- Экран лобби ----------

func _on_room_state(st: Dictionary) -> void:
	if st.is_empty():
		return
	if str(st.get("status", "")) == "lobby" and match_view != null and feed is FeedNet:
		_leave_match_view()
		_results_seen = false
	if match_view != null:
		return
	if ui == null or ui.name != "Lobby":
		show_lobby()
	_fill_lobby(st)


func show_lobby() -> void:
	_show_backdrop(true)
	var box := _screen("Lobby", 1180)
	var head := HBoxContainer.new()
	var title := UiTheme.label("", 30, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	var code := UiTheme.label("", 30, UiTheme.TEXT)
	head.add_child(code)
	var copy := Button.new()
	copy.text = "Копировать код"
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(str(net.room.get("code", "")))
		show_toast("Код скопирован"))
	head.add_child(copy)
	box.add_child(head)
	var info := UiTheme.label("", 17, UiTheme.DIM)
	box.add_child(info)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(640, 0)
	cols.add_child(left)
	left.add_child(UiTheme.label("Операторы", 20, UiTheme.DIM))
	var players := VBoxContainer.new()
	players.custom_minimum_size.y = 330
	left.add_child(players)
	var results := RichTextLabel.new()
	results.bbcode_enabled = true
	results.fit_content = true
	results.custom_minimum_size = Vector2(620, 0)
	left.add_child(results)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiTheme.label("Чат", 20, UiTheme.DIM))
	var chat := RichTextLabel.new()
	chat.bbcode_enabled = true
	chat.scroll_following = true
	chat.custom_minimum_size = Vector2(440, 300)
	chat.add_theme_font_size_override("normal_font_size", 17)
	var chat_bg := PanelContainer.new()
	chat_bg.add_child(chat)
	right.add_child(chat_bg)
	var say := LineEdit.new()
	say.placeholder_text = "Сообщение и Enter"
	say.max_length = Proto.MAX_CHAT
	say.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			net.send(Proto.CHAT, {"text": t})
		say.clear())
	right.add_child(say)
	var host_box := VBoxContainer.new()
	right.add_child(host_box)

	box.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_child(UiTheme.label("Укрытие", 18))
	var style := _options(SimConst.SHELTER_STYLES, Settings.last_style)
	bottom.add_child(style)
	bottom.add_child(UiTheme.label("Дрон", 18))
	var kind := _options(SimConst.KIND_NAMES, Settings.last_kind)
	bottom.add_child(kind)
	var send_loadout := func(_i = 0):
		Settings.last_style = style.selected
		Settings.last_kind = kind.selected
		Settings.save()
		net.send(Proto.LOADOUT, {"style": style.selected, "kind": kind.selected})
	style.item_selected.connect(send_loadout)
	kind.item_selected.connect(send_loadout)
	var ready := Button.new()
	ready.toggle_mode = true
	ready.text = "Готов"
	ready.custom_minimum_size = Vector2(160, 46)
	ready.toggled.connect(func(on): net.send(Proto.READY, {"ready": on}))
	bottom.add_child(ready)
	var start := UiTheme.button("Начать матч", func(): net.send(Proto.START), 200)
	bottom.add_child(start)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	bottom.add_child(UiTheme.button("Выйти из лобби", func():
		net.send(Proto.LEAVE)
		net.room = {}
		show_menu(), 220))
	box.add_child(bottom)
	_lobby = {"title": title, "code": code, "info": info, "players": players, "results": results, "chat": chat,
		"host_box": host_box, "ready": ready, "start": start, "style": style, "kind": kind}
	send_loadout.call()


func _fill_lobby(st: Dictionary) -> void:
	if not _lobby.has("players"):
		return
	var me := net.my_id
	var am_host := int(st.get("host", 0)) == me
	_lobby.title.text = str(st.get("title", ""))
	_lobby.code.text = "Код %s" % str(st.get("code", ""))
	_lobby.info.text = "%s · мест %d · жизней %d · боты %s" % ["открытое" if st.get("public", true) else "закрытое",
		int(st.get("slots", 8)), int(st.get("lives", 3)), "в пустых слотах" if st.get("bots", true) else "выключены"]
	var plist: VBoxContainer = _lobby.players
	for c in plist.get_children():
		c.queue_free()
	var all_ready := true
	for p in st.get("players", []):
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = SimConst.PLAYER_COLORS[int(p.color) % 8]
		sw.custom_minimum_size = Vector2(14, 30)
		h.add_child(sw)
		var is_host := int(p.pid) == int(st.get("host", 0))
		var nm := UiTheme.label(("★ " if is_host else "") + str(p.name) + (" (вы)" if int(p.pid) == me else ""), 20)
		nm.custom_minimum_size.x = 250
		nm.clip_text = true
		h.add_child(nm)
		h.add_child(UiTheme.label("%s · %s" % [SimConst.SHELTER_STYLES[int(p.style) % 4], SimConst.KIND_NAMES[int(p.kind) % 2]], 17, UiTheme.DIM))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		var rd := "хост" if is_host else ("готов" if p.ready else "не готов")
		h.add_child(UiTheme.label(rd, 17, UiTheme.ACCENT if (p.ready or is_host) else UiTheme.DIM))
		if not is_host and not p.ready:
			all_ready = false
		if am_host and int(p.pid) != me:
			var pid := int(p.pid)
			var k := Button.new()
			k.text = "Исключить"
			k.pressed.connect(func(): net.send(Proto.KICK, {"pid": pid}))
			h.add_child(k)
		plist.add_child(h)
	var free: int = int(st.get("slots", 8)) - st.get("players", []).size()
	if free > 0:
		plist.add_child(UiTheme.label("Свободно мест: %d%s" % [free, " — займут боты" if st.get("bots", true) else ""], 17, UiTheme.DIM))
	_lobby.ready.visible = not am_host
	_lobby.start.visible = am_host
	_lobby.start.disabled = not all_ready
	_lobby.start.tooltip_text = "" if all_ready else "Ждём, пока все нажмут «Готов»"
	# Итоги прошлого матча.
	var res: Array = st.get("results", [])
	var rt: RichTextLabel = _lobby.results
	rt.clear()
	if not res.is_empty():
		var text := "[color=#e8a33d]Итоги матча[/color]\n"
		for r in res:
			text += "%d. %s — попаданий %d, таранов %d\n" % [int(r.place), str(r.name), int(r.hits), int(r.rams)]
		rt.append_text(text)
	# Чат (полная история при первом заходе).
	if not _lobby.has("chat_loaded"):
		_lobby.chat_loaded = true
		for m in st.get("chat", []):
			_on_chat(m)
	# Настройки лобби для хоста.
	var hb: VBoxContainer = _lobby.host_box
	if am_host and hb.get_child_count() == 0:
		hb.add_child(UiTheme.label("Настройки (хост)", 18, UiTheme.DIM))
		var lives := _options(range(1, 6), int(st.get("lives", 3)) - 1)
		var slots := _options(range(2, 9), int(st.get("slots", 8)) - 2)
		var bots := CheckButton.new()
		bots.text = "Боты в пустых слотах"
		bots.button_pressed = bool(st.get("bots", true))
		var pub := CheckButton.new()
		pub.text = "Открытое лобби"
		pub.button_pressed = bool(st.get("public", true))
		var apply := func(_x = 0):
			net.send(Proto.SETTINGS, {"lives": lives.selected + 1, "slots": slots.selected + 2, "bots": bots.button_pressed, "public": pub.button_pressed})
		lives.item_selected.connect(apply)
		slots.item_selected.connect(apply)
		bots.toggled.connect(apply)
		pub.toggled.connect(apply)
		var h1 := HBoxContainer.new()
		h1.add_child(UiTheme.label("Жизни", 17))
		h1.add_child(lives)
		h1.add_child(UiTheme.label("Мест", 17))
		h1.add_child(slots)
		hb.add_child(h1)
		hb.add_child(bots)
		hb.add_child(pub)
	elif not am_host:
		for c in hb.get_children():
			c.queue_free()


func _on_chat(m: Dictionary) -> void:
	if not _lobby.has("chat") or not is_instance_valid(_lobby.chat):
		return
	var rt: RichTextLabel = _lobby.chat
	var text := Proto.clean_text(m.get("text", ""), Proto.MAX_CHAT).replace("[", "(")
	if int(m.get("from", 0)) == 0:
		rt.append_text("[color=#8a8d86][i]%s[/i][/color]\n" % text)
	else:
		var col: Color = SimConst.PLAYER_COLORS[int(m.get("color", 0)) % 8]
		rt.append_text("[color=#%s]%s:[/color] %s\n" % [col.to_html(false), str(m.get("name", "")).replace("[", "("), text])


# ---------- Матч ----------

func _on_match_started(_info: Dictionary) -> void:
	var f = net.feed
	_leave_match_view()
	net.feed = f
	feed = f
	_start_view()


func _start_view() -> void:
	if ui:
		ui.queue_free()
		ui = null
	_lobby = {}
	_show_backdrop(false)
	match_view = MatchView.new()
	match_view.setup(feed, Settings.quality)
	if OS.get_cmdline_user_args().has("--autopilot") and feed is FeedNet:
		match_view.autopilot = BotAI.new(net.my_id, 0.9, 7)
	match_view.leave_requested.connect(_on_leave_match)
	match_view.match_over.connect(func(_w):
		if feed is FeedLocal:
			_training_end_t = 6.0)
	add_child(match_view)


func _on_leave_match() -> void:
	var was_net: bool = feed is FeedNet
	_leave_match_view()
	if was_net:
		net.send(Proto.LEAVE)
		net.room = {}
	show_menu()


func _leave_match_view() -> void:
	if match_view:
		match_view.queue_free()
		match_view = null
	feed = null
	net.feed = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_training_end_t = -1.0


# ---------- Тренировка ----------

func show_training() -> void:
	var box := _screen("Training", 520)
	_title(box, "Тренировка", "Матч с ботами прямо на вашем компьютере — без сервера и интернета.")
	var bots := _options(range(1, 8), 4)
	_row(box, "Ботов", bots)
	var lives := _options(range(1, 6), 2)
	_row(box, "Жизней", lives)
	var kind := _options(SimConst.KIND_NAMES, Settings.last_kind)
	_row(box, "Первый дрон", kind)
	var style := _options(SimConst.SHELTER_STYLES, Settings.last_style)
	_row(box, "Укрытие", style)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.button("Начать", func():
		Settings.last_kind = kind.selected
		Settings.last_style = style.selected
		Settings.save()
		start_training(bots.selected + 1, lives.selected + 1), 220))
	h.add_child(UiTheme.button("Назад", show_menu, 220))
	box.add_child(h)


func start_training(bots: int, lives := 3) -> void:
	var name := Settings.player_name if Settings.player_name != "" else "Оператор"
	var roster := [{"pid": 1, "name": name, "color": 0, "style": Settings.last_style, "kind": Settings.last_kind}]
	var names := Room.BOT_NAMES
	for i in bots:
		roster.append({"pid": i + 2, "name": names[i % names.size()], "color": i + 1, "style": (i + 1) % 4, "kind": i % 2, "bot": true})
	_leave_match_view()
	var f := FeedLocal.new()
	var args := OS.get_cmdline_user_args()
	f.start(1 if args.has("--seed1") else randi() % 1000000, roster, lives, 1)
	if args.has("--autopilot"):
		f.autopilot = BotAI.new(1, 0.9, 77)
	feed = f
	_start_view()


# ---------- Настройки ----------

func show_settings() -> void:
	var box := _screen("Settings", 680)
	_title(box, "Настройки")
	var q := _options(["Низкое", "Среднее", "Высокое"], Settings.quality)
	_row(box, "Качество графики", q)
	var fs := CheckButton.new()
	fs.text = "Полный экран"
	fs.button_pressed = Settings.fullscreen
	box.add_child(fs)
	var vs := CheckButton.new()
	vs.text = "Вертикальная синхронизация"
	vs.button_pressed = Settings.vsync
	box.add_child(vs)
	var fps := CheckButton.new()
	fps.text = "Показывать кадры в секунду"
	fps.button_pressed = Settings.show_fps
	box.add_child(fps)
	var fov := _slider(80, 120, Settings.fov, 1)
	_row(box, "Угол обзора FPV", fov)
	var tilt := _slider(0, 40, Settings.camera_tilt, 1)
	_row(box, "Наклон камеры коптера", tilt)
	var sens := _slider(0.2, 3.0, Settings.mouse_sens, 0.05)
	_row(box, "Чувствительность мыши", sens)
	var inv := CheckButton.new()
	inv.text = "Инвертировать мышь по вертикали"
	inv.button_pressed = Settings.invert_y
	box.add_child(inv)
	var acro := CheckButton.new()
	acro.text = "Режим «акро» (без автовыравнивания)"
	acro.button_pressed = Settings.acro
	box.add_child(acro)
	var vol := _slider(0, 1, Settings.volume, 0.05)
	_row(box, "Громкость", vol)
	var host := LineEdit.new()
	host.text = Settings.server_host
	host.placeholder_text = "по умолчанию: %s" % NetConfig.DEFAULT_HOST
	_row(box, "Адрес сервера", host)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.button("Сохранить", func():
		Settings.quality = q.selected
		Settings.fullscreen = fs.button_pressed
		Settings.vsync = vs.button_pressed
		Settings.show_fps = fps.button_pressed
		Settings.fov = fov.value
		Settings.camera_tilt = tilt.value
		Settings.mouse_sens = sens.value
		Settings.invert_y = inv.button_pressed
		Settings.acro = acro.button_pressed
		Settings.volume = vol.value
		var hs := host.text.strip_edges()
		if hs.contains(":"):
			Settings.server_host = hs.split(":")[0]
			Settings.server_port = int(hs.split(":")[1])
		else:
			Settings.server_host = hs
			Settings.server_port = 0
		Settings.save()
		Settings.apply()
		show_menu(), 220))
	h.add_child(UiTheme.button("Назад", show_menu, 220))
	box.add_child(h)
	var help := UiTheme.label("Управление: W/S — газ, A/D — поворот, мышь или стрелки — наклон, Q/E — крен, Shift — форсаж, Пробел — подрыв, F — сеть, 1/2 — тип дрона, C — аркада/акро, Tab — таблица, Esc — меню. Геймпад: левый стик — газ и поворот, правый — наклон, RT — форсаж, A — подрыв, X — сеть, LB/RB — тип дрона.", 15, UiTheme.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)


func _slider(mn: float, mx: float, v: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(240, 30)
	return s
