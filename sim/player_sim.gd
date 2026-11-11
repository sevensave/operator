class_name PlayerSim
extends RefCounted
## Состояние оператора в матче.

var pid := 0
var name := ""
var color := 0
var shelter := 0
var style := 0
var kind := SimConst.Kind.COPTER   # какой дрон запускать следующим
var bot := false

var lives := 3
var stock := SimConst.STOCK_MAX
var regen_t := 0.0
var respawn_t := 0.0
var drone_id := 0
var eliminated := false
var place := 0
var grace := 0.0
var trap_cd := 0.0
var trap_t := 0.0
var hits := 0       # сколько жизней снял у других
var rams := 0       # сколько дронов перехватил
var launched := 0


func to_array() -> Array:
	return [pid, lives, stock, snappedf(respawn_t, 0.1), drone_id, eliminated, place,
		snappedf(trap_cd, 0.1), snappedf(trap_t, 0.1), hits, rams, kind, snappedf(regen_t, 0.1), snappedf(grace, 0.1)]


func apply_array(a: Array) -> void:
	lives = int(a[1])
	stock = int(a[2])
	respawn_t = float(a[3])
	drone_id = int(a[4])
	eliminated = bool(a[5])
	place = int(a[6])
	trap_cd = float(a[7])
	trap_t = float(a[8])
	hits = int(a[9])
	rams = int(a[10])
	kind = int(a[11])
	regen_t = float(a[12])
	grace = float(a[13])


func info() -> Dictionary:
	return {"pid": pid, "name": name, "color": color, "shelter": shelter, "style": style, "kind": kind, "bot": bot}
