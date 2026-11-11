extends Node
## Точка входа. Флаги (после «--»):
##   --server [--port=N]   выделенный сервер (headless)
##   --training            сразу тренировка с ботами
##   --shot=путь.png --shot-at=сек   сохранить скриншот и выйти (для проверки графики)
##   --screen=training               сразу открыть экран меню (show_<имя> в ui/app.gd)

var _shot_path := ""
var _shot_at := 0.0
var _t := 0.0


func _ready() -> void:
	var args := _args()
	if args.has("server") or DisplayServer.get_name() == "headless" and not args.has("client"):
		var srv: Node = load("res://server/server_main.gd").new()
		srv.name = "Server"
		add_child(srv)
		return
	get_tree().root.theme = UiTheme.theme()
	if args.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if args.has("quality"):
		Settings.quality = int(args.quality)
	_shot_path = args.get("shot", "")
	_shot_at = float(args.get("shot-at", "8"))
	var app: Node = load("res://ui/app.gd").new()
	app.name = "App"
	add_child(app)
	if args.has("training"):
		app.call_deferred("start_training", int(args.get("bots", "5")))
	elif args.has("screen") and app.has_method("show_" + str(args.screen)):   # для скриншотов экранов меню
		app.call_deferred("show_" + str(args.screen))


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			out[s.substr(0, i)] = s.substr(i + 1)
		else:
			out[s] = ""
	return out


func _process(delta: float) -> void:
	if _shot_path == "":
		return
	_t += delta
	if _t >= _shot_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("screenshot: ", _shot_path, "  fps: ", Engine.get_frames_per_second(), "  draw calls: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"  primitives: ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		_shot_path = ""
		get_tree().quit()
