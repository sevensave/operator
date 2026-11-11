class_name Osd
extends Control
## Экранная индикация оператора (OSD) и игровой HUD. Всё рисуется в _draw по данным кадра.

var data := {}          # заполняет MatchView каждый кадр
var feed_lines: Array = []   # [текст, цвет, время]
var big_text := ""
var big_sub := ""
var big_color := Color.WHITE
var show_table := false
var _blink := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func push_line(text: String, color := UiTheme.OSD) -> void:
	feed_lines.append([text, color, 7.0])
	if feed_lines.size() > 6:
		feed_lines.pop_front()


func _process(delta: float) -> void:
	_blink += delta
	for l in feed_lines:
		l[2] -= delta
	while feed_lines.size() > 0 and feed_lines[0][2] <= 0.0:
		feed_lines.pop_front()
	queue_redraw()


func _s(text: String, pos: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, mono := false) -> void:
	var f := UiTheme.mono() if mono else UiTheme.font()
	# Тень для читаемости на любом фоне.
	draw_string(f, pos + Vector2(2, 2), text, align, width, size, Color(0, 0, 0, 0.7 * color.a))
	draw_string(f, pos, text, align, width, size, color)


func _draw() -> void:
	if data.is_empty() or size.y < 100.0:
		return
	var sz := size
	var k := sz.y / 900.0
	var fs := int(20 * k)
	var c := UiTheme.OSD
	var flying: bool = data.get("flying", false)

	# ---- Таймер и режим ----
	var t: float = data.get("time", 0.0)
	_s("%02d:%02d" % [int(t) / 60, int(t) % 60], Vector2(28 * k, 44 * k), int(30 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	if data.get("sudden", false):
		_s("ВНЕЗАПНАЯ СМЕРТЬ — защита отключена", Vector2(28 * k, 74 * k), fs, UiTheme.WARN)
	elif t < SimConst.SUDDEN_DEATH_AT:
		var left := SimConst.SUDDEN_DEATH_AT - t
		if left < 60.0:
			_s("Внезапная смерть через %d с" % int(left), Vector2(28 * k, 74 * k), fs, UiTheme.ACCENT)
	if data.has("ping"):
		_s("пинг %d мс" % int(data.ping), Vector2(28 * k, 100 * k), int(15 * k), UiTheme.DIM)
	if data.has("fps"):
		_s("%d кадр/с" % int(data.fps), Vector2(28 * k, 120 * k), int(15 * k), UiTheme.DIM)

	_draw_players(k)
	_draw_feed(k)

	if flying:
		_draw_instruments(k)
	_draw_bottom(k)

	if big_text != "":
		_s(big_text, Vector2(0, sz.y * 0.36), int(54 * k), big_color, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
		if big_sub != "":
			_s(big_sub, Vector2(0, sz.y * 0.36 + 46 * k), int(24 * k), UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if show_table:
		_draw_table(k)


func _draw_players(k: float) -> void:
	var rows: Array = data.get("players", [])
	var x := size.x - 300 * k
	var y := 30 * k
	for r in rows:
		var col: Color = r.color
		var a := 0.45 if r.out else 1.0
		draw_rect(Rect2(x, y - 15 * k, 10 * k, 18 * k), Color(col, a))
		var name: String = r.name
		if r.me:
			name += " (вы)"
		_s(name, Vector2(x + 18 * k, y), int(18 * k), Color(UiTheme.TEXT, a))
		if r.out:
			_s("выбыл", Vector2(x + 190 * k, y), int(16 * k), Color(UiTheme.DIM, a))
		else:
			for i in r.lives:
				draw_rect(Rect2(x + (190 + i * 16) * k, y - 13 * k, 11 * k, 14 * k), col)
		y += 26 * k


func _draw_feed(k: float) -> void:
	var y := 170 * k
	for l in feed_lines:
		var a := clampf(l[2], 0.0, 1.0)
		_s(l[0], Vector2(28 * k, y), int(18 * k), Color(l[1], a))
		y += 26 * k


func _draw_instruments(k: float) -> void:
	var sz := size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	var c := UiTheme.OSD
	var lw := maxf(1.5, 2.0 * k)

	# Прицел.
	draw_line(Vector2(cx - 18 * k, cy), Vector2(cx - 6 * k, cy), c, lw)
	draw_line(Vector2(cx + 6 * k, cy), Vector2(cx + 18 * k, cy), c, lw)
	draw_line(Vector2(cx, cy - 12 * k), Vector2(cx, cy - 5 * k), c, lw)
	# Искусственный горизонт.
	if data.has("horizon"):
		var h: Array = data.horizon
		var a: Vector2 = h[0]
		var b: Vector2 = h[1]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		if mid.distance_to(Vector2(cx, cy)) < sz.y * 0.4:
			draw_line(mid - dir * 140 * k, mid - dir * 50 * k, Color(c, 0.8), lw)
			draw_line(mid + dir * 50 * k, mid + dir * 140 * k, Color(c, 0.8), lw)

	# Компас.
	var heading: float = data.get("heading", 0.0)
	var cw := 520.0 * k
	var top := 34.0 * k
	draw_line(Vector2(cx - cw / 2, top + 16 * k), Vector2(cx + cw / 2, top + 16 * k), Color(c, 0.5), 1.0)
	var deg_px := cw / 120.0
	for d in range(-60, 61, 5):
		var hd := int(round(heading)) / 5 * 5 + d
		var x := cx + (hd - heading) * deg_px
		if absf(x - cx) > cw / 2:
			continue
		var hn := posmod(hd, 360)
		var tick := 6.0 if hn % 15 != 0 else 12.0
		draw_line(Vector2(x, top + 16 * k), Vector2(x, top + (16 - tick) * k), Color(c, 0.7), 1.0)
		if hn % 45 == 0:
			var names := {0: "С", 45: "СВ", 90: "В", 135: "ЮВ", 180: "Ю", 225: "ЮЗ", 270: "З", 315: "СЗ"}
			_s(names[hn], Vector2(x - 20 * k, top - 2 * k), int(16 * k), c, HORIZONTAL_ALIGNMENT_CENTER, 40 * k)
	draw_line(Vector2(cx, top + 18 * k), Vector2(cx, top + 26 * k), UiTheme.ACCENT, 2.0)
	for m in data.get("marks", []):
		var rel := wrapf(m.bearing - heading, -180.0, 180.0)
		var x := cx + clampf(rel, -60.0, 60.0) * deg_px
		var col: Color = m.color
		var y := top + 30 * k
		var pts := PackedVector2Array([Vector2(x, y - 7 * k), Vector2(x - 6 * k, y + 4 * k), Vector2(x + 6 * k, y + 4 * k)])
		if m.home:
			draw_rect(Rect2(x - 5 * k, y - 5 * k, 10 * k, 10 * k), col, false, 2.0)
		else:
			draw_colored_polygon(pts, col)
		if absf(rel) < 60.0:
			_s("%s %d" % [m.label, int(m.dist)], Vector2(x - 60 * k, y + 22 * k), int(14 * k), Color(col, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 120 * k)

	# Метки целей в мире (проекция на экран).
	for m in data.get("screen_marks", []):
		var p: Vector2 = m.pos
		var col: Color = m.color
		draw_arc(p, 14 * k, 0, TAU, 20, col, 2.0)
		_s("%s  %d м" % [m.label, int(m.dist)], p + Vector2(18 * k, 5 * k), int(15 * k), col)

	# Левый блок: связь, АКБ, ветер.
	var lx := 40.0 * k
	var by := sz.y - 150 * k
	var q: float = data.get("signal", 1.0)
	_s("СВЯЗЬ", Vector2(lx, by), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	for i in 5:
		var on := q > (i + 0.5) / 5.0
		var col := c if q > 0.35 else UiTheme.WARN
		draw_rect(Rect2(lx + (78 + i * 13) * k, by - (4 + i * 4) * k, 9 * k, (6 + i * 4) * k), Color(col, 1.0 if on else 0.2))
	_s("%d%%" % int(q * 100), Vector2(lx + 150 * k, by), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var bat: float = data.get("battery", 1.0)
	var bcol := c if bat > 0.2 else UiTheme.WARN
	_s("АКБ", Vector2(lx, by + 30 * k), int(17 * k), bcol, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	draw_rect(Rect2(lx + 78 * k, by + 16 * k, 70 * k, 16 * k), bcol, false, 1.5)
	draw_rect(Rect2(lx + 80 * k, by + 18 * k, 66 * k * bat, 12 * k), bcol)
	_s("%d%%" % int(bat * 100), Vector2(lx + 156 * k, by + 30 * k), int(17 * k), bcol, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var wind: Vector2 = data.get("wind", Vector2.ZERO)   # в осях камеры: x — вправо, y — вперёд
	_s("ВЕТЕР %d м/с" % int(wind.length()), Vector2(lx, by + 60 * k), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var wc := Vector2(lx + 175 * k, by + 54 * k)
	if wind.length() > 0.3:
		var wd := Vector2(wind.x, -wind.y).normalized()
		draw_line(wc - wd * 10 * k, wc + wd * 10 * k, c, 2.0)
		draw_line(wc + wd * 10 * k, wc + wd * 4 * k + wd.orthogonal() * 5 * k, c, 2.0)
		draw_line(wc + wd * 10 * k, wc + wd * 4 * k - wd.orthogonal() * 5 * k, c, 2.0)

	# Правый блок: скорость, высота, тип.
	var rx := sz.x - 260 * k
	_s("СКОР %3d км/ч" % int(data.get("speed", 0.0) * 3.6), Vector2(rx, by), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_s("ВЫС  %3d м" % int(data.get("agl", 0.0)), Vector2(rx, by + 30 * k), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_s("%s · %s" % [data.get("kind_name", ""), "АКРО" if data.get("acro", false) else "АРКАДА"], Vector2(rx, by + 60 * k), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)

	# Предупреждения.
	var warns: Array = data.get("warnings", [])
	var wy := cy + 90 * k
	var blink_on := fmod(_blink, 0.6) < 0.4
	for w in warns:
		var col: Color = UiTheme.WARN if w[1] else UiTheme.ACCENT
		if w[1] and not blink_on:
			col.a = 0.35
		_s(w[0], Vector2(0, wy), int(24 * k), col, HORIZONTAL_ALIGNMENT_CENTER, sz.x, true)
		wy += 30 * k


func _draw_bottom(k: float) -> void:
	var sz := size
	var c := UiTheme.OSD
	var y := sz.y - 34 * k
	var stock: int = data.get("stock", 0)
	var x := sz.x * 0.5 - 330 * k
	_s("ДРОНЫ", Vector2(x, y), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	for i in SimConst.STOCK_MAX:
		draw_rect(Rect2(x + (72 + i * 18) * k, y - 14 * k, 13 * k, 15 * k), Color(c, 1.0 if i < stock else 0.2))
	if stock < SimConst.STOCK_MAX:
		_s("+1 через %d с" % int(ceil(data.get("regen", 0.0))), Vector2(x + 132 * k, y), int(15 * k), UiTheme.DIM)
	_s("[1/2] след.: %s" % data.get("next_kind", ""), Vector2(x + 250 * k, y), int(17 * k), c)
	var trap: float = data.get("trap_cd", 0.0)
	var trap_txt := "[F] сеть: готова" if trap <= 0.0 else "[F] сеть: %d с" % int(ceil(trap))
	if data.get("sudden", false):
		trap_txt = "[F] сеть: отключена"
	_s(trap_txt, Vector2(x + 470 * k, y), int(17 * k), UiTheme.ACCENT if trap <= 0.0 else UiTheme.DIM)


func _draw_table(k: float) -> void:
	var rows: Array = data.get("players", [])
	var w := 640 * k
	var h := (90 + rows.size() * 34) * k
	var r := Rect2((size.x - w) / 2, (size.y - h) / 2, w, h)
	draw_rect(r, Color(0.05, 0.06, 0.06, 0.88))
	draw_rect(r, Color(UiTheme.ACCENT, 0.6), false, 1.5)
	var y := r.position.y + 40 * k
	_s("Оператор", Vector2(r.position.x + 24 * k, y), int(18 * k), UiTheme.DIM)
	_s("Жизни", Vector2(r.position.x + 300 * k, y), int(18 * k), UiTheme.DIM)
	_s("Попадания", Vector2(r.position.x + 390 * k, y), int(18 * k), UiTheme.DIM)
	_s("Тараны", Vector2(r.position.x + 520 * k, y), int(18 * k), UiTheme.DIM)
	y += 38 * k
	for row in rows:
		draw_rect(Rect2(r.position.x + 24 * k, y - 15 * k, 10 * k, 18 * k), row.color)
		_s(row.name + (" (бот)" if row.bot else ""), Vector2(r.position.x + 42 * k, y), int(19 * k), UiTheme.TEXT)
		_s("—" if row.out else str(row.lives), Vector2(r.position.x + 300 * k, y), int(19 * k), UiTheme.TEXT)
		_s(str(row.hits), Vector2(r.position.x + 390 * k, y), int(19 * k), UiTheme.TEXT)
		_s(str(row.rams), Vector2(r.position.x + 520 * k, y), int(19 * k), UiTheme.TEXT)
		y += 34 * k
