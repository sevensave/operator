extends SceneTree
## Статистика автозахвата на случайной геометрии: кто кого сбивает тараном, сколько пролётов
## в радиусе подрыва и срывов захвата. godot --headless --path . -s res://tools/lock_stats.gd
## Прогон берёт _chase из tests/test_pilot_assist.gd — те же правила срыва, что в клиенте.
func _initialize() -> void:
	var T = load("res://tests/test_pilot_assist.gd").new()
	var tr := Terrain.new()
	tr.generate(4242)
	for weave in [false, true]:
		print("цель петляет" if weave else "цель летит прямо")
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for pk in 2:
			for tk in 2:
				var hits := 0
				var close := 0
				var lost := 0
				var times := []
				var n := 40
				for i in n:
					var ang := rng.randf() * TAU
					var dist := rng.randf_range(120, 250)
					var y := tr.height_at(0, 0) + 90.0
					var bpos := Vector3(cos(ang) * dist, y + rng.randf_range(-15, 15), sin(ang) * dist)
					var inp := DroneInput.new()
					var bvel := Vector3(22, 0, 0)
					if tk == 0:
						inp.pitch = 0.6
					else:
						inp.throttle = rng.randf_range(0.0, 1.0)
						bvel = Vector3(40, 0, 0)
					var ph := rng.randf() * TAU
					var amp := 0.8 if tk == 0 else 0.6
					var fn := func(k: int) -> DroneInput:
						var q := inp.duplicate_input()
						q.roll = sin(k / 30.0 * 1.6 + ph) * amp
						return q
					var r: Dictionary = T._chase(pk, tk, Vector3(0, y, 0), Vector3(38, 0, 0) if pk == 1 else Vector3.ZERO, bpos, bvel, inp, 20.0, fn if weave else Callable())
					if r.rammed:
						hits += 1
						times.append(r.time)
					elif r.closest < 7.0:
						close += 1
					if r.lost:
						lost += 1
				times.sort()
				print("  %s → %s: таран %d/%d, пролёт < 7 м %d, захват сорван %d, медиана %.1f с" % [SimConst.KIND_NAMES[pk], SimConst.KIND_NAMES[tk], hits, n, close, lost, times[times.size() / 2] if times.size() > 0 else 0.0])
	quit()
