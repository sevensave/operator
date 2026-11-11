extends RefCounted
## Боты доводят матч до победителя без ошибок.

var t


func _match(n: int, lives: int, seed: int, max_minutes: float) -> WorldSim:
	var w := WorldSim.new()
	var roster := []
	for i in n:
		roster.append({"pid": i + 1, "name": "Бот%d" % i, "color": i, "bot": true, "kind": i % 2})
	w.setup(seed, roster, lives)
	var bots := {}
	for i in n:
		bots[i + 1] = BotAI.new(i + 1, 0.5 + 0.5 * float(i) / n, seed + i)
	var ticks := int(max_minutes * 60.0 * SimConst.TICK_RATE)
	for k in ticks:
		var inputs := {}
		for pid in bots:
			inputs[pid] = bots[pid].think(w)
		w.step(inputs)
		w.take_events()
		if w.finished:
			break
	return w


func test_two_bots_finish() -> void:
	var w := _match(2, 2, 11, 12.0)
	t.check(w.finished, "матч 1×1 завершился за %.0f с" % w.time)
	print("      1×1: %.0f с, победитель %d" % [w.time, w.winner])


func test_four_bots_finish() -> void:
	var w := _match(4, 2, 23, 14.0)
	t.check(w.finished, "матч на 4 завершился, время %.0f с" % w.time)
	var hits := 0
	for p in w.players.values():
		hits += p.hits
	t.check(hits >= 6, "боты попадают по укрытиям: %d" % hits)
	print("      4 бота: %.0f с, попаданий %d, победитель %d" % [w.time, hits, w.winner])


func test_bots_finish_on_every_relief() -> void:
	for r in MapPreset.RELIEF_COUNT:
		var sd := MapPreset.seed_with_relief(300 + r * 11, r)
		var w := _match(4, 1, sd, 14.0)
		var name: String = MapPreset.RELIEF_NAMES[r]
		t.check(w.finished, "%s: матч ботов (коптеры и самолёты) завершился, время %.0f с" % [name, w.time])
		print("      %s: %.0f с, победитель %d" % [name, w.time, w.winner])
