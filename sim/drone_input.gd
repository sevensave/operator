class_name DroneInput
extends RefCounted
## Команды оператора за один тик. Оси от -1 до 1.
## pitch +1 — ручка от себя (нос вниз), roll +1 — крен вправо, yaw +1 — поворот вправо,
## throttle +1 — вверх / больше газа.

var seq := 0
var throttle := 0.0
var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var boost := false
var acro := false


func duplicate_input() -> DroneInput:
	var d := DroneInput.new()
	d.seq = seq
	d.throttle = throttle
	d.pitch = pitch
	d.roll = roll
	d.yaw = yaw
	d.boost = boost
	d.acro = acro
	return d


func scaled(k: float) -> DroneInput:
	var d := duplicate_input()
	d.throttle *= k
	d.pitch *= k
	d.roll *= k
	d.yaw *= k
	return d


## Компактная упаковка для сети: 4 оси по байту + флаги.
func to_array() -> Array:
	var flags := (1 if boost else 0) | (2 if acro else 0)
	return [seq, _q(throttle), _q(pitch), _q(roll), _q(yaw), flags]


static func from_array(a: Array) -> DroneInput:
	var d := DroneInput.new()
	if a.size() < 6:
		return d
	d.seq = int(a[0])
	d.throttle = _dq(a[1])
	d.pitch = _dq(a[2])
	d.roll = _dq(a[3])
	d.yaw = _dq(a[4])
	var f := int(a[5])
	d.boost = (f & 1) != 0
	d.acro = (f & 2) != 0
	return d


static func _q(v: float) -> int:
	return int(round(clampf(v, -1.0, 1.0) * 127.0))


static func _dq(v) -> float:
	return clampf(float(v) / 127.0, -1.0, 1.0)
