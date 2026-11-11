class_name Interp
## Интерполяция состояний дронов для плавной картинки.

static func lerp_state(a: DroneState, b: DroneState, t: float) -> DroneState:
	var d := b.clone()
	d.pos = a.pos.lerp(b.pos, t)
	d.vel = a.vel.lerp(b.vel, t)
	d.rot = a.rot.slerp(b.rot, t)
	d.thrust_frac = lerpf(a.thrust_frac, b.thrust_frac, t)
	d.signal_q = lerpf(a.signal_q, b.signal_q, t)
	return d
