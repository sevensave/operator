class_name Wind
## Общий для всех ветер: медленно меняет направление и силу, порывы,
## сильнее на высоте и над гребнями. Детерминирован от времени и сида.

static func at(p: Vector3, t: float, seed: int, ground: float) -> Vector3:
	var s := float(seed % 1000) * 0.37
	var dir := s + t * 0.012 + sin(t * 0.031 + s) * 0.6
	var base := 3.0 + 2.2 * sin(t * 0.045 + s * 2.0)
	var gust := maxf(0.0, sin(t * 0.7 + p.x * 0.013 + s) * sin(t * 0.23 + p.z * 0.011)) * 4.0
	var agl := maxf(0.0, p.y - ground)
	var height_k := 0.45 + minf(agl / 90.0, 1.4)
	var ridge_k := 1.0 + clampf((ground - 20.0) / 60.0, 0.0, 0.8)
	var strength := (base + gust) * height_k * ridge_k
	var turb := Vector3(
		sin(t * 2.3 + p.z * 0.07 + s),
		sin(t * 1.7 + p.x * 0.05) * 0.5,
		sin(t * 2.9 + p.x * 0.06 - s)) * (0.4 + gust * 0.25) * height_k
	return Vector3(cos(dir), 0.0, sin(dir)) * strength + turb


## Средний ветер для OSD (без турбулентности).
static func mean(t: float, seed: int) -> Vector3:
	var s := float(seed % 1000) * 0.37
	var dir := s + t * 0.012 + sin(t * 0.031 + s) * 0.6
	var base := 3.0 + 2.2 * sin(t * 0.045 + s * 2.0)
	return Vector3(cos(dir), 0.0, sin(dir)) * base
