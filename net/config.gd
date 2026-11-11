class_name NetConfig
## Адрес игрового сервера. Порядок: переменная окружения OPERATOR_SERVER («хост» или «хост:порт»),
## затем user://settings.cfg ([net] host/port), затем значения по умолчанию ниже.

## Адрес выделенного сервера (хост nether). Локально перекрывается OPERATOR_SERVER или настройками.
const DEFAULT_HOST := "150.251.139.13"
const DEFAULT_PORT := 27630
const PROTOCOL_VERSION := 2
const GAME_VERSION := "0.3.0"


static func host() -> String:
	var env := OS.get_environment("OPERATOR_SERVER")
	if env != "":
		return env.split(":")[0]
	var s := _settings()
	if s != null and str(s.get("server_host")) != "":
		return str(s.get("server_host"))
	return DEFAULT_HOST


static func port() -> int:
	var env := OS.get_environment("OPERATOR_SERVER")
	if env.contains(":"):
		return int(env.split(":")[1])
	var s := _settings()
	if s != null and int(s.get("server_port")) > 0:
		return int(s.get("server_port"))
	return DEFAULT_PORT


static func server_port() -> int:
	var env := OS.get_environment("OPERATOR_PORT")
	if env != "":
		return int(env)
	return DEFAULT_PORT


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Settings")
