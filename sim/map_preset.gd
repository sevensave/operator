class_name MapPreset
extends RefCounted
## Параметры карты, выведенные из сида матча: архетип рельефа, раскладка укрытий,
## застройка, лес и ветер. Сервер и клиент получают одинаковый пресет из одного сида,
## поэтому в MATCH_START ничего нового не передаётся.

enum Relief { VALLEY, PLATEAU, RIDGE, CANYON, HILLS }
const RELIEF_NAMES := ["Долина", "Плато", "Хребет", "Каньон", "Холмы"]
const RELIEF_COUNT := 5

enum TreeKind { SPRUCE, LEAFY, DEAD }
const WIND_NAMES := ["штиль", "умеренный ветер", "сильный ветер"]

var seed := 0
var relief := Relief.VALLEY

# Рельеф (смысл части полей зависит от архетипа).
var hill_freq := 0.0042
var hill_amp := 24.0
var ridge_freq := 0.0021
var ridge_amp := 30.0
var ridge_r0 := 120.0       # кольцо гребней (долина)
var ridge_r1 := 380.0
var center_depth := 6.0     # низина в центре (долина)
var base_lift := 6.0        # базовый уровень земли
var border_height := 110.0  # горы-стена по краю арены, есть всегда
var axis_angle := 0.0       # направление хребта/каньона
var axis_offset := 0.0      # сдвиг оси от центра
var feature_height := 0.0   # высота хребта/плато, глубина каньона
var feature_width := 0.0    # ширина хребта/каньона, радиус плато
var meander_amp := 0.0      # извилистость каньона
var meander_freq := 0.0
var passes: Array[float] = []      # перевалы хребта: координаты вдоль оси
var outcrops: Array[Vector4] = []  # останцы: x, z, радиус, высота

# Укрытия.
var shelter_ring := 420.0

# Застройка.
var clusters: Array[Vector3] = []  # скопления руин: x, z, радиус
var cluster_sizes: Array[int] = []
var scattered := 26
var towers := 6

# Лес.
var tree_count := 900
var tree_threshold := 0.08
var tree_kind := TreeKind.SPRUCE

# Ветер.
var wind_level := 1          # 0 штиль, 1 умеренный, 2 сильный
var wind_base := 3.0
var wind_swing := 2.2
var wind_gust := 4.0
var wind_dir := 0.0
var wind_phase := 0.0


static func from_seed(p_seed: int) -> MapPreset:
	var p := MapPreset.new()
	p.seed = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p_seed) ^ 0x5eed
	p.relief = posmod(p_seed, RELIEF_COUNT)
	p._roll_relief(rng)
	p._roll_layout(rng)
	p._roll_forest(rng)
	p._roll_wind(rng)
	return p


## Сид с нужным архетипом: ближайший сверху к данному (для --preset=N в тренировке).
static func seed_with_relief(p_seed: int, relief_idx: int) -> int:
	var r := posmod(relief_idx, RELIEF_COUNT)
	return p_seed + posmod(r - posmod(p_seed, RELIEF_COUNT), RELIEF_COUNT)


func relief_name() -> String:
	return RELIEF_NAMES[relief]


func title() -> String:
	return relief_name()


func _roll_relief(rng: RandomNumberGenerator) -> void:
	axis_angle = rng.randf() * TAU
	border_height = rng.randf_range(95.0, 125.0)
	match relief:
		Relief.VALLEY:
			hill_freq = rng.randf_range(0.0036, 0.005)
			hill_amp = rng.randf_range(18.0, 28.0)
			ridge_amp = rng.randf_range(24.0, 40.0)
			ridge_r0 = rng.randf_range(100.0, 160.0)
			ridge_r1 = rng.randf_range(340.0, 400.0)
			center_depth = rng.randf_range(4.0, 12.0)
			base_lift = 6.0
		Relief.PLATEAU:
			hill_freq = rng.randf_range(0.004, 0.006)
			hill_amp = rng.randf_range(8.0, 14.0)
			ridge_amp = rng.randf_range(8.0, 16.0)
			feature_height = rng.randf_range(34.0, 50.0)
			feature_width = rng.randf_range(220.0, 280.0)
			axis_offset = rng.randf_range(0.0, 70.0)
			base_lift = 2.0
		Relief.RIDGE:
			hill_freq = rng.randf_range(0.004, 0.0055)
			hill_amp = rng.randf_range(10.0, 18.0)
			ridge_amp = rng.randf_range(14.0, 24.0)
			feature_height = rng.randf_range(55.0, 80.0)
			feature_width = rng.randf_range(65.0, 90.0)
			axis_offset = rng.randf_range(-60.0, 60.0)
			var n := rng.randi_range(2, 3)
			passes.clear()
			for i in n:
				passes.append(lerpf(-300.0, 300.0, (i + 0.5) / n) + rng.randf_range(-50.0, 50.0))
			base_lift = 4.0
		Relief.CANYON:
			hill_freq = rng.randf_range(0.004, 0.006)
			hill_amp = rng.randf_range(5.0, 9.0)
			ridge_amp = rng.randf_range(6.0, 12.0)
			feature_height = rng.randf_range(28.0, 40.0)   # глубина
			feature_width = rng.randf_range(30.0, 45.0)    # полуширина дна
			meander_amp = rng.randf_range(50.0, 110.0)
			meander_freq = rng.randf_range(0.006, 0.011)
			axis_offset = rng.randf_range(-80.0, 80.0)
			base_lift = 34.0
		Relief.HILLS:
			hill_freq = rng.randf_range(0.0055, 0.0075)
			hill_amp = rng.randf_range(30.0, 42.0)
			ridge_amp = rng.randf_range(10.0, 20.0)
			base_lift = 18.0
			outcrops.clear()
			var n := rng.randi_range(6, 11)
			for i in n:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * 470.0
				outcrops.append(Vector4(cos(a) * r, sin(a) * r, rng.randf_range(14.0, 26.0), rng.randf_range(22.0, 40.0)))


func _roll_layout(rng: RandomNumberGenerator) -> void:
	shelter_ring = rng.randf_range(380.0, 450.0)
	clusters.clear()
	cluster_sizes.clear()
	var n := rng.randi_range(1, 3)
	for i in n:
		var c := Vector2.ZERO
		if i > 0 or relief != Relief.VALLEY:
			var a := rng.randf() * TAU
			c = Vector2(cos(a), sin(a)) * rng.randf_range(0.0 if i == 0 else 120.0, 260.0)
		var rad := rng.randf_range(55.0, 95.0) if i == 0 else rng.randf_range(40.0, 70.0)
		clusters.append(Vector3(c.x, c.y, rad))
		cluster_sizes.append(rng.randi_range(14, 24) if i == 0 else rng.randi_range(6, 12))
	scattered = rng.randi_range(12, 26)
	towers = rng.randi_range(0, 8)


func _roll_forest(rng: RandomNumberGenerator) -> void:
	var density := rng.randi_range(0, 2)
	tree_count = [300, 600, 900][density] + rng.randi_range(-50, 0)
	tree_threshold = [0.22, 0.12, 0.04][density]
	var k := rng.randf()
	if relief == Relief.CANYON or relief == Relief.HILLS:
		tree_kind = TreeKind.LEAFY if k < 0.45 else (TreeKind.DEAD if k < 0.75 else TreeKind.SPRUCE)
	else:
		tree_kind = TreeKind.SPRUCE if k < 0.5 else (TreeKind.LEAFY if k < 0.82 else TreeKind.DEAD)


func _roll_wind(rng: RandomNumberGenerator) -> void:
	var k := rng.randf()
	wind_level = 0 if k < 0.3 else (1 if k < 0.75 else 2)
	match wind_level:
		0:
			wind_base = 1.2
			wind_swing = 0.8
			wind_gust = 1.5
		1:
			wind_base = 3.0
			wind_swing = 2.2
			wind_gust = 4.0
		2:
			wind_base = 4.8
			wind_swing = 1.6
			wind_gust = 5.0
	wind_dir = rng.randf() * TAU
	wind_phase = rng.randf() * 100.0


## Опорный уровень земли: выше него ветер над гребнями усиливается.
func ground_ref() -> float:
	return base_lift + 14.0
