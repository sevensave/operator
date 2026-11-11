extends Node
## Настройки игрока (автозагрузка «Settings»). Хранятся в user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := ""
var quality := 1            # 0 — низкое, 1 — среднее, 2 — высокое
var fullscreen := true
var vsync := true
var fov := 100.0
var mouse_sens := 1.0
var invert_y := false
var acro := false
var volume := 0.8
var camera_tilt := 18.0
var server_host := ""       # пусто — адрес по умолчанию из net/config.gd
var server_port := 0
var last_kind := 0
var last_style := 0
var show_fps := false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	player_name = str(c.get_value("player", "name", player_name))
	last_kind = int(c.get_value("player", "kind", last_kind))
	last_style = int(c.get_value("player", "style", last_style))
	quality = int(c.get_value("video", "quality", quality))
	fullscreen = bool(c.get_value("video", "fullscreen", fullscreen))
	vsync = bool(c.get_value("video", "vsync", vsync))
	fov = float(c.get_value("video", "fov", fov))
	show_fps = bool(c.get_value("video", "show_fps", show_fps))
	camera_tilt = float(c.get_value("control", "camera_tilt", camera_tilt))
	mouse_sens = float(c.get_value("control", "mouse_sens", mouse_sens))
	invert_y = bool(c.get_value("control", "invert_y", invert_y))
	acro = bool(c.get_value("control", "acro", acro))
	volume = float(c.get_value("audio", "volume", volume))
	server_host = str(c.get_value("net", "host", server_host))
	server_port = int(c.get_value("net", "port", server_port))


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("player", "name", player_name)
	c.set_value("player", "kind", last_kind)
	c.set_value("player", "style", last_style)
	c.set_value("video", "quality", quality)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "vsync", vsync)
	c.set_value("video", "fov", fov)
	c.set_value("video", "show_fps", show_fps)
	c.set_value("control", "camera_tilt", camera_tilt)
	c.set_value("control", "mouse_sens", mouse_sens)
	c.set_value("control", "invert_y", invert_y)
	c.set_value("control", "acro", acro)
	c.set_value("audio", "volume", volume)
	if server_host != "":
		c.set_value("net", "host", server_host)
	if server_port != 0:
		c.set_value("net", "port", server_port)
	c.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if OS.has_feature("editor") or OS.get_environment("OPERATOR_WINDOWED") != "":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## Позывной: 2–16 символов, кириллица/латиница/цифры, пробел, дефис, подчёркивание.
static func clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or (c >= 0x410 and c <= 0x44F) or c == 0x401 or c == 0x451 or ch == " " or ch == "-" or ch == "_"
		if ok:
			if ch == " " and out.ends_with(" "):
				continue
			out += ch
	return out.strip_edges().substr(0, 16)


static func name_valid(n: String) -> bool:
	var c := clean_name(n)
	return c.length() >= 2 and c == n.strip_edges()
