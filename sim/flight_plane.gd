class_name FlightPlane
## Самолёт: не висит, широкие виражи, сваливание на малой скорости, 30–50 м/с.
## Подъёмная сила зависит от угла атаки, поэтому разворот идёт креном и тангажом.
## «Аркада» сама выравнивает крен и слегка держит горизонт, когда ручки отпущены.

const PITCH_RATE := 1.15
const ROLL_RATE := 3.0
const YAW_RATE := 0.45
const RATE_RESPONSE := 7.0
const THRUST := 13.5
const BOOST_THRUST := 19.5
const DRAG := 0.0054
const CL_A := 5.0
const ALPHA_STALL := 0.27
const LIFT_K := 0.0448
const MAX_LIFT := 5.0 * SimConst.GRAVITY
const SIDE_DAMP := 0.8
const DRAIN := 1.0 / 330.0


static func step(s: DroneState, inp: DroneInput, dt: float, air: Vector3) -> void:
	var g := SimConst.GRAVITY
	var powered := s.control and s.battery > 0.0
	var fwd := s.forward()
	var up := s.up()
	var right := s.rot * Vector3.RIGHT
	var rel := s.vel - air
	var vf := rel.dot(fwd)
	var vu := rel.dot(up)
	var vr := rel.dot(right)
	var alpha := atan2(-vu, maxf(vf, 1.0))

	var target := Vector3.ZERO
	if powered:
		s.throttle = move_toward(s.throttle, clampf(0.6 + 0.4 * inp.throttle, 0.1, 1.0), dt * 0.9)
		target = Vector3(-inp.pitch * PITCH_RATE, -inp.yaw * YAW_RATE, -inp.roll * ROLL_RATE)
		if not inp.acro:
			if absf(inp.roll) < 0.1:
				target.z += -clampf(right.y, -1.0, 1.0) * 2.4   # выравнивание крена
			if absf(inp.pitch) < 0.1 and rel.length() > 1.0:
				target.x += -clampf(rel.normalized().y, -1.0, 1.0) * 1.6  # удержание горизонта
	else:
		s.throttle = move_toward(s.throttle, 0.0, dt)
		target = Vector3(-0.3, 0.0, 0.6)

	# Флюгерная устойчивость: нос сам тянется за потоком.
	target.x += -(alpha - 0.05) * 2.2
	target.y += -vr * 0.08
	if powered and not inp.acro:
		target.y += -asin(clampf(-right.y, -1.0, 1.0)) * 0.45   # координированный разворот
	s.angvel = s.angvel.lerp(target, 1.0 - exp(-RATE_RESPONSE * dt))
	var ang := s.angvel.length() * dt
	if ang > 0.000001:
		s.rot = (s.rot * Quaternion(s.angvel.normalized(), ang)).normalized()

	var cl := CL_A * alpha
	if absf(alpha) > ALPHA_STALL:
		cl = signf(alpha) * CL_A * ALPHA_STALL * 0.35
	var lift := clampf(LIFT_K * cl * vf * absf(vf), -MAX_LIFT, MAX_LIFT)
	var thrust := 0.0
	if powered:
		thrust = s.throttle * (BOOST_THRUST if inp.boost else THRUST)
	var acc := up * lift + fwd * thrust + Vector3(0, -g, 0)
	acc -= rel * rel.length() * DRAG
	acc -= fwd * absf(lift) * 0.035                # индуктивное сопротивление
	acc -= right * vr * SIDE_DAMP                  # гашение скольжения
	s.vel += acc * dt
	s.pos += s.vel * dt
	s.thrust_frac = thrust / THRUST
	if powered:
		var drain := DRAIN * (0.4 + 0.6 * s.throttle) * (1.4 if inp.boost else 1.0)
		s.battery = maxf(0.0, s.battery - drain * dt)


static func stalled(s: DroneState) -> bool:
	return s.vel.dot(s.forward()) < 17.0
