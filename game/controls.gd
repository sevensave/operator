class_name Controls
extends RefCounted
## Сборка DroneInput из клавиатуры, мыши и геймпада.
## Клавиатура: W/S — газ, A/D — поворот, стрелки или мышь — наклон, Shift — форсаж,
## Пробел — подрыв, F — сеть, R — автозахват, 1/2 — тип следующего дрона.
## Геймпад (режим 2): левый стик — газ/поворот, правый — наклон, RT — форсаж,
## A — подрыв, X — сеть, Y — автозахват, LB/RB — тип дрона.
## Автозахват и помощь высоты подменяют собранный ввод в MatchView._process.

var mouse_stick := Vector2.ZERO   # x — крен, y — тангаж
var mouse_active := false
var seq := 0
const MOUSE_RETURN := 3.0
const DEADZONE := 0.12


func on_mouse_motion(rel: Vector2, sens: float, invert: bool) -> void:
	mouse_active = true
	mouse_stick.x = clampf(mouse_stick.x + rel.x * 0.004 * sens, -1.0, 1.0)
	mouse_stick.y = clampf(mouse_stick.y + rel.y * 0.004 * sens * (-1.0 if invert else 1.0), -1.0, 1.0)


func sample(delta: float, acro: bool) -> DroneInput:
	var i := DroneInput.new()
	seq += 1
	i.seq = seq
	i.acro = acro
	# Мышь — «пружинящий» стик: отпустил — возвращается в центр.
	mouse_stick = mouse_stick.move_toward(Vector2.ZERO, MOUSE_RETURN * delta * maxf(0.3, mouse_stick.length()))
	var kb_throttle := _axis(KEY_S, KEY_W)
	var kb_yaw := _axis(KEY_A, KEY_D)
	var kb_pitch := _axis(KEY_DOWN, KEY_UP)
	var kb_roll := _axis(KEY_LEFT, KEY_RIGHT)
	# Q/E — крен для тех, кто держит руку на WASD.
	kb_roll += _axis(KEY_Q, KEY_E)
	var pad := _pad()
	i.throttle = clampf(kb_throttle + pad.throttle, -1, 1)
	i.yaw = clampf(kb_yaw + pad.yaw, -1, 1)
	# Мышь вниз (rel.y > 0) — ручка от себя? Нет: как в авиасимах, мышь вперёд (вверх) — нос вниз.
	i.pitch = clampf(kb_pitch + pad.pitch - mouse_stick.y, -1, 1)
	i.roll = clampf(kb_roll + pad.roll + mouse_stick.x, -1, 1)
	i.boost = Input.is_key_pressed(KEY_SHIFT) or pad.boost
	return i


func _axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


func _pad() -> Dictionary:
	var out := {"throttle": 0.0, "yaw": 0.0, "pitch": 0.0, "roll": 0.0, "boost": false}
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return out
	var id: int = pads[0]
	out.throttle = -_dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
	out.yaw = _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
	out.pitch = -_dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
	out.roll = _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X))
	out.boost = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	return out


static func _dz(v: float) -> float:
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)
