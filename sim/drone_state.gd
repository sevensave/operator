class_name DroneState
extends RefCounted
## Состояние одного дрона в симуляции.

var id := 0
var owner := 0
var kind := SimConst.Kind.COPTER
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Quaternion.IDENTITY
var angvel := Vector3.ZERO     # угловые скорости в осях дрона (x — тангаж, y — рыск, z — крен)
var throttle := 0.6            # для самолёта — положение РУД
var thrust_frac := 0.0         # доля тяги (для звука и OSD)
var battery := 1.0
var signal_q := 1.0            # качество связи 0..1
var nolink := 0.0              # сколько секунд связи нет
var control := true            # есть ли управление (нет при потере связи, пустой батарее, сети)
var trapped := 0.0             # сколько ещё держит сеть
var lock := 0.0                # захват автотурели 0..1
var jammed := false
var age := 0.0


func radius() -> float:
	return SimConst.DRONE_RADIUS[kind]


func forward() -> Vector3:
	return rot * Vector3.FORWARD


func up() -> Vector3:
	return rot * Vector3.UP


func copy_from(o: DroneState) -> void:
	id = o.id
	owner = o.owner
	kind = o.kind
	pos = o.pos
	vel = o.vel
	rot = o.rot
	angvel = o.angvel
	throttle = o.throttle
	thrust_frac = o.thrust_frac
	battery = o.battery
	signal_q = o.signal_q
	nolink = o.nolink
	control = o.control
	trapped = o.trapped
	lock = o.lock
	jammed = o.jammed
	age = o.age


func clone() -> DroneState:
	var d := DroneState.new()
	d.copy_from(self)
	return d


## Компактная бинарная упаковка для снапшота (~46 байт).
func write(b: StreamPeerBuffer) -> void:
	b.put_u16(id & 0xFFFF)
	b.put_32(owner)
	b.put_u8(kind)
	b.put_float(pos.x)
	b.put_float(pos.y)
	b.put_float(pos.z)
	b.put_half(vel.x)
	b.put_half(vel.y)
	b.put_half(vel.z)
	var q := rot.normalized()
	b.put_16(int(round(q.x * 32767.0)))
	b.put_16(int(round(q.y * 32767.0)))
	b.put_16(int(round(q.z * 32767.0)))
	b.put_16(int(round(q.w * 32767.0)))
	b.put_half(angvel.x)
	b.put_half(angvel.y)
	b.put_half(angvel.z)
	b.put_u8(int(clampf(throttle, 0, 1) * 255))
	b.put_u8(int(clampf(thrust_frac, 0, 2) * 127))
	b.put_u8(int(clampf(battery, 0, 1) * 255))
	b.put_u8(int(clampf(signal_q, 0, 1) * 255))
	b.put_u8(int(clampf(nolink, 0, 5) * 50))
	b.put_u8((1 if control else 0) | (2 if trapped > 0.0 else 0) | (4 if jammed else 0))
	b.put_u8(int(clampf(lock, 0, 1) * 255))


static func read(b: StreamPeerBuffer) -> DroneState:
	var d := DroneState.new()
	d.id = b.get_u16()
	d.owner = b.get_32()
	d.kind = b.get_u8()
	d.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
	d.vel = Vector3(b.get_half(), b.get_half(), b.get_half())
	d.rot = Quaternion(b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0).normalized()
	d.angvel = Vector3(b.get_half(), b.get_half(), b.get_half())
	d.throttle = b.get_u8() / 255.0
	d.thrust_frac = b.get_u8() / 127.0
	d.battery = b.get_u8() / 255.0
	d.signal_q = b.get_u8() / 255.0
	d.nolink = b.get_u8() / 50.0
	var f := b.get_u8()
	d.control = (f & 1) != 0
	d.trapped = 1.0 if (f & 2) != 0 else 0.0
	d.jammed = (f & 4) != 0
	d.lock = b.get_u8() / 255.0
	return d


## Упаковка для снапшота (читаемая, для отладки).
func to_array() -> Array:
	var flags := (1 if control else 0) | (2 if trapped > 0.0 else 0) | (4 if jammed else 0)
	return [id, owner, kind, pos, vel, rot, angvel, snappedf(throttle, 0.01),
		snappedf(thrust_frac, 0.01), snappedf(battery, 0.001), snappedf(signal_q, 0.01),
		snappedf(nolink, 0.01), flags, snappedf(lock, 0.01)]


static func from_array(a: Array) -> DroneState:
	var d := DroneState.new()
	d.apply_array(a)
	return d


func apply_array(a: Array) -> void:
	id = int(a[0])
	owner = int(a[1])
	kind = int(a[2])
	pos = a[3]
	vel = a[4]
	rot = a[5]
	angvel = a[6]
	throttle = float(a[7])
	thrust_frac = float(a[8])
	battery = float(a[9])
	signal_q = float(a[10])
	nolink = float(a[11])
	var f := int(a[12])
	control = (f & 1) != 0
	trapped = 1.0 if (f & 2) != 0 else 0.0
	jammed = (f & 4) != 0
	lock = float(a[13])
