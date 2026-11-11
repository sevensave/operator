class_name Defenses
## Автотурель укрытия: набирает «захват» на чужом дроне, который идёт высоко и прямо
## в зоне её действия при прямой видимости. Уходится манёвром и малой высотой.

const LOCK_GAIN := 0.75
const LOCK_DECAY := 0.55
const LOW_AGL := 7.0
const HIGH_AGL := 28.0


## Насколько дрон «удобен» турели сейчас (0..1).
static func exposure(d: DroneState, agl: float, turret: Vector3, terrain: Terrain) -> float:
	var dist := d.pos.distance_to(turret)
	if dist > SimConst.TURRET_RANGE:
		return 0.0
	var height_k := clampf((agl - LOW_AGL) / (HIGH_AGL - LOW_AGL), 0.0, 1.0)
	if height_k <= 0.0:
		return 0.0
	# Резкие манёвры (большие угловые скорости) и боковое движение мешают захвату.
	var turn := d.angvel.length()
	var straight_k := clampf(1.0 - (turn - 0.4) / 1.6, 0.0, 1.0)
	var to_t := (turret - d.pos).normalized()
	var v := d.vel.length()
	var lateral := 0.0
	if v > 1.0:
		lateral = (d.vel - to_t * d.vel.dot(to_t)).length() / v
	var lateral_k := clampf(1.0 - lateral * 0.6, 0.3, 1.0)
	var near_k := 0.6 + 0.4 * (1.0 - dist / SimConst.TURRET_RANGE)
	var e := height_k * straight_k * lateral_k * near_k
	if e <= 0.02:
		return 0.0
	if not terrain.line_of_sight(turret + Vector3(0, 4, 0), d.pos):
		return 0.0
	return e
