extends SceneTree
## Headless-раннер: godot --headless --path . -s res://tests/run_tests.gd
## Запускает все методы test_* из tests/test_*.gd, код выхода 1 при провалах.

var failures := 0
var passed := 0
var _current := ""
var _logger := ErrorCounter.new()


## Ошибки скриптов во время теста тоже считаем провалом.
class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		count += 1


func _initialize() -> void:
	OS.add_logger(_logger)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		if only != "" and not f.contains(only):
			continue
		var script: GDScript = load("res://tests/" + f)
		var inst = script.new()
		inst.set("t", self)
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			_current = f.get_basename() + "." + mname
			var before := failures
			var errs := _logger.count
			var t0 := Time.get_ticks_msec()
			inst.call(mname)
			if _logger.count > errs:
				failures += 1
				printerr("  FAIL %s: ошибки скрипта (%d)" % [_current, _logger.count - errs])
			var ms := Time.get_ticks_msec() - t0
			if failures == before:
				passed += 1
				print("  ok   %s (%d мс)" % [_current, ms])
	print("\nТесты: %d прошли, %d провалов" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("  FAIL %s: %s" % [_current, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (получили %.3f, ждали %.3f ± %.3f)" % [msg, a, b, eps])
