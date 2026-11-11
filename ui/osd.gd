class_name Osd
extends Control
## Экранная индикация оператора (OSD) и игровой HUD. Всё рисуется в _draw по данным кадра.
## Каждый блок лежит на тёмной подложке — читается и на снегу, и на небе.

var data := {}          # заполняет MatchView каждый кадр
var feed_lines: Array = []   # [текст, цвет, время]
var big_text := ""
var big_sub := ""
var big_color := Color.WHITE
var show_table := false
var _blink := 0.0
var _plate_sb := StyleBoxFlat.new()
var _k := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate_sb.anti_aliasing_size = 0.8


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


# ---------- Примитивы ----------

func _s(text: String, pos: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, f: Font = null) -> void:
	if f == null:
		f = UiTheme.font()
	# Тень для читаемости на любом фоне.
	draw_string(f, pos + Vector2(1.5, 1.5) * _k, text, align, width, size, Color(0, 0, 0, 0.75 * color.a))
	draw_string(f, pos, text, align, width, size, color)


func _w(text: String, size: int, f: Font = null) -> float:
	if f == null:
		f = UiTheme.font()
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _plate(r: Rect2, alpha := 1.0, stripe := Color(0, 0, 0, 0)) -> void:
	_plate_sb.bg_color = Color(UiTheme.PLATE, UiTheme.PLATE.a * alpha)
	_plate_sb.set_corner_radius_all(int(6 * _k))
	draw_style_box(_plate_sb, r)
	if stripe.a > 0.0:
		draw_rect(Rect2(r.position.x, r.position.y + 5 * _k, 3 * _k, r.size.y - 10 * _k), stripe)


func _kick(text: String, pos: Vector2, color := UiTheme.DIM) -> void:
	_s(text, pos, int(12 * _k), color, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.caps())


func _pip(r: Rect2, color: Color, on: bool) -> void:
	draw_rect(r, Color(color, 1.0 if on else 0.22))


# ---------- Кадр ----------

func _draw() -> void:
	if data.is_empty() or size.y < 100.0:
		return
	var sz := size
	var k := sz.y / 900.0
	_k = k
	var flying: bool = data.get("flying", false)

	_draw_clock(k)
	_draw_players(k)
	_draw_feed(k)
	_draw_targets(k)
	if flying:
		_draw_instruments(k)
		_draw_lock(k)
	_draw_warnings(k)
	_draw_bottom(k)

	if big_text != "":
		var bs := int(52 * k)
		var tw := maxf(_w(big_text, bs, UiTheme.bold()), _w(big_sub, int(20 * k))) + 90 * k
		var h := (118 if big_sub != "" else 84) * k
		var r := Rect2((sz.x - tw) / 2, sz.y * 0.3, tw, h)
		_plate(r)
		draw_rect(Rect2(r.position.x + 24 * k, r.position.y, tw - 48 * k, 2 * k), big_color)
		_s(big_text, Vector2(0, r.position.y + 58 * k), bs, big_color, HORIZONTAL_ALIGNMENT_CENTER, sz.x, UiTheme.bold())
		if big_sub != "":
			_s(big_sub, Vector2(0, r.position.y + 94 * k), int(20 * k), UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if show_table:
		_draw_table(k)


func _draw_clock(k: float) -> void:
	var t: float = data.get("time", 0.0)
	var sub := []
	if data.has("ping"):
		sub.append("пинг %d мс" % int(data.ping))
	if data.has("fps"):
		sub.append("%d к/с" % int(data.fps))
	var r := Rect2(24 * k, 20 * k, 150 * k, (74 if not sub.is_empty() else 54) * k)
	_plate(r)
	_s("%02d:%02d" % [int(t) / 60, int(t) % 60], r.position + Vector2(16 * k, 39 * k), int(32 * k), UiTheme.OSD, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
	if not sub.is_empty():
		_s(" · ".join(sub), r.position + Vector2(16 * k, 62 * k), int(13 * k), UiTheme.DIM)
	var note := ""
	var ncol := UiTheme.ACCENT
	if data.get("sudden", false):
		note = "ВНЕЗАПНАЯ СМЕРТЬ — защита отключена"
		ncol = UiTheme.WARN
	elif t < SimConst.SUDDEN_DEATH_AT and SimConst.SUDDEN_DEATH_AT - t < 60.0:
		note = "Внезапная смерть через %d с" % int(SimConst.SUDDEN_DEATH_AT - t)
	if note != "":
		var nr := Rect2(r.end.x + 8 * k, r.position.y, _w(note, int(16 * k)) + 28 * k, 34 * k)
		_plate(nr, 1.0, ncol)
		_s(note, nr.position + Vector2(16 * k, 23 * k), int(16 * k), ncol)


func _draw_players(k: float) -> void:
	var rows: Array = data.get("players", [])
	if rows.is_empty():
		return
	var w := 268 * k
	var rh := 27 * k
	var r := Rect2(size.x - w - 24 * k, 20 * k, w, rows.size() * rh + 14 * k)
	_plate(r)
	var y := r.position.y + 7 * k
	for row in rows:
		var col: Color = row.color
		var a := 0.45 if row.out else 1.0
		if row.me:
			draw_rect(Rect2(r.position.x, y, w, rh), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(r.position.x + 12 * k, y + 5 * k, 4 * k, rh - 10 * k), Color(col, a))
		_s(row.name, Vector2(r.position.x + 26 * k, y + 19 * k), int(16 * k), Color(UiTheme.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, 150 * k,
			UiTheme.bold() if row.me else UiTheme.font())
		if row.out:
			_kick("выбыл", Vector2(r.end.x - 62 * k, y + 18 * k), Color(UiTheme.DIM, 0.8))
		else:
			for i in row.lives:
				draw_rect(Rect2(r.end.x - (24 + i * 13) * k, y + 8 * k, 9 * k, 11 * k), col)
		y += rh


func _draw_feed(k: float) -> void:
	var y := 112 * k
	var fs := int(16 * k)
	for l in feed_lines:
		var a := clampf(l[2], 0.0, 1.0)
		var r := Rect2(24 * k, y, _w(l[0], fs) + 26 * k, 26 * k)
		_plate(r, a * 0.85)
		_s(l[0], r.position + Vector2(13 * k, 19 * k), fs, Color(l[1], a))
		y += 30 * k


## Чужие дроны: рамка цвета стороны, дистанция, точка упреждения; за краем экрана — стрелка.
## Захваченная цель — ромб с кольцом и сплошной линией к точке встречи, кандидат — метка [R].
func _draw_targets(k: float) -> void:
	var fast := fmod(_blink, 0.24) < 0.12
	for m in data.get("targets", []):
		var p: Vector2 = m.pos
		var col: Color = m.color
		var dist: float = m.dist
		if not m.on:
			var dir: Vector2 = m.dir
			var side := dir.orthogonal()
			var tip := p + dir * 12 * k
			draw_colored_polygon(PackedVector2Array([tip, p - dir * 8 * k + side * 11 * k, p - dir * 2 * k, p - dir * 8 * k - side * 11 * k]), col)
			_s("%d" % int(dist), p - dir * 30 * k + Vector2(-30 * k, 5 * k), int(14 * k), col, HORIZONTAL_ALIGNMENT_CENTER, 60 * k, UiTheme.mono())
			continue
		var hot: bool = m.hot
		var locked: bool = m.get("locked", false)
		var c := Color.WHITE if (hot and fast) else col
		var s := clampf(1100.0 / maxf(dist, 1.0), 13.0, 46.0) * k
		var g := s * 0.45
		var lw := maxf(2.0, (3.0 if hot else 2.0) * k)
		if locked:
			_draw_lock_frame(p, s, c, lw, k)
		elif m.get("cand", false):
			var tag := "[R]"
			var tr := Rect2(p.x + s + 6 * k, p.y - 11 * k, _w(tag, int(14 * k), UiTheme.bold()) + 12 * k, 22 * k)
			_plate(tr, 0.85)
			_s(tag, tr.position + Vector2(6 * k, 16 * k), int(14 * k), UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.bold())
		for sx: float in ([] if locked else [-1.0, 1.0]):
			for sy: float in [-1.0, 1.0]:
				var corner := p + Vector2(sx, sy) * s
				draw_line(corner + Vector2(0, 1.5 * sy), corner - Vector2(sx * g, 0) + Vector2(0, 1.5 * sy), Color(0, 0, 0, 0.6), lw + 2.0)
				draw_line(corner, corner - Vector2(sx * g, 0), c, lw)
				draw_line(corner, corner - Vector2(0, sy * g), c, lw)
		if hot:
			draw_arc(p, s * 1.5, 0, TAU, 28, c, lw)
		var txt := "%s  %d м" % [m.label, int(dist)]
		_s(txt, Vector2(p.x - 100 * k, p.y - s - 8 * k), int(14 * k), col, HORIZONTAL_ALIGNMENT_CENTER, 200 * k, UiTheme.bold())
		if m.has("lead") and locked:
			var lp: Vector2 = m.lead
			var lc := UiTheme.ACCENT
			if lp.distance_to(p) > s * 0.6:
				draw_line(p + (lp - p).normalized() * s * 0.6, lp, Color(0, 0, 0, 0.5), 4.0)
				draw_line(p + (lp - p).normalized() * s * 0.6, lp, lc, 2.0)
			var d := 8.0 * k
			draw_circle(lp, 2.5 * k, lc)
			draw_arc(lp, d, 0, TAU, 20, Color(0, 0, 0, 0.5), 4.0)
			draw_arc(lp, d, 0, TAU, 20, lc, 2.0)
		elif m.has("lead"):
			var lp: Vector2 = m.lead
			if lp.distance_to(p) > s * 0.8:
				draw_line(p + (lp - p).normalized() * s * 0.5, lp, Color(col, 0.55), 1.5)
				var d := 6.0 * k
				draw_polyline(PackedVector2Array([lp + Vector2(0, -d), lp + Vector2(d, 0), lp + Vector2(0, d), lp + Vector2(-d, 0), lp + Vector2(0, -d)]), col, 2.0)


## Рамка захваченной цели: двойное кольцо с вращающимися засечками внутрь —
## не путается ни с обычной рамкой, ни с ромбом укрытия.
func _draw_lock_frame(p: Vector2, s: float, c: Color, lw: float, k: float) -> void:
	var r := s * 1.2
	for col: Color in [Color(0, 0, 0, 0.6), c]:
		var w := lw + (2.0 if col.a < 0.99 else 0.0)
		draw_arc(p, r, 0, TAU, 36, col, w)
	draw_arc(p, r + 6 * k, 0, TAU, 36, Color(UiTheme.ACCENT, 0.7), maxf(1.0, k))
	var a0 := _blink * 1.6
	for i in 4:
		var dir := Vector2.from_angle(a0 + i * TAU / 4.0)
		draw_line(p + dir * (r + 12 * k), p + dir * (r - 7 * k), Color(0, 0, 0, 0.6), lw + 2.0)
		draw_line(p + dir * (r + 12 * k), p + dir * (r - 7 * k), UiTheme.ACCENT, lw)


## Плашка автозахвата под прицелом.
func _draw_lock(k: float) -> void:
	if not data.has("lock"):
		return
	var lk: Dictionary = data.lock
	var fs := int(17 * k)
	var txt := "АВТОЗАХВАТ · %s · %d м · [R] отмена" % [lk.name, int(lk.dist)]
	var tw := _w(txt, fs, UiTheme.caps()) + 40 * k
	var r := Rect2((size.x - tw) / 2, size.y * 0.5 + 52 * k, tw, 32 * k)
	_plate(r, 1.0, lk.color)
	_s(txt, Vector2(r.position.x + 22 * k, r.position.y + 22 * k), fs, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.caps())


func _draw_instruments(k: float) -> void:
	var sz := size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.5
	var c := UiTheme.OSD
	var lw := maxf(1.5, 2.0 * k)
	var sh := Color(0, 0, 0, 0.5)

	# Прицел.
	for o: Vector2 in [Vector2(1.5, 1.5), Vector2.ZERO]:
		var cc := sh if o != Vector2.ZERO else c
		draw_line(Vector2(cx - 22 * k, cy) + o, Vector2(cx - 8 * k, cy) + o, cc, lw)
		draw_line(Vector2(cx + 8 * k, cy) + o, Vector2(cx + 22 * k, cy) + o, cc, lw)
		draw_line(Vector2(cx, cy - 14 * k) + o, Vector2(cx, cy - 6 * k) + o, cc, lw)
		draw_circle(Vector2(cx, cy) + o, 1.6 * k, cc)
	# Искусственный горизонт.
	if data.has("horizon"):
		var h: Array = data.horizon
		var a: Vector2 = h[0]
		var b: Vector2 = h[1]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		if mid.distance_to(Vector2(cx, cy)) < sz.y * 0.4:
			for sgn: float in [-1.0, 1.0]:
				draw_line(mid + dir * 56 * k * sgn + Vector2(1.5, 1.5), mid + dir * 150 * k * sgn + Vector2(1.5, 1.5), sh, lw)
				draw_line(mid + dir * 56 * k * sgn, mid + dir * 150 * k * sgn, Color(c, 0.85), lw)
				draw_line(mid + dir * 56 * k * sgn, mid + dir * 56 * k * sgn + dir.orthogonal() * 7 * k, Color(c, 0.85), lw)

	# Компас.
	var heading: float = data.get("heading", 0.0)
	var cw := 520.0 * k
	var top := 20.0 * k
	_plate(Rect2(cx - cw / 2 - 16 * k, top, cw + 32 * k, 46 * k))
	var base := top + 38 * k
	var deg_px := cw / 120.0
	var names := {0: "С", 45: "СВ", 90: "В", 135: "ЮВ", 180: "Ю", 225: "ЮЗ", 270: "З", 315: "СЗ"}
	for d in range(-60, 61, 5):
		var hd := int(round(heading)) / 5 * 5 + d
		var x := cx + (hd - heading) * deg_px
		if absf(x - cx) > cw / 2:
			continue
		var hn := posmod(hd, 360)
		var tick := 5.0 if hn % 15 != 0 else 10.0
		draw_line(Vector2(x, base), Vector2(x, base - tick * k), Color(c, 0.55 if hn % 15 != 0 else 0.9), 1.0)
		if hn % 45 == 0:
			_s(names[hn], Vector2(x - 20 * k, top + 21 * k), int(15 * k), UiTheme.ACCENT if hn % 90 == 0 else c, HORIZONTAL_ALIGNMENT_CENTER, 40 * k, UiTheme.bold())
	draw_colored_polygon(PackedVector2Array([Vector2(cx, base - 3 * k), Vector2(cx - 6 * k, base + 7 * k), Vector2(cx + 6 * k, base + 7 * k)]), UiTheme.ACCENT)
	for m in data.get("marks", []):
		var rel := wrapf(m.bearing - heading, -180.0, 180.0)
		var x := cx + clampf(rel, -60.0, 60.0) * deg_px
		var col: Color = m.color
		var y := top + 60 * k
		if m.home:
			draw_rect(Rect2(x - 5 * k, y - 5 * k, 10 * k, 10 * k), col, false, 2.0)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - 7 * k), Vector2(x - 6 * k, y + 4 * k), Vector2(x + 6 * k, y + 4 * k)]), col)
		if absf(rel) < 60.0:
			_s("%s %d" % [m.label, int(m.dist)], Vector2(x - 60 * k, y + 21 * k), int(13 * k), col, HORIZONTAL_ALIGNMENT_CENTER, 120 * k)

	# Метки укрытий в мире (проекция на экран).
	for m in data.get("screen_marks", []):
		var p: Vector2 = m.pos
		var col: Color = m.color
		var d := 11.0 * k
		var pts := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)])
		draw_polyline(pts, Color(0, 0, 0, 0.5), 4.0)
		draw_polyline(pts, col, 2.0)
		_s("%s  %d м" % [m.label, int(m.dist)], p + Vector2(17 * k, 5 * k), int(14 * k), col)

	# Левый блок: связь, АКБ, ветер.
	var lr := Rect2(24 * k, sz.y - 142 * k, 268 * k, 118 * k)
	_plate(lr)
	var lx := lr.position.x + 16 * k
	var vx := lr.end.x - 16 * k
	var row := lr.position.y + 30 * k
	var q: float = data.get("signal", 1.0)
	var qcol := c if q > 0.35 else UiTheme.WARN
	_kick("СВЯЗЬ", Vector2(lx, row))
	for i in 5:
		var on := q > (i + 0.5) / 5.0
		draw_rect(Rect2(lx + (74 + i * 12) * k, row - (3 + i * 3) * k, 8 * k, (5 + i * 3) * k), Color(qcol, 1.0 if on else 0.22))
	_s("%d%%" % int(q * 100), Vector2(vx - 70 * k, row + 1 * k), int(18 * k), qcol, HORIZONTAL_ALIGNMENT_RIGHT, 70 * k, UiTheme.mono())
	row += 33 * k
	var bat: float = data.get("battery", 1.0)
	var bcol := c if bat > 0.2 else UiTheme.WARN
	_kick("АКБ", Vector2(lx, row))
	draw_rect(Rect2(lx + 74 * k, row - 12 * k, 76 * k, 13 * k), Color(bcol, 0.22))
	draw_rect(Rect2(lx + 74 * k, row - 12 * k, 76 * k * clampf(bat, 0.0, 1.0), 13 * k), bcol)
	_s("%d%%" % int(bat * 100), Vector2(vx - 70 * k, row + 1 * k), int(18 * k), bcol, HORIZONTAL_ALIGNMENT_RIGHT, 70 * k, UiTheme.mono())
	row += 33 * k
	var wind: Vector2 = data.get("wind", Vector2.ZERO)   # в осях камеры: x — вправо, y — вперёд
	_kick("ВЕТЕР", Vector2(lx, row))
	var wc := Vector2(lx + 90 * k, row - 6 * k)
	if wind.length() > 0.3:
		var wd := Vector2(wind.x, -wind.y).normalized()
		draw_line(wc - wd * 11 * k, wc + wd * 11 * k, c, 2.0)
		draw_line(wc + wd * 11 * k, wc + wd * 4 * k + wd.orthogonal() * 5 * k, c, 2.0)
		draw_line(wc + wd * 11 * k, wc + wd * 4 * k - wd.orthogonal() * 5 * k, c, 2.0)
	else:
		draw_circle(wc, 2.5 * k, Color(c, 0.6))
	_s("%d м/с" % int(wind.length()), Vector2(vx - 90 * k, row + 1 * k), int(18 * k), c, HORIZONTAL_ALIGNMENT_RIGHT, 90 * k, UiTheme.mono())

	# Правый блок: скорость, высота, режим.
	var rr := Rect2(sz.x - 292 * k, sz.y - 142 * k, 268 * k, 118 * k)
	_plate(rr)
	var rx := rr.position.x + 16 * k
	_kick("СКОРОСТЬ, КМ/Ч", Vector2(rx, rr.position.y + 24 * k))
	_s("%d" % int(data.get("speed", 0.0) * 3.6), Vector2(rx, rr.position.y + 66 * k), int(40 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
	var hx := rr.position.x + 150 * k
	_kick("ВЫСОТА, М", Vector2(hx, rr.position.y + 24 * k))
	var agl: float = data.get("agl", 0.0)
	_s("%d" % int(agl), Vector2(hx, rr.position.y + 66 * k), int(40 * k), c if agl > 3.0 else UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
	draw_rect(Rect2(rx, rr.position.y + 80 * k, rr.size.x - 32 * k, 1), UiTheme.LINE)
	_kick("%s · %s" % [str(data.get("kind_name", "")).to_upper(), "АКРО" if data.get("acro", false) else "АРКАДА"], Vector2(rx, rr.position.y + 103 * k), UiTheme.ACCENT)


func _draw_warnings(k: float) -> void:
	var warns: Array = data.get("warnings", [])
	var wy := size.y * 0.5 + 96 * k
	var blink_on := fmod(_blink, 0.6) < 0.4
	var fs := int(19 * k)
	for w in warns:
		var col: Color = UiTheme.WARN if w[1] else UiTheme.ACCENT
		var tw := _w(w[0], fs, UiTheme.caps()) + 40 * k
		var r := Rect2((size.x - tw) / 2, wy, tw, 34 * k)
		_plate(r, 1.0, col)
		if w[1] and not blink_on:
			col.a = 0.4
		_s(w[0], Vector2(r.position.x + 22 * k, wy + 24 * k), fs, col, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.caps())
		wy += 40 * k


func _draw_bottom(k: float) -> void:
	if not data.has("stock"):
		return
	var sz := size
	var c := UiTheme.OSD
	var w := 790 * k
	var r := Rect2((sz.x - w) / 2, sz.y - 70 * k, w, 46 * k)
	_plate(r)
	var y := r.position.y + 29 * k
	var x := r.position.x + 18 * k
	var stock: int = data.get("stock", 0)
	_kick("ДРОНЫ", Vector2(x, y))
	for i in SimConst.STOCK_MAX:
		draw_rect(Rect2(x + (62 + i * 15) * k, y - 12 * k, 10 * k, 14 * k), Color(c, 1.0 if i < stock else 0.22))
	if stock < SimConst.STOCK_MAX:
		_s("+%d с" % int(ceil(data.get("regen", 0.0))), Vector2(x + 112 * k, y + 1 * k), int(14 * k), UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
	draw_rect(Rect2(x + 170 * k, r.position.y + 10 * k, 1, r.size.y - 20 * k), UiTheme.LINE)
	x += 188 * k
	_kick("СЛЕД. [1/2]", Vector2(x, y))
	_s(str(data.get("next_kind", "")), Vector2(x + 96 * k, y + 2 * k), int(17 * k), c, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.bold())
	draw_rect(Rect2(x + 190 * k, r.position.y + 10 * k, 1, r.size.y - 20 * k), UiTheme.LINE)
	x += 208 * k
	var trap: float = data.get("trap_cd", 0.0)
	_kick("СЕТЬ [F]", Vector2(x, y))
	if data.get("sudden", false):
		_s("отключена", Vector2(x + 76 * k, y + 2 * k), int(17 * k), UiTheme.DIM)
	elif trap <= 0.0:
		_s("готова", Vector2(x + 76 * k, y + 2 * k), int(17 * k), UiTheme.GOOD, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.bold())
	else:
		var bw := 60 * k
		draw_rect(Rect2(x + 76 * k, y - 9 * k, bw, 6 * k), Color(c, 0.2))
		draw_rect(Rect2(x + 76 * k, y - 9 * k, bw * (1.0 - trap / SimConst.TRAP_COOLDOWN), 6 * k), UiTheme.ACCENT)
		_s("%d с" % int(ceil(trap)), Vector2(x + 144 * k, y + 1 * k), int(14 * k), UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
	draw_rect(Rect2(x + 178 * k, r.position.y + 10 * k, 1, r.size.y - 20 * k), UiTheme.LINE)
	x += 196 * k
	_kick("ЗАХВАТ [R]", Vector2(x, y))
	if data.get("lock_on", false):
		_s("ведёт", Vector2(x + 92 * k, y + 2 * k), int(17 * k), UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.bold())
	elif data.get("lock_ready", false):
		_s("цель", Vector2(x + 92 * k, y + 2 * k), int(17 * k), UiTheme.GOOD, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.bold())
	else:
		_s("нет цели", Vector2(x + 92 * k, y + 2 * k), int(17 * k), UiTheme.DIM)


func _draw_table(k: float) -> void:
	var rows: Array = data.get("players", [])
	var w := 680 * k
	var h := (96 + rows.size() * 36) * k
	var r := Rect2((size.x - w) / 2, (size.y - h) / 2, w, h)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	_plate_sb.bg_color = UiTheme.PANEL
	_plate_sb.set_corner_radius_all(int(10 * k))
	draw_style_box(_plate_sb, r)
	draw_rect(Rect2(r.position.x + 28 * k, r.position.y, w - 56 * k, 2 * k), UiTheme.ACCENT)
	var x0 := r.position.x + 28 * k
	var y := r.position.y + 36 * k
	_kick("Оператор", Vector2(x0, y))
	_kick("Жизни", Vector2(x0 + 310 * k, y))
	_kick("Попадания", Vector2(x0 + 410 * k, y))
	_kick("Перехваты", Vector2(x0 + 530 * k, y))
	draw_rect(Rect2(x0, y + 12 * k, w - 56 * k, 1), UiTheme.LINE)
	y += 42 * k
	for row in rows:
		var a := 0.5 if row.out else 1.0
		if row.me:
			draw_rect(Rect2(r.position.x + 14 * k, y - 23 * k, w - 28 * k, 34 * k), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(x0, y - 16 * k, 4 * k, 20 * k), Color(row.color, a))
		_s(row.name + (" (бот)" if row.bot else ""), Vector2(x0 + 16 * k, y), int(19 * k), Color(UiTheme.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, 280 * k,
			UiTheme.bold() if row.me else UiTheme.font())
		_s("—" if row.out else str(row.lives), Vector2(x0 + 310 * k, y), int(19 * k), Color(UiTheme.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
		_s(str(row.hits), Vector2(x0 + 410 * k, y), int(19 * k), Color(UiTheme.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
		_s(str(row.rams), Vector2(x0 + 530 * k, y), int(19 * k), Color(UiTheme.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.mono())
		y += 36 * k
