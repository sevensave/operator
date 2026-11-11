extends SceneTree
## Статистика бот-матча: причины взрывов, попадания. godot --headless --path . -s res://tools/bot_stats.gd -- [игроков] [минут] [сид]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 4
	var minutes := float(args[1]) if args.size() > 1 else 4.0
	var seed := int(args[2]) if args.size() > 2 else 23
	var w := WorldSim.new()
	var roster := []
	for i in n:
		roster.append({"pid": i + 1, "name": "Б%d" % i, "color": i, "bot": true, "kind": i % 2})
	w.setup(seed, roster, 3)
	var bots := {}
	for i in n:
		bots[i + 1] = BotAI.new(i + 1, 0.8, seed + i)
	var causes := {}
	var kinds := {}
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
				if OS.get_environment("TRACE") != "" and dd < 70.0 and k % 6 == 0 and d.id < 6:
					var c := w.shelter_center(w.players[b.target_pid])
					print("d%d t=%.1f dist=%.0f rel=(%.0f,%.0f,%.0f) v=%.0f sig=%.2f ctl=%s lock=%.2f agl=%.1f bat=%.2f" % [d.id, w.time, dd, d.pos.x-c.x, d.pos.y-c.y, d.pos.z-c.z, d.vel.length(), d.signal_q, d.control, d.lock, w.terrain.agl(d.pos), d.battery])
		if OS.get_environment("PATHTRACE") != "" and k % 60 == 0:
			var d1 := w.drone_of(1)
			var b1: BotAI = bots[1]
			if d1 and b1.target_pid > 0:
				var c1 := w.shelter_center(w.players[b1.target_pid])
				print("t=%.0f d%d kind=%d dist=%.0f h=%.0f agl=%.1f v=%.0f sig=%.2f ctl=%s bat=%.2f lock=%.2f" % [w.time, d1.id, d1.kind, Vector2(d1.pos.x-c1.x, d1.pos.z-c1.z).length(), d1.pos.y-c1.y, w.terrain.agl(d1.pos), d1.vel.length(), d1.signal_q, d1.control, d1.battery, d1.lock])
		for e in w.take_events():
			if e.t == "boom":
				var key: String = "%s/%s" % [e.cause, SimConst.KIND_NAMES[e.kind]]
				causes[key] = causes.get(key, 0) + 1
			if e.t == "nolink":
				causes["nolink"] = causes.get("nolink", 0) + 1
				var dn: DroneState = w.drones.get(e.id)
				if dn and OS.get_environment("NL") != "":
					var m := w.mast_pos(w.players[dn.owner])
					print("nolink d%d mast=%.0f los=%s jam=%.2f agl=%.1f bat=%.2f kind=%d" % [dn.id, m.distance_to(dn.pos), w.terrain.line_of_sight(m, dn.pos), SignalModel.jam_factor(dn.pos, w.enemy_shelters(dn.owner)), w.terrain.agl(dn.pos), dn.battery, dn.kind])
		if w.finished:
			break
	print("время %.0f с, итог %s" % [w.time, str(w.winner)])
	print(causes)
	var arr := mind.values()
	arr.sort()
	print("мин. дистанция до цели по дронам: ", arr.map(func(x): return int(x)))
	for p in w.players.values():
		print("%d: жизни %d, попаданий %d, запусков %d" % [p.pid, p.lives, p.hits, p.launched])
	quit()
