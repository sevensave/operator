class_name UiTheme
## Общая тема интерфейса: «пульт оператора» — тёмные полупрозрачные панели, янтарный акцент,
## узкий гротеск для заголовков и моноширинные цифры. Шрифты системные, иконки рисуются кодом.

const ACCENT := Color(0.96, 0.66, 0.20)
const ACCENT_HI := Color(1.0, 0.78, 0.36)
const INK := Color(0.07, 0.06, 0.04)            # текст на акцентной заливке
const BG := Color(0.035, 0.045, 0.055, 0.94)
const PANEL := Color(0.05, 0.062, 0.074, 0.93)
const CARD := Color(1.0, 1.0, 1.0, 0.045)       # вложенная плашка внутри панели
const LINE := Color(1.0, 1.0, 1.0, 0.10)
const FIELD := Color(0.0, 0.0, 0.0, 0.38)
const TEXT := Color(0.93, 0.94, 0.91)
const DIM := Color(0.60, 0.65, 0.66)
const OSD := Color(0.93, 0.96, 0.92)
const WARN := Color(1.0, 0.40, 0.30)
const GOOD := Color(0.48, 0.86, 0.56)
const PLATE := Color(0.02, 0.03, 0.035, 0.76)   # подложка OSD: текст читается и на снегу

static var _font: Font
static var _bold: Font
static var _mono: Font
static var _caps: Font
static var _theme: Theme


static func _sys(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	return f


static func font() -> Font:
	if _font == null:
		_font = _sys(["Bahnschrift", "Segoe UI", "DIN Alternate", "Roboto Condensed", "Helvetica Neue", "Arial", "DejaVu Sans"], 400)
	return _font


static func bold() -> Font:
	if _bold == null:
		_bold = _sys(["Bahnschrift", "Segoe UI", "DIN Alternate", "Roboto Condensed", "Helvetica Neue", "Arial", "DejaVu Sans"], 700)
	return _bold


static func mono() -> Font:
	if _mono == null:
		_mono = _sys(["Cascadia Mono", "Consolas", "SF Mono", "Menlo", "DejaVu Sans Mono", "Courier New"], 600)
	return _mono


## Жирный шрифт с разрядкой — для подписей-«кикеров» прописными.
static func caps() -> Font:
	if _caps == null:
		var v := FontVariation.new()
		v.base_font = bold()
		v.spacing_glyph = 2
		_caps = v
	return _caps


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)

	# Кнопка: спокойная плашка, акцент появляется на наведении.
	_button_colors(t, "Button", TEXT, Color.WHITE, INK, Color(0.42, 0.45, 0.45))
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.13)))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.12), Color(ACCENT, 0.85)))
	t.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.05)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.9), 2))

	# Главное действие экрана: акцентная заливка, тёмный текст.
	t.set_type_variation("PrimaryButton", "Button")
	_button_colors(t, "PrimaryButton", INK, INK, INK, Color(0.42, 0.45, 0.45))
	t.set_font("font", "PrimaryButton", bold())
	t.set_stylebox("normal", "PrimaryButton", _box(ACCENT, ACCENT))
	t.set_stylebox("hover", "PrimaryButton", _box(ACCENT_HI, ACCENT_HI))
	t.set_stylebox("pressed", "PrimaryButton", _box(ACCENT.darkened(0.2), ACCENT.darkened(0.2)))
	t.set_stylebox("disabled", "PrimaryButton", _box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.05)))
	t.set_stylebox("focus", "PrimaryButton", _box(Color(0, 0, 0, 0), Color.WHITE, 2))

	# Пункт главного меню: без рамки, слева полоса-акцент на наведении.
	t.set_type_variation("NavButton", "Button")
	_button_colors(t, "NavButton", Color(TEXT, 0.82), Color.WHITE, ACCENT, Color(0.42, 0.45, 0.45))
	t.set_font_size("font_size", "NavButton", 27)
	t.set_stylebox("normal", "NavButton", _nav_box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.14)))
	t.set_stylebox("hover", "NavButton", _nav_box(Color(1, 1, 1, 0.07), ACCENT))
	t.set_stylebox("pressed", "NavButton", _nav_box(Color(ACCENT, 0.16), ACCENT))
	t.set_stylebox("focus", "NavButton", _nav_box(Color(1, 1, 1, 0.04), ACCENT))

	# Тихая текстовая кнопка («изменить», «копировать»).
	t.set_type_variation("LinkButton2", "Button")
	_button_colors(t, "LinkButton2", ACCENT, ACCENT_HI, Color.WHITE, Color(0.42, 0.45, 0.45))
	t.set_font_size("font_size", "LinkButton2", 17)
	for st in ["normal", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "LinkButton2", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 4))
	t.set_stylebox("hover", "LinkButton2", _box(Color(ACCENT, 0.12), Color(0, 0, 0, 0), 0, 8, 4))

	# Поля ввода и списки выбора.
	t.set_stylebox("normal", "LineEdit", _box(FIELD, Color(1, 1, 1, 0.14)))
	t.set_stylebox("focus", "LineEdit", _box(FIELD, ACCENT, 2))
	t.set_stylebox("read_only", "LineEdit", _box(FIELD, Color(1, 1, 1, 0.06)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	_button_colors(t, "OptionButton", TEXT, Color.WHITE, TEXT, Color(0.42, 0.45, 0.45))
	t.set_stylebox("normal", "OptionButton", _box(FIELD, Color(1, 1, 1, 0.14)))
	t.set_stylebox("hover", "OptionButton", _box(Color(0, 0, 0, 0.5), Color(ACCENT, 0.85)))
	t.set_stylebox("pressed", "OptionButton", _box(Color(0, 0, 0, 0.5), ACCENT))
	t.set_stylebox("focus", "OptionButton", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.9), 2))
	t.set_icon("arrow", "OptionButton", _icon(16, 16, func(p: Vector2) -> float:
		return _seg(p, Vector2(4, 6), Vector2(8, 10), 1.1) + _seg(p, Vector2(8, 10), Vector2(12, 6), 1.1), DIM))
	t.set_constant("arrow_margin", "OptionButton", 12)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.075, 0.09, 0.98), Color(1, 1, 1, 0.16), 1, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.9), Color(0, 0, 0, 0), 0, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	var dot_on := _icon(16, 16, func(p: Vector2) -> float: return _disc(p, Vector2(8, 8), 4.0), ACCENT)
	var dot_off := _icon(16, 16, func(p: Vector2) -> float: return _ring(p, Vector2(8, 8), 4.0, 0.9), Color(DIM, 0.7))
	t.set_icon("radio_checked", "PopupMenu", dot_on)
	t.set_icon("radio_unchecked", "PopupMenu", dot_off)

	# Переключатель: «пилюля» с бегунком.
	_button_colors(t, "CheckButton", TEXT, Color.WHITE, TEXT, Color(0.42, 0.45, 0.45))
	for st in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "CheckButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, 6))
	t.set_icon("checked", "CheckButton", _toggle_icon(true))
	t.set_icon("unchecked", "CheckButton", _toggle_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _toggle_icon(true, 0.4))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(false, 0.4))
	t.set_constant("h_separation", "CheckButton", 12)

	# Ползунок.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _icon(20, 20, func(p: Vector2) -> float: return _disc(p, Vector2(10, 10), 7.0), Color(0.96, 0.96, 0.93)))
	t.set_icon("grabber_highlight", "HSlider", _icon(20, 20, func(p: Vector2) -> float: return _disc(p, Vector2(10, 10), 8.5), Color.WHITE))

	# Панели, разделители, прокрутка, подсказки.
	var panel := _box(PANEL, Color(1, 1, 1, 0.09), 1, 30, 26)
	panel.set_corner_radius_all(10)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 28
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _box(CARD, Color(1, 1, 1, 0.07), 1, 14, 10))
	t.set_type_variation("Row", "PanelContainer")
	t.set_stylebox("panel", "Row", _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 12, 7))
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(1, 1, 1, 0.04)
	bar.set_corner_radius_all(3)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	var grab := bar.duplicate()
	grab.bg_color = Color(1, 1, 1, 0.22)
	var grab_hi := bar.duplicate()
	grab_hi.bg_color = Color(ACCENT, 0.8)
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.03, 0.04, 0.05, 0.97), Color(ACCENT, 0.6), 1, 10, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "ItemList", _box(FIELD, Color(1, 1, 1, 0.1)))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t


static func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_focus_color", type, hover)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_disabled_color", type, disabled)


static func _box(bg: Color, border: Color, bw := 1, mx := 16, my := 9) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(6)
	s.anti_aliasing_size = 0.8
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


static func _nav_box(bg: Color, stripe: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = stripe
	s.border_width_left = 3
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	return s


# ---------- Иконки: растровая заливка по функции покрытия ----------

static func _icon(w: int, h: int, cover: Callable, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a := clampf(cover.call(Vector2(x + 0.5, y + 0.5)), 0.0, 1.0)
			img.set_pixel(x, y, Color(color, color.a * a))
	return ImageTexture.create_from_image(img)


static func _disc(p: Vector2, c: Vector2, r: float) -> float:
	return clampf(r - p.distance_to(c) + 0.5, 0.0, 1.0)


static func _ring(p: Vector2, c: Vector2, r: float, w: float) -> float:
	return clampf(w - absf(p.distance_to(c) - r) + 0.5, 0.0, 1.0)


static func _seg(p: Vector2, a: Vector2, b: Vector2, w: float) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return clampf(w - p.distance_to(a + ab * t) + 0.5, 0.0, 1.0)


static func _toggle_icon(on: bool, alpha := 1.0) -> ImageTexture:
	var w := 46
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a0 := Vector2(13, 13)
	var a1 := Vector2(33, 13)
	var knob := a1 if on else a0
	var base := ACCENT if on else Color(1, 1, 1, 0.16)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var col := Color(base, base.a * _seg(p, a0, a1, 11.0))
			var k := _disc(p, knob, 8.0)
			col = col.blend(Color(INK if on else Color(0.9, 0.9, 0.88), k))
			col.a *= alpha
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------- Готовые виджеты ----------

static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Заголовок экрана или блока: жирный гротеск.
static func heading(text: String, size := 34, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", bold())
	return l


## Маленькая подпись прописными с разрядкой над блоком.
static func kicker(text: String, color := DIM) -> Label:
	var l := label(text.to_upper(), 14, color)
	l.add_theme_font_override("font", caps())
	return l


static func button(text: String, cb: Callable, min_w := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.pressed.connect(cb)
	return b


static func primary(text: String, cb: Callable, min_w := 260) -> Button:
	var b := button(text, cb, min_w)
	b.theme_type_variation = "PrimaryButton"
	return b


static func nav(text: String, cb: Callable) -> Button:
	var b := button(text, cb, 0)
	b.theme_type_variation = "NavButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


static func link(text: String, cb: Callable) -> Button:
	var b := button(text, cb, 0)
	b.custom_minimum_size = Vector2.ZERO
	b.theme_type_variation = "LinkButton2"
	return b


static func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	return p
