class_name SignalModel
## Качество связи дрона со своим оператором (0..1).
## Падает с расстоянием, без прямой видимости до своей антенны и в куполе чужой глушилки.

const LOS_PENALTY := 0.55
const JAM_FLOOR := 0.4
const LAG_START := 0.32      # ниже — задержка и «залипание» управления
const NOLINK := 0.08         # ниже — связи нет совсем


static func distance_quality(dist: float, kind: int) -> float:
	var r: float = SimConst.SIGNAL_RANGE[kind]
	return clampf(1.0 - pow(dist / r, 2.2), 0.0, 1.0)


## Множитель глушилки (1 — нет влияния). jammers — точки укрытий соперников.
static func jam_factor(p: Vector3, jammers: Array) -> float:
	var k := 1.0
	for j in jammers:
		var d := p.distance_to(j)
		if d < SimConst.JAMMER_RADIUS:
			var t := d / SimConst.JAMMER_RADIUS
			k *= lerpf(JAM_FLOOR, 1.0, t * t)
	return k


## Сколько тиков задержки ввода даёт текущее качество.
static func input_delay_ticks(q: float) -> int:
	if q >= LAG_START:
		return 0
	return int(round((LAG_START - q) / LAG_START * 10.0))


## Доля «шума» в управлении (дрожание ручек).
static func control_noise(q: float) -> float:
	return clampf((LAG_START - q) / LAG_START, 0.0, 1.0) * 0.35
