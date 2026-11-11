extends SceneTree
## Замер скорости тика симуляции с ботами: godot --headless --path . -s res://tools/bench.gd
func _initialize() -> void:
	var n := 8
	var w := WorldSim.new()
	var roster := []
	for i in n:
		roster.append({"pid": i + 1, "name": "Б%d" % i, "color": i, "bot": true, "kind": i % 2})
	var t0 := Time.get_ticks_usec()
	w.setup(5, roster, 3)
	print("setup: %d мс" % ((Time.get_ticks_usec() - t0) / 1000))
	var bots := {}
	for i in n:
		bots[i + 1] = BotAI.new(i + 1, 0.7, i)
	var think := 0
	var step := 0
	for k in 900:
		var a := Time.get_ticks_usec()
		var inputs := {}
		for pid in bots:
			inputs[pid] = bots[pid].think(w)
		var b := Time.get_ticks_usec()
		w.step(inputs)
		var c := Time.get_ticks_usec()
		think += b - a
		step += c - b
		w.take_events()
	print("900 тиков: думать %.2f мс/тик, шаг %.2f мс/тик, время матча %.0f с, дронов %d" % [think / 900.0 / 1000.0, step / 900.0 / 1000.0, w.time, w.drones.size()])
	quit()
