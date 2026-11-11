class_name Wind
## Общий для всех ветер: медленно меняет направление и силу, порывы,
## сильнее на высоте и над гребнями. Детерминирован от времени и пресета карты
## (базовая сила, направление и порывистость — от сида).

static func at(p: Vector3, t: float, preset: MapPreset, ground: float) -> Vector3:
	var s := preset.wind_phase
	var dir := preset.wind_dir + t * 0.012 + sin(t * 0.031 + s) * 0.6
	var base := preset.wind_base + preset.wind_swing * sin(t * 0.045 + s * 2.0)
	var gust := maxf(0.0, sin(t * 0.7 + p.x * 0.013 + s) * sin(t * 0.23 + p.z * 0.011)) * preset.wind_gust
	var agl := maxf(0.0, p.y - ground)
	var height_k := 0.45 + minf(agl / 90.0, 1.4)
	var ridge_k := 1.0 + clampf((ground - preset.ground_ref()) / 60.0, 0.0, 0.8)
	var strength := (base + gust) * height_k * ridge_k
	var turb := Vector3(
		sin(t * 2.3 + p.z * 0.07 + s),
		sin(t * 1.7 + p.x * 0.05) * 0.5,
		sin(t * 2.9 + p.x * 0.06 - s)) * (0.4 + gust * 0.25) * height_k
	return Vector3(cos(dir), 0.0, sin(dir)) * strength + turb


## Средний ветер для OSD (без турбулентности).
static func mean(t: float, preset: MapPreset) -> Vector3:
	var s := preset.wind_phase
	var dir := preset.wind_dir + t * 0.012 + sin(t * 0.031 + s) * 0.6
	var base := preset.wind_base + preset.wind_swing * sin(t * 0.045 + s * 2.0)
	return Vector3(cos(dir), 0.0, sin(dir)) * base
