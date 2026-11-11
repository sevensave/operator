class_name MatchView
extends Node3D
## Вид матча: мир, укрытия, дроны, FPV-камера, OSD, звук, наблюдение.
## Получает состояние из feed (FeedLocal или FeedNet).

signal leave_requested
signal match_over(winner: int)

const FPV_SHADER := preload("res://shaders/fpv_feed.gdshader")

var feed
var quality := 1
var controls := Controls.new()
var cam: Camera3D
var osd: Osd
var post: ColorRect
var post_mat: ShaderMaterial
var drone_views := {}       # id -> DroneView
var shelter_nodes := {}     # pid -> Node3D
var jam_domes := {}         # pid -> MeshInstance3D
var spectate_pid := 0
var hit_flash := 0.0
var shake := 0.0
var menu_open := false
var pause_menu: Control
var _own_motor: AudioStreamPlayer
var _own_wind: AudioStreamPlayer
var _own_static: AudioStreamPlayer
var _chase_pos := Vector3.ZERO
var _orbit := 0.0
var _ended := false
var _last_input := DroneInput.new()
var _was_flying := false
var autopilot: BotAI          # отладка: дроном управляет бот (флаг --autopilot)
var _autopilot_rw: RemoteWorld
var _precip: GPUParticles3D      # дождь/снег вокруг камеры (косметика пресета)
var _chase_mode := OS.get_cmdline_user_args().has("--chase")   # кадры для арта: вид сзади


func setup(p_feed, p_quality: int) -> void:
	feed = p_feed
	quality = p_quality
	feed.game_event.connect(_on_event)


func _ready() -> void:
	var world_root := Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	WorldBuilder.build(feed.terrain, world_root, quality)
	_precip = WorldBuilder.precipitation(feed.terrain.preset, quality)
	if _precip != null:
		add_child(_precip)
	for p in feed.players.values():
		var pos: Vector3 = feed.terrain.shelters[p.shelter]
		var col: Color = SimConst.PLAYER_COLORS[p.color % SimConst.PLAYER_COLORS.size()]
		var node := ShelterBuilder.build(p.style, col, p.name, p.pid * 31 + feed.terrain.seed)
		node.position = pos
		node.rotation.y = atan2(pos.x, pos.z)
		add_child(node)
		shelter_nodes[p.pid] = node
		if p.pid == feed.my_pid:
			node.get_node("Label").visible = false
		if p.pid != feed.my_pid:
			var dome := Fx.dome(SimConst.JAMMER_RADIUS, col.lerp(Color(0.6, 0.9, 1.0), 0.5), 0.05, 40.0)
			dome.position = pos
			add_child(dome)
			jam_domes[p.pid] = dome

	cam = Camera3D.new()
	cam.fov = Settings.fov
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)
	cam.current = true

	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = FPV_SHADER
	post.material = post_mat
	post_layer.add_child(post)

	var hud := CanvasLayer.new()
	hud.layer = 1
	add_child(hud)
	osd = Osd.new()
	osd.theme = UiTheme.theme()
	hud.add_child(osd)
	osd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu = _build_pause_menu()
	hud.add_child(pause_menu)
	pause_menu.visible = false

	_own_motor = _player(SoundBank.motor_loop(0), -6.0)
	_own_wind = _player(SoundBank.noise_loop("wind"), -14.0)
	_own_static = _player(SoundBank.noise_loop("static"), -40.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_cmdline_user_args().has("--cinematic"):   # кадры для арта: без OSD
		osd.visible = false
	osd.push_line("Карта: %s" % map_title(), UiTheme.ACCENT)
	osd.push_line("W/S — газ, A/D — поворот, мышь или стрелки — наклон", UiTheme.DIM)
	osd.push_line("Shift — форсаж, Пробел — подрыв, F — сеть, Tab — таблица", UiTheme.DIM)


## «Каньон · закат · сильный ветер» — архетип и всё, что заметно игроку.
func map_title() -> String:
	var p: MapPreset = feed.terrain.preset
	return "%s · %s" % [p.title(), MapPreset.WIND_NAMES[p.wind_level]]


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		controls.on_mouse_motion(event.relative, Settings.mouse_sens, Settings.invert_y)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_toggle_menu()
			KEY_F:
				feed.trap()
			KEY_SPACE:
				if _my_drone_alive():
					feed.detonate()
				else:
					_next_spectate()
			KEY_1:
				_set_kind(SimConst.Kind.COPTER)
			KEY_2:
				_set_kind(SimConst.Kind.PLANE)
			KEY_TAB:
				osd.show_table = true
			KEY_C:
				Settings.acro = not Settings.acro
				osd.push_line("Режим: %s" % ("акро" if Settings.acro else "аркада"), UiTheme.ACCENT)
	if event is InputEventKey and not event.pressed and event.keycode == KEY_TAB:
		osd.show_table = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if menu_open:
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not _my_drone_alive():
			_next_spectate()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				if _my_drone_alive():
					feed.detonate()
				else:
					_next_spectate()
			JOY_BUTTON_X:
				feed.trap()
			JOY_BUTTON_LEFT_SHOULDER:
				_set_kind(SimConst.Kind.COPTER)
			JOY_BUTTON_RIGHT_SHOULDER:
				_set_kind(SimConst.Kind.PLANE)
			JOY_BUTTON_START:
				_toggle_menu()
			JOY_BUTTON_BACK:
				osd.show_table = not osd.show_table


func _set_kind(k: int) -> void:
	feed.set_kind(k)
	Settings.last_kind = k
	osd.push_line("Следующий дрон: %s" % SimConst.KIND_NAMES[k], UiTheme.ACCENT)


func _my_drone_alive() -> bool:
	var me = feed.players.get(feed.my_pid)
	return me != null and me.drone_id != 0


func _process(delta: float) -> void:
	var inp := controls.sample(delta, Settings.acro)
	if menu_open:
		inp = DroneInput.new()
		inp.seq = controls.seq
		inp.acro = Settings.acro
	if autopilot != null:
		if feed is FeedNet:
			if _autopilot_rw == null:
				_autopilot_rw = RemoteWorld.new()
				_autopilot_rw.client = feed.client
			_autopilot_rw.sync_from(feed)
			inp = autopilot.think(_autopilot_rw)
	_last_input = inp
	feed.update(delta, inp)
	var drones: Dictionary = feed.render_drones()
	_sync_drones(drones, delta)
	var me = feed.players.get(feed.my_pid)
	var mine: DroneState = null
	if me != null and me.drone_id != 0:
		mine = drones.get(me.drone_id)
	hit_flash = maxf(0.0, hit_flash - delta * 2.5)
	shake = maxf(0.0, shake - delta * 2.0)
	if mine != null and _chase_mode:
		_chase_camera(mine, delta)
	elif mine != null:
		_fpv_camera(mine, delta)
		if not _was_flying:
			spectate_pid = 0
	else:
		_spectate_camera(drones, me, delta)
	_was_flying = mine != null
	if _precip != null:
		_precip.global_position = cam.global_position + cam.global_transform.basis.z * -12.0 + Vector3(0, 22, 0)
	_update_post(mine)
	_update_audio(mine)
	_update_osd(mine, me, drones)
	for pid in jam_domes:
		var p = feed.players.get(pid)
		jam_domes[pid].visible = p != null and not p.eliminated and not feed.sudden_death()
	if feed.finished() and not _ended:
		_ended = true
		match_over.emit(feed.winner())


func _sync_drones(drones: Dictionary, delta: float) -> void:
	var me = feed.players.get(feed.my_pid)
	var my_id: int = me.drone_id if me != null else 0
	for id in drone_views.keys():
		if not drones.has(id):
			drone_views[id].queue_free()
			drone_views.erase(id)
	for id in drones:
		var d: DroneState = drones[id]
		var v: DroneView = drone_views.get(id)
		if v == null:
			v = DroneView.new()
			var p = feed.players.get(d.owner)
			var col: Color = SimConst.PLAYER_COLORS[(p.color if p else 0) % SimConst.PLAYER_COLORS.size()]
			v.setup(d.kind, col, id != my_id)
			add_child(v)
			drone_views[id] = v
		v.global_position = d.pos
		v.quaternion = d.rot
		v.visible = id != my_id or _chase_mode
		v.update_visual(d.thrust_frac, delta)


func _fpv_camera(d: DroneState, delta: float) -> void:
	var tilt := deg_to_rad(Settings.camera_tilt) if d.kind == SimConst.Kind.COPTER else deg_to_rad(4.0)
	var basis := Basis(d.rot) * Basis(Vector3.RIGHT, tilt)
	var offset := Basis(d.rot) * Vector3(0, 0.12, -0.25)
	var jitter := Vector3.ZERO
	if shake > 0.0 or d.signal_q < 0.3:
		var amp := shake * 0.15 + maxf(0.0, 0.3 - d.signal_q) * 0.03
		jitter = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0)
	cam.global_transform = Transform3D(basis, d.pos + offset + jitter)
	cam.fov = lerpf(cam.fov, Settings.fov + (6.0 if _last_input.boost else 0.0), delta * 4.0)
	_chase_pos = cam.global_position


func _chase_camera(d: DroneState, delta: float) -> void:
	cam.fov = 70.0
	var back := -d.vel.normalized() if d.vel.length() > 2.0 else -d.forward()
	var want := d.pos + back * 7.0 + Vector3(0, 2.2, 0)
	want.y = maxf(want.y, feed.terrain.height_at(want.x, want.z) + 1.5)
	_chase_pos = want if _chase_pos == Vector3.ZERO else _chase_pos.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
	cam.global_position = _chase_pos
	cam.look_at(d.pos + d.vel * 0.6 + Vector3(0, 0.5, 0), Vector3.UP)


func _next_spectate() -> void:
	var ids := []
	for p in feed.players.values():
		if p.drone_id != 0:
			ids.append(p.pid)
	if ids.is_empty():
		spectate_pid = 0
		return
	ids.sort()
	var i := ids.find(spectate_pid)
	spectate_pid = ids[(i + 1) % ids.size()]


func _spectate_camera(drones: Dictionary, me, delta: float) -> void:
	cam.fov = lerpf(cam.fov, 75.0, delta * 3.0)
	# Пока ждём перезапуска и живы — смотрим со своего укрытия, иначе следим за чужими дронами.
	var waiting: bool = me != null and not me.eliminated and not feed.finished()
	var target: DroneState = null
	if not waiting:
		if spectate_pid != 0:
			var sp = feed.players.get(spectate_pid)
			if sp != null and sp.drone_id != 0:
				target = drones.get(sp.drone_id)
		if target == null:
			_next_spectate()
			if spectate_pid != 0:
				var sp2 = feed.players.get(spectate_pid)
				if sp2 != null and sp2.drone_id != 0:
					target = drones.get(sp2.drone_id)
	var want_pos: Vector3
	var look: Vector3
	if target != null:
		var back := -target.vel.normalized() if target.vel.length() > 2.0 else -target.forward()
		back.y = 0.0
		back = back.normalized() if back.length() > 0.1 else Vector3.BACK
		want_pos = target.pos + back * 9.0 + Vector3(0, 3.5, 0)
		look = target.pos + target.vel * 0.3
	elif me != null and not me.eliminated:
		var s: Vector3 = feed.terrain.shelters[me.shelter]
		var to_c := Vector3(-s.x, 0, -s.z).normalized()
		want_pos = s - to_c * 12.0 + to_c.cross(Vector3.UP) * 7.0 + Vector3(0, 9.0, 0)
		look = s + to_c * 120.0 + Vector3(0, 10, 0)
	else:
		_orbit += delta * 0.05
		want_pos = Vector3(cos(_orbit) * 520.0, 220.0, sin(_orbit) * 520.0)
		look = Vector3(0, 20, 0)
	var g: float = feed.terrain.height_at(want_pos.x, want_pos.z) + 2.0
	want_pos.y = maxf(want_pos.y, g)
	_chase_pos = _chase_pos.lerp(want_pos, clampf(delta * 4.0, 0.0, 1.0)) if _chase_pos != Vector3.ZERO else want_pos
	cam.global_position = _chase_pos
	if _chase_pos.distance_to(look) > 0.5:
		cam.look_at(look, Vector3.UP)


func _update_post(d: DroneState) -> void:
	if d != null:
		var nl := clampf(d.nolink / SimConst.NOLINK_FALL, 0.0, 1.0)
		if not d.control and d.trapped <= 0.0:
			nl = 1.0
		post_mat.set_shader_parameter("signal_q", d.signal_q)
		post_mat.set_shader_parameter("nolink", nl * 0.85)
		post_mat.set_shader_parameter("jam", clampf(0.15 + (1.0 - d.signal_q) * 0.9, 0.0, 1.0) if d.jammed else 0.0)
		post_mat.set_shader_parameter("spectate", 0.0)
		post_mat.set_shader_parameter("lens", 0.14)
	else:
		post_mat.set_shader_parameter("signal_q", 1.0)
		post_mat.set_shader_parameter("nolink", 0.0)
		post_mat.set_shader_parameter("jam", 0.0)
		post_mat.set_shader_parameter("spectate", 1.0)
		post_mat.set_shader_parameter("lens", 0.02)
	post_mat.set_shader_parameter("hit_flash", hit_flash)


func _update_audio(d: DroneState) -> void:
	if d != null:
		_own_motor.stream_paused = false
		if _own_motor.stream != SoundBank.motor_loop(d.kind):
			_own_motor.stream = SoundBank.motor_loop(d.kind)
			_own_motor.play()
		var on := d.control and d.battery > 0.0
		_own_motor.pitch_scale = clampf(0.75 + d.thrust_frac * 0.55, 0.4, 2.0) if on else 0.5
		_own_motor.volume_db = -8.0 if on else -30.0
		var spd := d.vel.length()
		_own_wind.volume_db = linear_to_db(clampf(spd / 45.0, 0.02, 1.0)) - 8.0
		_own_wind.pitch_scale = 0.7 + spd / 60.0
		var noise := clampf(1.0 - d.signal_q * 1.4, 0.0, 1.0)
		if d.jammed:
			noise = maxf(noise, 0.35)
		_own_static.volume_db = linear_to_db(maxf(noise, 0.001)) - 10.0
	else:
		_own_motor.stream_paused = true
		_own_wind.volume_db = -26.0
		_own_wind.pitch_scale = 0.6
		_own_static.volume_db = -60.0


func _update_osd(d: DroneState, me, drones: Dictionary) -> void:
	var data := {}
	data.time = feed.match_time()
	data.sudden = feed.sudden_death()
	if feed.ping_ms > 0.0:
		data.ping = feed.ping_ms
	if Settings.show_fps:
		data.fps = Engine.get_frames_per_second()
	var rows := []
	for p in feed.players.values():
		rows.append({"name": p.name, "color": SimConst.PLAYER_COLORS[p.color % 8], "lives": maxi(p.lives, 0),
			"out": p.eliminated, "me": p.pid == feed.my_pid, "hits": p.hits, "rams": p.rams, "bot": p.bot, "place": p.place})
	rows.sort_custom(func(a, b): return (a.lives if not a.out else -a.place) > (b.lives if not b.out else -b.place))
	data.players = rows
	if me != null:
		data.stock = me.stock
		data.regen = SimConst.STOCK_REGEN - me.regen_t
		data.trap_cd = me.trap_cd
		data.next_kind = SimConst.KIND_NAMES[me.kind]
	data.flying = d != null
	if d != null:
		var f := cam.global_transform.basis * Vector3.FORWARD
		data.heading = posmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
		data.signal = d.signal_q
		data.battery = d.battery
		data.speed = d.vel.length()
		data.agl = feed.terrain.agl(d.pos)
		data.kind_name = SimConst.KIND_NAMES[d.kind]
		data.acro = _last_input.acro
		var w := Wind.mean(feed.match_time(), feed.terrain.preset)
		var cb := cam.global_transform.basis
		var cr := cb.x
		cr.y = 0
		var cf := -cb.z
		cf.y = 0
		data.wind = Vector2(w.dot(cr.normalized()), w.dot(cf.normalized()))
		# Горизонт.
		var flat := f
		flat.y = 0
		if flat.length() > 0.05:
			flat = flat.normalized()
			var side := flat.cross(Vector3.UP).normalized()
			var p0 := cam.global_position + flat * 1000.0
			var a := p0 - side * 100.0
			var b := p0 + side * 100.0
			a.y = cam.global_position.y
			b.y = cam.global_position.y
			if not cam.is_position_behind(a) and not cam.is_position_behind(b):
				data.horizon = [cam.unproject_position(a), cam.unproject_position(b)]
		# Отметки укрытий на компасе и на экране.
		var marks := []
		var smarks := []
		for p in feed.players.values():
			if p.eliminated:
				continue
			var sp: Vector3 = feed.terrain.shelters[p.shelter] + Vector3(0, 3, 0)
			var to := sp - d.pos
			var bearing := posmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
			var col: Color = SimConst.PLAYER_COLORS[p.color % 8]
			var home: bool = p.pid == feed.my_pid
			marks.append({"bearing": bearing, "color": col, "label": "БАЗА" if home else p.name, "dist": to.length(), "home": home})
			if not home and not cam.is_position_behind(sp) and to.length() < 900.0:
				var sc := cam.unproject_position(sp)
				if Rect2(Vector2.ZERO, osd.size).has_point(sc):
					smarks.append({"pos": sc, "color": col, "label": p.name, "dist": to.length()})
		data.marks = marks
		data.screen_marks = smarks
		var warns := []
		if d.trapped > 0.0:
			warns.append(["ДРОН В СЕТИ", true])
		if not d.control and d.trapped <= 0.0:
			warns.append(["НЕТ УПРАВЛЕНИЯ", true])
		elif d.signal_q < SignalModel.NOLINK:
			warns.append(["НЕТ СВЯЗИ %.1f с" % maxf(0.0, SimConst.NOLINK_FALL - d.nolink), true])
		elif d.signal_q < SignalModel.LAG_START:
			warns.append(["СЛАБЫЙ СИГНАЛ — ЗАДЕРЖКА", false])
		if d.jammed:
			warns.append(["ГЛУШИЛКА", false])
		if d.lock > 0.15:
			warns.append(["ТУРЕЛЬ: ЗАХВАТ %d%%" % int(d.lock * 100), d.lock > 0.5])
		if d.battery < 0.15:
			warns.append(["АКБ НА ИСХОДЕ", true])
		if d.kind == SimConst.Kind.PLANE and FlightPlane.stalled(d) and d.age > 2.0:
			warns.append(["СВАЛИВАНИЕ", true])
		data.warnings = warns
	# Крупная надпись.
	osd.big_text = ""
	osd.big_sub = ""
	if feed.finished():
		var w: int = feed.winner()
		if w == feed.my_pid:
			osd.big_text = "ПОБЕДА"
			osd.big_color = UiTheme.ACCENT
		elif w != 0 and feed.players.has(w):
			osd.big_text = "Победил %s" % feed.players[w].name
			osd.big_color = UiTheme.TEXT
		else:
			osd.big_text = "Ничья"
			osd.big_color = UiTheme.TEXT
		osd.big_sub = "Возвращаемся в лобби…"
	elif me != null and me.eliminated:
		osd.big_text = "Укрытие уничтожено"
		osd.big_color = UiTheme.WARN
		osd.big_sub = "Наблюдение · Пробел или клик — следующий дрон"
	elif d == null and me != null:
		if me.stock <= 0:
			osd.big_text = "Нет дронов"
			osd.big_sub = "Следующий будет через %d с" % int(ceil(SimConst.STOCK_REGEN - me.regen_t))
		else:
			osd.big_text = "Запуск через %.1f" % me.respawn_t
			osd.big_sub = "Следующий: %s  ·  1 — коптер, 2 — самолёт" % SimConst.KIND_NAMES[me.kind]
			if feed.match_time() < 4.0:
				osd.big_sub = "Карта: %s  ·  %s" % [map_title(), osd.big_sub]
		osd.big_color = UiTheme.TEXT
	osd.data = data


func _name(pid: int) -> String:
	var p = feed.players.get(pid)
	return p.name if p else "?"


func _color(pid: int) -> Color:
	var p = feed.players.get(pid)
	return SimConst.PLAYER_COLORS[p.color % 8] if p else UiTheme.TEXT


func _on_event(ev: Dictionary) -> void:
	match ev.t:
		"boom":
			var pos: Vector3 = ev.pos
			Fx.explosion(self, pos, ev.kind == SimConst.Kind.PLANE, quality)
			if ev.pid == feed.my_pid:
				hit_flash = 0.9
				shake = 0.6
				var why := {"ground": "Дрон разбился о землю", "tree": "Дрон задел дерево", "building": "Дрон врезался в постройку",
					"turret": "Дрон сбит турелью", "ram": "Таран: дрон потерян", "detonate": "Подрыв", "shelter": "Удар по укрытию",
					"bounds": "Дрон ушёл за край карты", "out": ""}
				var t: String = why.get(ev.cause, "Дрон потерян")
				if t != "":
					osd.push_line(t, UiTheme.DIM)
			elif ev.cause == "turret":
				osd.push_line("%s: дрон сбит турелью" % _name(ev.pid), UiTheme.DIM)
			else:
				var cd := cam.global_position.distance_to(pos)
				if cd < 60.0:
					shake = maxf(shake, (60.0 - cd) / 60.0 * 0.5)
		"hit":
			osd.push_line("%s → %s: −1 жизнь (осталось %d)" % [_name(ev.by), _name(ev.victim), maxi(ev.lives, 0)], _color(ev.by))
			if ev.victim == feed.my_pid:
				shake = 1.0
				hit_flash = maxf(hit_flash, 0.5)
				_beep(220.0, 0.25)
			elif ev.by == feed.my_pid:
				_beep(880.0, 0.12)
			var n: Node3D = shelter_nodes.get(ev.victim)
			if n:
				Fx.explosion(self, n.global_position + Vector3(0, 4, 0), true, quality)
		"out":
			osd.push_line("%s выбывает — %d место" % [_name(ev.pid), ev.place], UiTheme.WARN)
			var n2: Node3D = shelter_nodes.get(ev.pid)
			if n2:
				n2.get_node("Beacon").visible = false
				n2.get_node("BeaconLight").visible = false
		"ram":
			osd.push_line("Таран: %s и %s" % [_name(ev.a), _name(ev.b)], UiTheme.TEXT)
		"caught":
			osd.push_line("%s поймал сетью дрон %s" % [_name(ev.pid), _name(ev.victim)], _color(ev.pid))
		"trap":
			var dome := Fx.dome(SimConst.TRAP_RADIUS, _color(ev.pid).lerp(Color.WHITE, 0.3), 0.6, 18.0)
			add_child(dome)
			dome.global_position = ev.pos
			var tw := dome.create_tween()
			tw.tween_property(dome, "scale", Vector3.ONE, 0.25).from(Vector3.ONE * 0.2)
			tw.tween_interval(SimConst.TRAP_TIME - 0.5)
			tw.tween_property(dome, "scale", Vector3.ONE * 1.05, 0.25)
			tw.tween_callback(dome.queue_free)
			if ev.pid == feed.my_pid:
				_beep(660.0, 0.15)
		"sudden":
			osd.push_line("Внезапная смерть: глушилки, турели и сети отключены", UiTheme.WARN)
			_beep(330.0, 0.5)
		"nolink":
			if ev.pid == feed.my_pid:
				osd.push_line("Связь потеряна — дрон без управления", UiTheme.WARN)
		"spawn":
			if ev.pid == feed.my_pid:
				_beep(520.0, 0.08)


func _beep(f: float, d: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = SoundBank.beep(f, d)
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _toggle_menu() -> void:
	menu_open = not menu_open
	pause_menu.visible = menu_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED


func _build_pause_menu() -> Control:
	var root := ColorRect.new()
	root.theme = UiTheme.theme()
	root.color = Color(0, 0, 0, 0.55)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.position = Vector2(-160, -120)
	box.custom_minimum_size = Vector2(320, 240)
	root.add_child(box)
	box.add_child(UiTheme.label("Пауза оператора", 30, UiTheme.ACCENT))
	box.add_child(UiTheme.label("Матч продолжается — дрон висит без команд", 16, UiTheme.DIM))
	box.add_child(UiTheme.button("Вернуться", _toggle_menu))
	var acro := UiTheme.button("Режим: аркада / акро (C)", func():
		Settings.acro = not Settings.acro
		osd.push_line("Режим: %s" % ("акро" if Settings.acro else "аркада"), UiTheme.ACCENT))
	box.add_child(acro)
	box.add_child(UiTheme.button("Выйти из матча", func(): leave_requested.emit()))
	return root
