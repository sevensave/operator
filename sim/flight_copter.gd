class_name FlightCopter
## Квадрокоптер: висит, резко маневрирует, скорость до ~33 м/с (с форсажем быстрее).
## Режим «аркада» — ручки задают угол наклона и вертикальную скорость (автовыравнивание),
## «акро» — ручки задают угловые скорости, газ — абсолютная тяга.

const MAX_TILT := deg_to_rad(45.0)
const MAX_TILT_BOOST := deg_to_rad(52.0)
const TILT_RESPONSE := 8.0
const YAW_RATE := 2.4
const ACRO_RATE := 6.5
const ACRO_RESPONSE := 18.0
const MAX_THRUST := 2.7 * SimConst.GRAVITY
const BOOST_THRUST := 3.3 * SimConst.GRAVITY
const CLIMB_SPEED := 10.0    # аркада: газ +1 — подъём 10 м/с
const DESCENT_SPEED := 22.0  # аркада: газ −1 — снижение до 22 м/с (не быстрее свободного падения)
const CLIMB_DAMP := 1.2
const BRAKE_DAMP := 3.0      # торможение снижения/разгон вверх резче, чтобы после пике не «проваливаться»
const DIVE_EXTRA_TILT := deg_to_rad(32.0)  # газ вниз + ручка от себя — нос опускается глубже
const DIVE_THRUST_K := 0.55   # нижний предел тяги ∝ наклону: в пике винты продолжают тянуть вперёд
const DRAG_LIN := 0.05
const DRAG_QUAD := 0.0075
const DRAIN_HOVER := 1.0 / 220.0 # ~3,7 мин висения на одном заряде


static func step(s: DroneState, inp: DroneInput, dt: float, air: Vector3) -> void:
	var g := SimConst.GRAVITY
	var thrust := 0.0
	var powered := s.control and s.battery > 0.0
	if powered:
		if inp.acro:
			var target := Vector3(-inp.pitch, -inp.yaw * 0.6, -inp.roll) * ACRO_RATE
			s.angvel = s.angvel.lerp(target, 1.0 - exp(-ACRO_RESPONSE * dt))
			_integrate_rot(s, dt)
			var max_t := BOOST_THRUST if inp.boost else MAX_THRUST
			thrust = (inp.throttle + 1.0) * 0.5 * max_t
		else:
			var prev := s.rot
			s.rot = (Quaternion(Vector3.UP, -inp.yaw * YAW_RATE * dt) * s.rot).normalized()
			var fwd := s.forward()
			fwd.y = 0.0
			var yaw := 0.0
			if fwd.length_squared() > 0.0001:
				yaw = atan2(-fwd.x, -fwd.z)
			var tilt := MAX_TILT_BOOST if inp.boost else MAX_TILT
			var tilt_p := tilt
			if inp.pitch > 0.0 and inp.throttle < 0.0:
				tilt_p += DIVE_EXTRA_TILT * -inp.throttle
			var target_rot := Quaternion(Vector3.UP, yaw) \
				* Quaternion(Vector3.RIGHT, -inp.pitch * tilt_p) \
				* Quaternion(Vector3.BACK, -inp.roll * tilt)
			s.rot = s.rot.slerp(target_rot.normalized(), 1.0 - exp(-TILT_RESPONSE * dt)).normalized()
			# Угловая скорость нужна для OSD/визуала и турели.
			var dq := prev.inverse() * s.rot
			s.angvel = dq.get_axis() * dq.get_angle() / dt if dq.get_angle() > 0.00001 else Vector3.ZERO
			var up := s.up()
			var cos_t := maxf(up.y, 0.4)
			var v_t := arcade_vspeed(inp.throttle)
			var want := (v_t - s.vel.y) * (BRAKE_DAMP if s.vel.y < v_t else CLIMB_DAMP)
			var max_t := BOOST_THRUST if inp.boost else MAX_THRUST
			var floor_t := g * sqrt(maxf(0.0, 1.0 - up.y * up.y)) * DIVE_THRUST_K
			thrust = clampf(maxf((g + want) / cos_t, floor_t), 0.0, max_t)
	else:
		# Без управления винты встают, дрон кувыркается вниз.
		s.angvel = s.angvel.lerp(Vector3(1.2, 0.4, 0.8), 1.0 - exp(-1.5 * dt))
		_integrate_rot(s, dt)

	var rel := s.vel - air
	var acc := s.up() * thrust + Vector3(0, -g, 0) - rel * DRAG_LIN - rel * rel.length() * DRAG_QUAD
	s.vel += acc * dt
	s.pos += s.vel * dt
	s.thrust_frac = thrust / MAX_THRUST
	if powered:
		var drain := DRAIN_HOVER * (0.35 + 0.65 * thrust / g) * (1.45 if inp.boost else 1.0)
		s.battery = maxf(0.0, s.battery - drain * dt)


## Целевая вертикальная скорость аркады. Вниз — кривая: малые отклонения дают мягкие
## 0…−5 м/с для точного подхода, полный ход — быстрое снижение.
static func arcade_vspeed(throttle: float) -> float:
	if throttle >= 0.0:
		return throttle * CLIMB_SPEED
	var a := -throttle
	return -DESCENT_SPEED * (0.35 * a + 0.65 * a * a)


## Обратная к arcade_vspeed: какой газ даёт нужную вертикальную скорость (для ботов).
static func throttle_for_vspeed(v: float) -> float:
	if v >= 0.0:
		return clampf(v / CLIMB_SPEED, 0.0, 1.0)
	var a := minf(-v / DESCENT_SPEED, 1.0)
	# 0,65·x² + 0,35·x − a = 0
	return -(-0.35 + sqrt(0.35 * 0.35 + 4.0 * 0.65 * a)) / (2.0 * 0.65)


static func _integrate_rot(s: DroneState, dt: float) -> void:
	var ang := s.angvel.length() * dt
	if ang > 0.000001:
		s.rot = (s.rot * Quaternion(s.angvel.normalized(), ang)).normalized()
