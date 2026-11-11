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


## Упаковка для снапшота.
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
