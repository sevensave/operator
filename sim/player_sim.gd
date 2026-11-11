class_name PlayerSim
extends RefCounted
## Состояние оператора в матче.

var pid := 0
var name := ""
var color := 0
var shelter := 0
var style := 0
var model := 0     # вариант внешнего вида дрона (0..MODEL_COUNT-1), в снапшот не идёт
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


func write(b: StreamPeerBuffer) -> void:
	b.put_32(pid)
	b.put_8(clampi(lives, -1, 100))
	b.put_u8(stock)
	b.put_u8(int(clampf(respawn_t, 0, 25) * 10))
	b.put_u16(drone_id & 0xFFFF)
	b.put_u8(1 if eliminated else 0)
	b.put_u8(place)
	b.put_u8(int(clampf(trap_cd, 0, 50) * 5))
	b.put_u8(int(clampf(trap_t, 0, 25) * 10))
	b.put_u8(mini(hits, 255))
	b.put_u8(mini(rams, 255))
	b.put_u8(kind)
	b.put_u8(int(clampf(regen_t, 0, 25) * 10))
	b.put_u8(int(clampf(grace, 0, 25) * 10))


## Читает запись игрока из буфера и возвращает pid (данные кладёт в self).
func read(b: StreamPeerBuffer) -> void:
	pid = b.get_32()
	lives = b.get_8()
	stock = b.get_u8()
	respawn_t = b.get_u8() / 10.0
	drone_id = b.get_u16()
	eliminated = b.get_u8() != 0
	place = b.get_u8()
	trap_cd = b.get_u8() / 5.0
	trap_t = b.get_u8() / 10.0
	hits = b.get_u8()
	rams = b.get_u8()
	kind = b.get_u8()
	regen_t = b.get_u8() / 10.0
	grace = b.get_u8() / 10.0


func copy_net(o: PlayerSim) -> void:
	lives = o.lives
	stock = o.stock
	respawn_t = o.respawn_t
	drone_id = o.drone_id
	eliminated = o.eliminated
	place = o.place
	trap_cd = o.trap_cd
	trap_t = o.trap_t
	hits = o.hits
	rams = o.rams
	kind = o.kind
	regen_t = o.regen_t
	grace = o.grace


func info() -> Dictionary:
	return {"pid": pid, "name": name, "color": color, "shelter": shelter, "style": style, "model": model, "kind": kind, "bot": bot}
