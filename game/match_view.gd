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
## Автозахват: дрон сам идёт на перехват чужого дрона, пока игрок не отменит.
const LOCK_CONE := deg_to_rad(35.0)   # кандидат — не дальше этого угла от оси взгляда
const LOCK_PICK_RANGE := 400.0
const LOCK_LOSE_RANGE := 600.0
const LOCK_GROW_TIME := 3.0           # дистанция растёт столько секунд подряд — цель потеряна
const LOCK_BREAK_STICK := 0.35        # ручка отклонена сильнее — ручное управление
var _lock_id := 0           # id дрона-цели, 0 — нет захвата
var _lock_cand := 0         # кандидат под прицелом (по прошлому кадру)
var _lock_armed := false    # ручки побывали в центре после захвата — теперь их движение отменяет
var _lock_dist := 0.0
var _lock_grow := 0.0
var _autolock := OS.get_cmdline_user_args().has("--autolock")   # отладка: захват ближайшего сам
var _chase_mode := OS.get_cmdline_user_args().has("--chase")   # кадры для арта: вид сзади
## Кадры для арта: при --chase/--cinematic убрать FPV-эффекты (линза, зерно, сканлайны).
var _clean := OS.get_cmdline_user_args().has("--clean") and (_chase_mode or OS.get_cmdline_user_args().has("--cinematic"))
## Кадры для проверки графики: --look=x,y,z,tx,ty,tz — неподвижная камера (точка и куда смотреть).
var _look := PackedFloat32Array()
## Камера «bodycam»: логический угол обзора (_fov) и линза — камера рендерит шире,
## фильтр возвращает центру масштаб _fov. Метки OSD проходят через ту же линзу (_proj).
var _fov := 100.0
var _lens_k := 0.0
var _lens_s := 1.0
var _prev_basis := Basis.IDENTITY
var _sun: DirectionalLight3D


func _look_arg() -> PackedFloat32Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			var v := PackedFloat32Array()
			for x in a.substr(7).split(","):
				v.append(x.to_float())
			if v.size() == 6:
				return v
	return PackedFloat32Array()


func setup(p_feed, p_quality: int) -> void:
	feed = p_feed
	quality = p_quality
	feed.game_event.connect(_on_event)


func _ready() -> void:
	var world_root := Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	WorldBuilder.build(feed.terrain, world_root, quality)
	_look = _look_arg()
	_sun = world_root.get_node_or_null("Sun") as DirectionalLight3D
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
	_fov = Settings.fov
	cam.near = 0.05
	cam.far = 4000.0
	cam.attributes = WorldBuilder.camera_attributes(feed.terrain.preset.daytime)
	add_child(cam)
	cam.current = true
	WorldBuilder.apply_viewport(get_viewport(), quality, Settings.render_scale)

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
	osd.push_line("Shift — форсаж, Пробел — подрыв (сбивает и дроны рядом), F — сеть, Tab — таблица", UiTheme.DIM)
	osd.push_line("R — автозахват чужого дрона под прицелом, повторно или ручками — отмена", UiTheme.DIM)


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
			KEY_R:
				_toggle_lock()
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
			JOY_BUTTON_Y:
				_toggle_lock()
			JOY_BUTTON_LEFT_SHOULDER:
				_set_kind(SimConst.Kind.COPTER)
			JOY_BUTTON_RIGHT_SHOULDER:
				_set_kind(SimConst.Kind.PLANE)
			JOY_BUTTON_START:
				_toggle_menu()
			JOY_BUTTON_BACK:
				osd.show_table = not osd.show_table


## R / геймпад Y: захватить чужой дрон под прицелом или снять захват.
func _toggle_lock() -> void:
	if _lock_id != 0:
		_drop_lock("Автозахват снят", UiTheme.DIM)
	elif _lock_cand != 0 and _my_drone_alive() and not menu_open:
		_start_lock(_lock_cand)
	else:
		osd.push_line("Нет цели для захвата", UiTheme.DIM)


func _start_lock(id: int) -> void:
	var tg := _lock_target(id)
	var own: DroneState = feed.predicted_drone()
	if tg == null or own == null:
		return
	_lock_id = id
	_lock_armed = false
	_lock_grow = 0.0
	_lock_dist = own.pos.distance_to(tg.pos)
	osd.push_line("Автозахват: дрон %s — [R] отмена" % _name(tg.owner), UiTheme.ACCENT)
	_beep(740.0, 0.08)


func _drop_lock(msg: String, col := UiTheme.WARN) -> void:
	if _lock_id == 0:
		return
	_lock_id = 0
	if msg != "":
		osd.push_line(msg, col)


## Цель захвата: свежее состояние (снапшот или мир), а не отстающая интерполяция.
## По сети снапшот старше своего предсказания примерно на пинг — досчитываем по скорости.
func _lock_target(id := -1) -> DroneState:
	var o: DroneState = feed.latest_drones().get(_lock_id if id < 0 else id)
	if o == null:
		return null
	if feed is FeedNet and feed.ping_ms > 0.0:
		o = o.clone()
		o.pos += o.vel * clampf(feed.ping_ms * 0.001, 0.0, 0.3)
	return o


## Срывы захвата: ручки, цель уничтожена или ушла, свой дрон без управления.
func _update_lock(raw: DroneInput, own: DroneState, delta: float) -> void:
	if _lock_id == 0:
		return
	if own == null:
		_drop_lock("")   # свой дрон потерян — причину уже показало событие взрыва
		return
	if own.trapped > 0.0:
		_drop_lock("Захват сорван: дрон в сети")
		return
	if not own.control:
		_drop_lock("Захват сорван: нет связи")
		return
	var tg := _lock_target()
	if tg == null:
		_drop_lock("Цель уничтожена", UiTheme.ACCENT)
		return
	var dev := maxf(maxf(absf(raw.pitch), absf(raw.roll)), maxf(absf(raw.yaw), absf(raw.throttle)))
	if dev < LOCK_BREAK_STICK:
		_lock_armed = true
	elif _lock_armed:
		_drop_lock("Автозахват снят: ручное управление", UiTheme.DIM)
		return
	var dist := own.pos.distance_to(tg.pos)
	_lock_grow = _lock_grow + delta if dist > _lock_dist else 0.0
	_lock_dist = dist
	if dist > LOCK_LOSE_RANGE or _lock_grow >= LOCK_GROW_TIME:
		_drop_lock("Цель потеряна")


## --autolock: захватить ближайший чужой дрон в радиусе без оглядки на прицел (для съёмки).
func _auto_pick(own: DroneState) -> void:
	var best := 0
	var best_d := LOCK_PICK_RANGE
	for o: DroneState in feed.latest_drones().values():
		if o.owner != feed.my_pid and own.pos.distance_to(o.pos) < best_d:
			best_d = own.pos.distance_to(o.pos)
			best = o.id
	if best != 0:
		_start_lock(best)


func _set_kind(k: int) -> void:
	feed.set_kind(k)
	Settings.last_kind = k
	osd.push_line("Следующий дрон: %s" % SimConst.KIND_NAMES[k], UiTheme.ACCENT)


func _my_drone_alive() -> bool:
	var me = feed.players.get(feed.my_pid)
	return me != null and me.drone_id != 0


func _process(delta: float) -> void:
	var raw := controls.sample(delta, Settings.acro)
	var inp := raw
	if menu_open:
		inp = DroneInput.new()
		inp.seq = controls.seq
		inp.acro = Settings.acro
	var own: DroneState = feed.predicted_drone() if _my_drone_alive() else null
	if _autolock and _lock_id == 0 and own != null and not menu_open:
		_auto_pick(own)
	_update_lock(raw, own, delta)
	if _lock_id != 0:
		inp = PilotAssist.pursue(own, _lock_target(), feed.terrain)
		inp.seq = controls.seq
		inp.acro = false
	elif own != null and Settings.alt_assist and not inp.acro and own.kind == SimConst.Kind.COPTER and absf(inp.throttle) < 0.1:
		inp.throttle = PilotAssist.alt_hold_throttle(own, inp.throttle, feed.terrain)
		inp.pitch = PilotAssist.alt_hold_pitch(own, inp.pitch, feed.terrain)
	if feed is FeedLocal:
		feed.manual_override = _lock_id != 0
	if autopilot != null and _lock_id == 0:
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
	if _look.size() == 6:
		_fov = 75.0
		cam.look_at_from_position(Vector3(_look[0], _look[1], _look[2]), Vector3(_look[3], _look[4], _look[5]), Vector3.UP)
	if _precip != null:
		_precip.global_position = cam.global_position + cam.global_transform.basis.z * -12.0 + Vector3(0, 22, 0)
		var splash := _precip.get_node_or_null("Splashes") as Node3D
		if splash != null:
			var c := cam.global_position
			splash.global_position = Vector3(c.x, feed.terrain.height_at(c.x, c.z) + 0.05, c.z)
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
			v.setup(d.kind, col, id != my_id, p.model if p else 0)
			add_child(v)
			drone_views[id] = v
		v.global_position = d.pos
		v.quaternion = d.rot
		v.visible = id != my_id or _chase_mode
		v.update_state(d, delta)


func _fpv_camera(d: DroneState, delta: float) -> void:
	var tilt := deg_to_rad(Settings.camera_tilt) if d.kind == SimConst.Kind.COPTER else deg_to_rad(4.0)
	var basis := Basis(d.rot) * Basis(Vector3.RIGHT, tilt)
	var offset := Basis(d.rot) * Vector3(0, 0.12, -0.25)
	var jitter := Vector3.ZERO
	if shake > 0.0 or d.signal_q < 0.3:
		var amp := shake * 0.15 + maxf(0.0, 0.3 - d.signal_q) * 0.03
		jitter = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0)
	cam.global_transform = Transform3D(basis, d.pos + offset + jitter)
	_fov = lerpf(_fov, Settings.fov + (6.0 if _last_input.boost else 0.0), delta * 4.0)
	_chase_pos = cam.global_position


func _chase_camera(d: DroneState, delta: float) -> void:
	_fov = 70.0
	var back := -d.vel.normalized() if d.vel.length() > 2.0 else -d.forward()
	var dist := (3.2 if d.kind == SimConst.Kind.COPTER else 5.5) if _clean else 7.0   # для съёмки моделей — ближе
	var want := d.pos + back * dist + Vector3(0, 1.2 if _clean else 2.2, 0)
	want.y = maxf(want.y, feed.terrain.height_at(want.x, want.z) + 1.5)
	_chase_pos = want if _chase_pos == Vector3.ZERO else _chase_pos.lerp(want, clampf(delta * (12.0 if _clean else 5.0), 0.0, 1.0))
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
	_fov = lerpf(_fov, 75.0, delta * 3.0)
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


## Выбывшее укрытие: осевшие, закопчённые постройки и столб дыма до конца матча.
func _ruin_shelter(n: Node3D) -> void:
	if n.has_meta("ruined"):
		return
	n.set_meta("ruined", true)
	var body := n.get_node_or_null("Body") as GeometryInstance3D
	if body != null:
		body.scale = Vector3(1.05, 0.55, 1.05)
		body.rotation = Vector3(0.06, 0.0, -0.05)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.32, 0.30, 0.28)
		m.roughness = 1.0
		body.material_override = m
	Fx.smoke_column(n, Vector3(0, 2.0, 0), quality)


func _update_post(d: DroneState) -> void:
	post.visible = not _clean
	var amount: float = [0.0, 0.5, 1.0][clampi(Settings.camera_filter, 0, 2)]
	var fpv := d != null and not _chase_mode and _look.is_empty()
	if not fpv:
		amount *= 0.3
	# Линза: FPV — широкий угол с бочкой, наблюдение — почти без искажений, кадры без фильтра — без линзы.
	_lens_k = 0.0 if _clean else (lerpf(0.12, 0.34, amount) if fpv else 0.03)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	_lens_s = 1.0 / (1.0 + _lens_k * aspect * aspect * 0.25)
	cam.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov) * 0.5) / _lens_s)), 1.0, 165.0)
	post_mat.set_shader_parameter("lens_k", _lens_k)
	post_mat.set_shader_parameter("lens_s", _lens_s)
	post_mat.set_shader_parameter("amount", amount)
	# Смаз и роллинг-шаттер — от поворота камеры за кадр.
	var dt := maxf(get_process_delta_time(), 0.001)
	var rel := _prev_basis.inverse() * cam.global_transform.basis
	_prev_basis = cam.global_transform.basis
	var e := rel.get_euler()
	var vf := deg_to_rad(cam.fov)
	var hf := 2.0 * atan(tan(vf * 0.5) * aspect)
	var bv := Vector2(-e.y / hf, e.x / vf) * 0.6
	if bv.length() > 0.08:
		bv = bv.normalized() * 0.08   # резкий разворот/телепорт камеры — без «полосы на весь экран»
	post_mat.set_shader_parameter("blur_vec", bv if fpv else Vector2.ZERO)
	post_mat.set_shader_parameter("roll_rate", clampf(e.z * 0.6, -0.08, 0.08) if fpv else 0.0)
	post_mat.set_shader_parameter("shutter", clampf(-e.y / dt * 0.004, -0.03, 0.03) if fpv else 0.0)
	post_mat.set_shader_parameter("jello", (clampf(d.thrust_frac, 0.0, 1.0) * 0.6 + clampf(d.vel.length() / 50.0, 0.0, 1.0) * 0.4) if fpv else 0.0)
	var preset: MapPreset = feed.terrain.preset
	post_mat.set_shader_parameter("gain", [0.1, 0.4, 0.4, 0.25, 0.25, 1.0][preset.daytime])
	post_mat.set_shader_parameter("rain", 0.8 if fpv and preset.precip == MapPreset.Precip.RAIN else 0.0)
	post_mat.set_shader_parameter("compress", 0.15)
	post_mat.set_shader_parameter("sun_pos", _sun_screen(preset))
	if d != null:
		var nl := clampf(d.nolink / SimConst.NOLINK_FALL, 0.0, 1.0)
		if not d.control and d.trapped <= 0.0:
			nl = 1.0
		post_mat.set_shader_parameter("signal_q", d.signal_q)
		post_mat.set_shader_parameter("nolink", nl * 0.85)
		post_mat.set_shader_parameter("jam", clampf(0.15 + (1.0 - d.signal_q) * 0.9, 0.0, 1.0) if d.jammed else 0.0)
		post_mat.set_shader_parameter("spectate", 0.0)
	else:
		post_mat.set_shader_parameter("signal_q", 1.0)
		post_mat.set_shader_parameter("nolink", 0.0)
		post_mat.set_shader_parameter("jam", 0.0)
		post_mat.set_shader_parameter("spectate", 1.0)
	post_mat.set_shader_parameter("hit_flash", hit_flash)


## Солнце на экране (uv) и его видимость: не за рельефом/постройкой, не ночью, слабее в пасмурно.
func _sun_screen(preset: MapPreset) -> Vector3:
	if _sun == null or preset.daytime == MapPreset.Daytime.NIGHT:
		return Vector3(0.5, 0.5, 0.0)
	var to_sun := _sun.global_transform.basis.z.normalized()
	var p := cam.global_position + to_sun * 1000.0
	if cam.is_position_behind(p):
		return Vector3(0.5, 0.5, 0.0)
	var size := get_viewport().get_visible_rect().size
	var sp := _proj(p) / size
	var off := maxf(absf(sp.x - 0.5), absf(sp.y - 0.5))
	var vis := 1.0 - smoothstep(0.45, 0.75, off)
	if vis <= 0.0 or not feed.terrain.line_of_sight(cam.global_position, cam.global_position + to_sun * 500.0):
		return Vector3(sp.x, sp.y, 0.0)
	var k: float = {MapPreset.Daytime.OVERCAST: 0.15, MapPreset.Daytime.FOG: 0.35}.get(preset.daytime, 1.0)
	return Vector3(sp.x, sp.y, vis * k)


## Точка мира → экран с учётом линзы фильтра (обратная функция бочки из fpv_feed.gdshader).
func _proj(p: Vector3) -> Vector2:
	var q := cam.unproject_position(p)
	if _lens_k <= 0.0 and _lens_s == 1.0:
		return q
	var size := get_viewport().get_visible_rect().size
	var asp := Vector2(size.aspect(), 1.0)
	var sc := (q / size - Vector2(0.5, 0.5)) * asp
	var rho := sc.length()
	if rho < 1e-6:
		return q
	var r := rho / _lens_s
	for i in 4:   # Ньютон: r·s·(1 + k·r²) = ρ
		var f := r * _lens_s * (1.0 + _lens_k * r * r) - rho
		r -= f / (_lens_s * (1.0 + 3.0 * _lens_k * r * r))
	var cn := sc * (r / rho)
	return (cn / asp + Vector2(0.5, 0.5)) * size


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
	var warns := []
	# Чужие дроны: рамка на экране (с точкой упреждения) или стрелка у края.
	var targets := []
	var ref: Vector3 = d.pos if d != null else cam.global_position
	var my_speed: float = d.vel.length() if d != null else 0.0
	var view := Rect2(Vector2.ZERO, osd.size).grow(-30.0)
	var at_home := false
	var hot_any := false
	var cam_fwd := -cam.global_transform.basis.z
	var cand := 0
	var cand_ang := LOCK_CONE
	for o: DroneState in drones.values():
		if o.owner == feed.my_pid:
			continue
		if me != null and not me.eliminated and o.pos.distance_to(feed.terrain.shelters[me.shelter]) < SimConst.TRAP_RADIUS:
			at_home = true
		var dist := ref.distance_to(o.pos)
		if dist > 700.0:
			continue
		var hot: bool = d != null and dist < SimConst.INTERCEPT_BLAST[d.kind] * 0.9
		hot_any = hot_any or hot
		var m := {"color": _color(o.owner), "label": "дрон " + _name(o.owner), "dist": dist, "hot": hot, "on": false,
			"locked": o.id == _lock_id, "id": o.id}
		if d != null and dist < LOCK_PICK_RANGE:
			var ang := cam_fwd.angle_to(o.pos - cam.global_position)
			if ang < cand_ang:
				cand_ang = ang
				cand = o.id
		var behind := cam.is_position_behind(o.pos)
		var sc := Vector2.ZERO if behind else _proj(o.pos)
		if not behind and view.has_point(sc):
			m.on = true
			m.pos = sc
			if d != null and o.id == _lock_id:
				var tg := _lock_target()
				var lp := PilotAssist.lead_point(d, tg if tg != null else o)
				if not cam.is_position_behind(lp):
					m.lead = _proj(lp)
			elif d != null and dist < 450.0 and dist > 8.0:
				var lead := o.pos + o.vel * (dist / maxf(my_speed, 20.0))
				if not cam.is_position_behind(lead):
					m.lead = _proj(lead)
		elif dist < 400.0 or o.id == _lock_id:
			var loc := cam.global_transform.affine_inverse() * o.pos
			var dir := Vector2(loc.x, -loc.y)
			dir = dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
			var half := osd.size * 0.5 - Vector2(70, 70)
			m.pos = osd.size * 0.5 + dir * minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			m.dir = dir
		else:
			continue
		targets.append(m)
	_lock_cand = cand
	for m in targets:
		m.cand = _lock_id == 0 and m.id == cand
	data.targets = targets
	data.lock_ready = d != null and (cand != 0 or _lock_id != 0)
	data.lock_on = _lock_id != 0
	if _lock_id != 0:
		var tg := _lock_target()
		if tg != null:
			data.lock = {"name": _name(tg.owner), "dist": ref.distance_to(tg.pos), "color": _color(tg.owner)}
	if hot_any:
		warns.append(["ЦЕЛЬ РЯДОМ — ПОДРЫВ [ПРОБЕЛ]", true])
	if at_home and me.trap_cd <= 0.0 and not feed.sudden_death():
		warns.append(["ДРОН У УКРЫТИЯ — СЕТЬ [F]", true])
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
				data.horizon = [_proj(a), _proj(b)]
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
				var sc := _proj(sp)
				if Rect2(Vector2.ZERO, osd.size).has_point(sc):
					smarks.append({"pos": sc, "color": col, "label": p.name, "dist": to.length()})
		data.marks = marks
		data.screen_marks = smarks
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
			Fx.explosion(self, pos, ev.kind == SimConst.Kind.PLANE, quality, feed.terrain.height_at(pos.x, pos.z))
			if ev.pid == feed.my_pid:
				hit_flash = 0.9
				shake = 0.6
				var why := {"ground": "Дрон разбился о землю", "tree": "Дрон задел дерево", "building": "Дрон врезался в постройку",
					"turret": "Дрон сбит турелью", "ram": "Таран: дрон потерян", "blast": "Дрон сбит взрывом", "detonate": "Подрыв", "shelter": "Удар по укрытию",
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
				_ruin_shelter(n2)
		"ram":
			osd.push_line("Перехват: %s и %s" % [_name(ev.a), _name(ev.b)], UiTheme.TEXT)
			# a — меньший pid пары (у ботов pid < 0), так что свой дрон может быть и в b.
			if ev.a == feed.my_pid or ev.b == feed.my_pid:
				_beep(990.0, 0.1)
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
	if menu_open:
		_drop_lock("Автозахват снят: меню", UiTheme.DIM)
	pause_menu.visible = menu_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED


func _build_pause_menu() -> Control:
	var root := ColorRect.new()
	root.theme = UiTheme.theme()
	root.color = Color(0.015, 0.025, 0.035, 0.6)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiTheme.kicker("Пауза оператора", UiTheme.ACCENT))
	box.add_child(UiTheme.heading("Меню", 34))
	box.add_child(UiTheme.label("Матч продолжается — дрон висит без команд.", 16, UiTheme.DIM))
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.primary("Вернуться", _toggle_menu))
	box.add_child(UiTheme.button("Режим: аркада / акро (C)", func():
		Settings.acro = not Settings.acro
		osd.push_line("Режим: %s" % ("акро" if Settings.acro else "аркада"), UiTheme.ACCENT)))
	var alt_text := func(): return "Помощь высоты коптера: %s" % ("вкл" if Settings.alt_assist else "выкл")
	var alt_btn := UiTheme.button(alt_text.call(), func(): pass)
	alt_btn.pressed.connect(func():
		Settings.alt_assist = not Settings.alt_assist
		Settings.save()
		alt_btn.text = alt_text.call()
		osd.push_line("Помощь высоты: %s" % ("вкл" if Settings.alt_assist else "выкл"), UiTheme.ACCENT))
	box.add_child(alt_btn)
	var hint := UiTheme.label("R / геймпад Y — автозахват чужого дрона под прицелом; повторно или движение ручек — отмена. Пробел — подрыв.", 15, UiTheme.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	box.add_child(UiTheme.button("Выйти из матча", func(): leave_requested.emit()))
	return root
