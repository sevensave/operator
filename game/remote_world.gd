class_name RemoteWorld
extends WorldSim
## Зеркало матча по снапшотам для автопилота (бот за клиента): действия уходят на сервер.

var client


func sync_from(feed: FeedNet) -> void:
	terrain = feed.terrain
	players = feed.players
	seed = feed.world.seed
	time = feed.match_time()
	sudden_death = feed.sudden_death()
	drones = feed.latest_drones()


func detonate(_pid: int) -> void:
	client.send(Proto.ACTION, {"a": "detonate"})


func trigger_trap(_pid: int) -> bool:
	client.send(Proto.ACTION, {"a": "trap"})
	return true


func set_kind(_pid: int, kind: int) -> void:
	client.send(Proto.ACTION, {"a": "kind", "v": kind})
