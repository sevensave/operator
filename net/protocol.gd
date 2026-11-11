class_name Proto
## Сообщения клиент ↔ сервер. Пакет — var_to_bytes([тип, данные]) без объектов.
## Сервер не доверяет данным клиента: всё проверяется в server/server_main.gd и room.gd.

enum {
	# клиент → сервер
	HELLO = 1,      # {name, ver}
	LIST,           # {}
	CREATE,         # {title, public, slots, lives, bots}
	JOIN,           # {code}
	LEAVE,          # {}
	READY,          # {ready}
	LOADOUT,        # {style, kind, model}
	CHAT,           # {text}
	START,          # {}
	KICK,           # {pid}
	SETTINGS,       # {title, public, slots, lives, bots}
	INPUT,          # [[seq, thr, pitch, roll, yaw, flags], ...] (ненадёжно)
	ACTION,         # {a: "trap"|"detonate"|"kind", v}
	PING,           # {t}
	RENAME,         # {name}
	# сервер → клиент
	WELCOME = 40,   # {id, name, motd}
	ROOMS,          # [{code, title, host, players, slots, status}]
	ROOM,           # полное состояние лобби
	CHAT_MSG,       # {from, name, text, color}
	ERROR,          # {text}
	MATCH_START,    # {seed, roster, lives, me}
	SNAP,           # [tick, time, flags, drones, players, acks] (ненадёжно)
	EVENTS,         # [событие, ...]
	MATCH_END,      # {winner, table}
	PONG,           # {t}
	KICKED,         # {text}
}

const MAX_PACKET := 4096
const MAX_CHAT := 200
const CODE_LEN := 6


static func pack(type: int, payload) -> PackedByteArray:
	return var_to_bytes([type, payload])


## Возвращает [тип, данные] или [] для мусора.
static func unpack(data: PackedByteArray) -> Array:
	if data.size() < 4 or data.size() > MAX_PACKET * 8:
		return []
	var v = bytes_to_var(data)   # без объектов: allow_objects = false по умолчанию
	if typeof(v) != TYPE_ARRAY or v.size() != 2 or typeof(v[0]) != TYPE_INT:
		return []
	return v


static func dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func clean_text(s, max_len: int) -> String:
	if typeof(s) != TYPE_STRING:
		return ""
	var out := ""
	for ch: String in s.strip_edges():
		var c: int = ch.unicode_at(0)
		if c >= 32 and c != 127:
			out += ch
	return out.substr(0, max_len)
