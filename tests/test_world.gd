extends RefCounted
## Мир: ландшафт, столкновения, связь, защита, жизни и победа.

var t


func _world(n := 2, lives := 3) -> WorldSim:
	var w := WorldSim.new()
	var roster := []
	for i in n:
		roster.append({"pid": i + 1, "name": "И%d" % i, "color": i})
	w.setup(4242, roster, lives)
	return w


func _tick(w: WorldSim, seconds: float, inputs := {}) -> void:
	for i in int(seconds * SimConst.TICK_RATE):
		w.step(inputs)


func test_terrain_deterministic() -> void:
	var a := Terrain.new()
	a.generate(77)
	var b := Terrain.new()
	b.generate(77)
	t.near(a.height_at(123.4, -55.0), b.height_at(123.4, -55.0), 0.0001, "одинаковая высота")
	t.check(a.trees.size() == b.trees.size() and a.trees.size() > 300, "одинаковый лес: %d" % a.trees.size())
	t.check(a.boxes.size() == b.boxes.size() and a.boxes.size() > 15, "одинаковые руины")
	t.check(a.shelters.size() == 8, "8 укрытий")
	for s in a.shelters:
		t.near(a.height_at(s.x, s.z), s.y, 0.6, "площадка укрытия ровная")


func _terrain_hash(tr: Terrain) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(tr.heights.to_byte_array())
	ctx.update(var_to_bytes(tr.trees))
	ctx.update(var_to_bytes(tr.boxes))
	ctx.update(var_to_bytes(tr.shelters))
	return ctx.finish().hex_encode()


func _relief_seed(r: int, k := 0) -> int:
	return MapPreset.seed_with_relief(1000 + k * 7919 + r * 37, r)


func test_preset_from_seed() -> void:
	for r in MapPreset.RELIEF_COUNT:
		for base in [0, 17, 123456, 999999]:
			var sd := MapPreset.seed_with_relief(base, r)
			t.check(MapPreset.from_seed(sd).relief == r and sd >= base and sd < base + 5, "сид %d → архетип %d" % [sd, r])
	var a := MapPreset.from_seed(4242)
	var b := MapPreset.from_seed(4242)
	t.check(a.relief == b.relief and a.wind_base == b.wind_base and a.tree_kind == b.tree_kind \
		and a.shelter_ring == b.shelter_ring and a.clusters == b.clusters, "пресет детерминирован")
	t.check(a.title() != "", "у карты есть название")


func test_every_relief_is_deterministic_and_playable() -> void:
	for r in MapPreset.RELIEF_COUNT:
		for k in 2:
			var sd := _relief_seed(r, k)
			var a := Terrain.new()
			a.generate(sd)
			var b := Terrain.new()
			b.generate(sd)
			var name := "%s (сид %d)" % [a.preset.title(), sd]
			t.check(_terrain_hash(a) == _terrain_hash(b), "%s: одинаковая карта при двух генерациях" % name)
			t.check(a.shelters.size() == 8, "%s: 8 укрытий" % name)
			t.check(a.trees.size() >= 200 and a.boxes.size() >= 10, "%s: есть лес (%d) и постройки (%d)" % [name, a.trees.size(), a.boxes.size()])
			var min_d := INF
			for i in a.shelters.size():
				var s := a.shelters[i]
				t.near(a.height_at(s.x, s.z), s.y, 0.6, "%s: площадка укрытия %d ровная" % [name, i])
				t.check(a.collide(s + Vector3(0, 3, 0), 1.0) == "", "%s: над укрытием %d свободно" % [name, i])
				for j in range(i + 1, a.shelters.size()):
					min_d = minf(min_d, Vector2(s.x, s.z).distance_to(Vector2(a.shelters[j].x, a.shelters[j].z)))
				# Связь до центра карты достижима: с какой-то разумной высоты видна мачта.
				var mast := s + Vector3(0, SimConst.MAST_HEIGHT, 0)
				var seen := false
				for hgt in [30.0, 60.0, 100.0, 150.0]:
					if a.line_of_sight(mast, Vector3(0, a.height_at(0, 0) + hgt, 0)):
						seen = true
						break
				t.check(seen, "%s: от укрытия %d есть прямая видимость к центру" % [name, i])
			t.check(min_d >= Terrain.SHELTER_MIN_DIST, "%s: укрытия не ближе 220 м: %.0f" % [name, min_d])


## Метрики рельефа: средняя высота центра, кольца и разброс высот внутри арены.
func _relief_metrics(tr: Terrain) -> Vector3:
	var center := 0.0
	var nc := 0
	var vals := []
	for zi in range(0, Terrain.N, 2):
		for xi in range(0, Terrain.N, 2):
			var x := -SimConst.MAP_HALF + xi * Terrain.CELL
			var z := -SimConst.MAP_HALF + zi * Terrain.CELL
			var rr := Vector2(x, z).length()
			var h := tr.heights[zi * Terrain.N + xi]
			if rr < 150.0:
				center += h
				nc += 1
			if rr < 440.0:
				vals.append(h)
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var dev := 0.0
	for v in vals:
		dev += (v - mean) * (v - mean)
	return Vector3(center / nc, mean, sqrt(dev / vals.size()))


func test_reliefs_differ() -> void:
	var sig := []
	for r in MapPreset.RELIEF_COUNT:
		var tr := Terrain.new()
		tr.generate(_relief_seed(r))
		sig.append(_relief_metrics(tr))
		print("      %s: центр %.0f, средняя %.0f, разброс %.1f" % [tr.preset.title(), sig[r].x, sig[r].y, sig[r].z])
	for i in sig.size():
		for j in range(i + 1, sig.size()):
			var d: Vector3 = (sig[i] - sig[j]).abs()
			t.check(d.x > 6.0 or d.y > 6.0 or d.z > 3.0, "архетипы %d и %d различаются: %s" % [i, j, d])


func test_collide_finds_obstacle_across_grid_cell() -> void:
	var tr := Terrain.new()
	tr.generate(77)
	var found := 0
	for tree in tr.trees:
		# Проба радиусом 3 м сбоку от ствола, но уже в соседней ячейке индекса.
		var p := Vector3(tree.x + tree.z + 2.5, tree.w - 2.0, tree.y)
		if floori(p.x / Terrain.GRID) == floori(tree.x / Terrain.GRID):
			continue
		found += 1
		t.check(tr.collide(p, 3.0) != "", "проба на границе ячейки задевает дерево")
		if found >= 5:
			break
	t.check(found > 0, "нашлись деревья у границы ячеек")


func test_ground_collision_explodes_without_life_loss() -> void:
	var w := _world()
	_tick(w, 1.5)
	var d := w.drone_of(1)
	t.check(d != null, "дрон запущен")
	d.pos = Vector3(0, w.terrain.height_at(0, 0) + 0.2, 0)
	w.events.clear()
	w.step({})
	t.check(w.drone_of(1) == null, "дрон взорвался о землю")
	t.check(w.players[1].lives == 3 and w.players[2].lives == 3, "жизни целы")
	t.check(w.players[1].respawn_t > 2.0, "ждёт перезапуска")


func test_drone_drone_collision_swept() -> void:
	var w := _world()
	_tick(w, 1.5)
	var a := w.drone_of(1)
	var b := w.drone_of(2)
	a.pos = Vector3(0, 150, 0)
	b.pos = Vector3(0, 150, -2.5)
	a.vel = Vector3(0, 0, -40)
	b.vel = Vector3(0, 0, 40)  # за тик пролетят друг сквозь друга
	w.step({})
	t.check(w.drone_of(1) == null and w.drone_of(2) == null, "оба взорвались при встрече")


func test_shelter_hit_costs_life_and_elimination_wins() -> void:
	var w := _world(2, 2)
	_tick(w, 1.5)
	for k in 2:
		_tick(w, 3.5)
		var d := w.drone_of(1)
		t.check(d != null, "у атакующего есть дрон (%d)" % k)
		if d == null:
			return
		d.pos = w.shelter_center(w.players[2]) + Vector3(0, 1.0, 3.0)
		w.step({})
	t.check(w.players[2].lives == 0, "у цели кончились жизни: %d" % w.players[2].lives)
	t.check(w.players[2].eliminated, "цель выбыла")
	t.check(w.finished and w.winner == 1, "победил атакующий")


func test_grace_prevents_double_hit() -> void:
	var w := _world(2, 3)
	_tick(w, 1.5)
	var c := w.shelter_center(w.players[2])
	var d := w.drone_of(1)
	d.pos = c + Vector3(0, 1.0, 2.0)
	w.step({})
	t.check(w.players[2].lives == 2, "минус одна жизнь")
	w.players[2].grace = 1.0
	# Второй взрыв сразу — не считается.
	w.players[1].respawn_t = 0.0
	w.step({})
	var d2 := w.drone_of(1)
	if d2:
		d2.pos = c + Vector3(0, 1.0, 2.0)
		w.step({})
	t.check(w.players[2].lives == 2, "в окне неуязвимости жизнь не снимается")


func test_signal_drops_with_distance_and_terrain() -> void:
	var near := SignalModel.distance_quality(50.0, SimConst.Kind.COPTER)
	var far := SignalModel.distance_quality(900.0, SimConst.Kind.COPTER)
	var plane_far := SignalModel.distance_quality(900.0, SimConst.Kind.PLANE)
	t.check(near > 0.95 and far < 0.35, "сигнал падает с расстоянием: %.2f → %.2f" % [near, far])
	t.check(plane_far > far + 0.3, "у самолёта связь дальше")
	t.check(SignalModel.jam_factor(Vector3.ZERO, [Vector3(10, 0, 0)]) < 0.45, "глушилка режет сигнал вблизи")
	t.check(SignalModel.jam_factor(Vector3.ZERO, [Vector3(500, 0, 0)]) == 1.0, "вдали глушилки нет")
	t.check(SignalModel.input_delay_ticks(0.1) > 5 and SignalModel.input_delay_ticks(0.9) == 0, "задержка управления при слабом сигнале")


func test_no_link_makes_drone_fall() -> void:
	var w := _world()
	_tick(w, 1.5)
	var d := w.drone_of(1)
	# Уводим дрон за горы — связи нет.
	var s := w.shelter_pos(w.players[1])
	d.pos = -s.normalized() * (SimConst.MAP_HALF - 10.0)
	d.pos.y = w.terrain.height_at(d.pos.x, d.pos.z) + 120.0
	d.signal_q = 0.0
	var lost := false
	for i in 90:
		w.step({})
		var dd := w.drone_of(1)
		if dd == null or not dd.control:
			lost = true
			break
	t.check(lost, "без связи 2 с — дрон теряет управление")


func test_turret_locks_high_straight_drone_only() -> void:
	var w := _world()
	_tick(w, 1.5)
	var target := w.shelter_center(w.players[2])
	var d := w.drone_of(1)
	var dir := (Vector3(0, target.y, 0) - target).normalized()
	d.pos = target + dir * 100.0 + Vector3(0, 60, 0)
	d.vel = Vector3.ZERO
	d.angvel = Vector3.ZERO
	var e_high := Defenses.exposure(d, w.terrain.agl(d.pos), target, w.terrain)
	d.pos.y = w.terrain.height_at(d.pos.x, d.pos.z) + 4.0
	var e_low := Defenses.exposure(d, w.terrain.agl(d.pos), target, w.terrain)
	d.pos.y += 60.0
	d.angvel = Vector3(3, 0, 3)
	var e_turn := Defenses.exposure(d, w.terrain.agl(d.pos), target, w.terrain)
	t.check(e_high > 0.4, "высоко и прямо — турель видит: %.2f" % e_high)
	t.check(e_low == 0.0, "на бреющем — нет")
	t.check(e_turn < e_high * 0.3, "манёвр мешает захвату: %.2f" % e_turn)


func test_trap_catches_enemy_and_neutralizes() -> void:
	var w := _world()
	_tick(w, 1.5)
	var c := w.shelter_center(w.players[2])
	var d := w.drone_of(1)
	d.pos = c + Vector3(20, 25, 0)
	d.vel = Vector3(-10, 0, 0)
	t.check(w.trigger_trap(2), "сеть сработала")
	t.check(not w.trigger_trap(2), "перезарядка не даёт повторить")
	w.step({})
	t.check(w.drone_of(1) != null and w.drone_of(1).trapped > 0.0, "дрон в сети")
	_tick(w, 8.0)
	t.check(w.players[2].lives == 3, "запутавшийся дрон не снимает жизнь")


func test_sudden_death_disables_defenses() -> void:
	var w := _world()
	w.time = SimConst.SUDDEN_DEATH_AT - 0.01
	w.step({})
	t.check(w.sudden_death, "внезапная смерть включилась")
	t.check(not w.trigger_trap(1), "сеть отключена")
	t.check(SignalModel.jam_factor(Vector3.ZERO, []) == 1.0, "без глушилок")


func test_stock_limits_spam() -> void:
	var w := _world()
	var p: PlayerSim = w.players[1]
	var spawns := 0
	for i in int(20.0 * SimConst.TICK_RATE):
		var before := p.launched
		w.step({})
		if p.launched > before:
			spawns += 1
			var d := w.drone_of(1)
			d.pos.y = -100.0 # сразу разбиваем
	t.check(spawns <= SimConst.STOCK_MAX + 2, "запас ограничивает запуски за 20 с: %d" % spawns)


func test_full_bot_free_match_progresses() -> void:
	# Без ввода дроны висят над укрытиями — матч не должен падать с ошибками.
	var w := _world(8)
	_tick(w, 10.0)
	t.check(w.drones.size() == 8, "у всех 8 игроков есть дрон: %d" % w.drones.size())


func test_simultaneous_hit_and_crash_of_eliminated_owner() -> void:
	# Дрон Б разбивается в тот же тик, когда взрыв А выбивает Б — ошибки быть не должно.
	var w := _world(3, 1)
	_tick(w, 1.5)
	var a := w.drone_of(1)
	var b := w.drone_of(2)
	a.pos = w.shelter_center(w.players[2]) + Vector3(0, 1.0, 2.0)
	b.pos = Vector3(b.pos.x, w.terrain.height_at(b.pos.x, b.pos.z) - 1.0, b.pos.z)
	w.step({})
	t.check(w.players[2].eliminated, "Б выбыл")
	t.check(w.drone_of(2) == null, "дрон Б убран")
