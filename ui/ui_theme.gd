class_name UiTheme
## Общая тема интерфейса: системный шрифт с кириллицей, тёмные панели, янтарный акцент.

const ACCENT := Color(0.91, 0.64, 0.24)
const BG := Color(0.06, 0.07, 0.07, 0.92)
const PANEL := Color(0.11, 0.12, 0.12, 0.94)
const TEXT := Color(0.9, 0.9, 0.86)
const DIM := Color(0.6, 0.62, 0.58)
const OSD := Color(0.92, 0.95, 0.9)
const WARN := Color(1.0, 0.42, 0.3)

static var _font: Font
static var _mono: Font
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto Condensed", "Helvetica Neue", "Arial", "DejaVu Sans"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
	return _font


static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New"])
		f.font_weight = 600
		_mono = f
	return _mono


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.BLACK)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.42))
	t.set_stylebox("normal", "Button", _box(Color(0.16, 0.17, 0.16), Color(0.28, 0.29, 0.27)))
	t.set_stylebox("hover", "Button", _box(Color(0.22, 0.23, 0.21), ACCENT.darkened(0.2)))
	t.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color(0.12, 0.12, 0.12), Color(0.18, 0.18, 0.18)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.08, 0.09, 0.09), Color(0.3, 0.31, 0.29)))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(0.22, 0.23, 0.21)))
	t.set_stylebox("panel", "Panel", _box(PANEL, Color(0.22, 0.23, 0.21)))
	t.set_stylebox("normal", "OptionButton", _box(Color(0.16, 0.17, 0.16), Color(0.28, 0.29, 0.27)))
	t.set_stylebox("hover", "OptionButton", _box(Color(0.22, 0.23, 0.21), ACCENT.darkened(0.2)))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "ItemList", _box(Color(0.08, 0.09, 0.09), Color(0.22, 0.23, 0.21)))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.pressed.connect(cb)
	return b
