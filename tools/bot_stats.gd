extends SceneTree
## Статистика бот-матчей: причины взрывов, попадания и итоги по типам дронов.
## godot --headless --path . -s res://tools/bot_stats.gd -- [игроков] [минут] [сид] [матчей] [fixed]
## «fixed» — каждый бот летает только своим типом (чётные pid — коптер, нечётные — самолёт),
## иначе боты сами выбирают тип перед вылетом. Матчей больше одного — сиды подряд, сумма по типам.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 4
	var minutes := float(args[1]) if args.size() > 1 else 4.0
	var seed0 := int(args[2]) if args.size() > 2 else 23
	var runs := int(args[3]) if args.size() > 3 else 1
	var fixed := args.size() > 4 and args[4] == "fixed"
	# По типу: вылеты, попадания по укрытиям, сбитые чужие дроны (таран/взрыв), потери от чужих дронов, разбился сам.
	var by_kind := [{}, {}]
	for k in 2:
		by_kind[k] = {"launch": 0, "hit": 0, "kill": 0, "lost_to_drone": 0, "crash": 0, "life_s": 0.0}
	var causes := {}
	var wins := [0, 0]
	for r in runs:
		var seed := seed0 + r * 101
		var w := WorldSim.new()
		var roster := []
		for i in n:
			roster.append({"pid": i + 1, "name": "Б%d" % i, "color": i, "bot": true, "kind": (i + 1) % 2 if fixed else i % 2})
		w.setup(seed, roster, 3)
		var bots := {}
		for i in n:
			bots[i + 1] = BotAI.new(i + 1, 0.8, seed + i)
			bots[i + 1].keep_kind = fixed
		var kind_of := {}   # drone id -> kind
		var born := {}
		var mind := {}
		for k in int(minutes * 60 * SimConst.TICK_RATE):
			var inputs := {}
			for pid in bots:
				inputs[pid] = bots[pid].think(w)
			w.step(inputs)
			for d in w.drones.values():
				var b: BotAI = bots[d.owner]
				if b.target_pid != 0:
					var dd: float = d.pos.distance_to(w.shelter_center(w.players[b.target_pid]))
					mind[d.id] = minf(mind.get(d.id, 1e9), dd)
			var last_kind := {}   # pid -> тип последнего взорвавшегося дрона в этом тике
			for e in w.take_events():
				if e.t == "spawn":
					kind_of[e.id] = e.kind
					born[e.id] = w.time
					by_kind[e.kind].launch += 1
				if e.t == "boom":
					var key: String = "%s/%s" % [e.cause, SimConst.KIND_NAMES[e.kind]]
					causes[key] = causes.get(key, 0) + 1
					last_kind[e.pid] = e.kind
					by_kind[e.kind].life_s += w.time - born.get(e.id, w.time)
					if e.cause == "ram" or e.cause == "blast":
						by_kind[e.kind].lost_to_drone += 1
					elif e.cause in ["ground", "tree", "building", "bounds"]:
						by_kind[e.kind].crash += 1
				if e.t == "hit" and last_kind.has(e.by):
					by_kind[last_kind[e.by]].hit += 1
				if e.t == "ram":
					# a — сбивший при подрыве; при таране оба теряют дрон, засчитываем обоим типам.
					if last_kind.has(e.a):
						by_kind[last_kind[e.a]].kill += 1
					if last_kind.has(e.b) and e.b != e.a:
						by_kind[last_kind[e.b]].kill += 1
				if e.t == "nolink":
					causes["nolink"] = causes.get("nolink", 0) + 1
			if w.finished:
				break
		if w.winner != 0:
			wins[(w.winner) % 2 if fixed else 0] += 1
		var arr := mind.values()
		arr.sort()
		print("сид %d: время %.0f с, победитель %s" % [seed, w.time, str(w.winner)])
		if runs == 1:
			print("мин. дистанция до цели по дронам: ", arr.map(func(x): return int(x)))
			for p in w.players.values():
				print("%d: жизни %d, попаданий %d, запусков %d" % [p.pid, p.lives, p.hits, p.launched])
	print(causes)
	for k in 2:
		var s: Dictionary = by_kind[k]
		var l := maxi(s.launch, 1)
		print("%-8s вылетов %3d · попаданий %3d (%.2f/вылет) · сбил дронов %3d · сбит дронами %3d · разбился %3d · жизнь %.0f с" % [
			SimConst.KIND_NAMES[k], s.launch, s.hit, float(s.hit) / l, s.kill, s.lost_to_drone, s.crash, s.life_s / l])
	if fixed:
		print("победы: коптеры %d, самолёты %d" % [wins[0], wins[1]])
	quit()
