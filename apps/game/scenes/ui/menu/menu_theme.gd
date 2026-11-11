class_name MenuTheme
extends RefCounted
## Tema visual de los menús (construido en código para no depender de un .tres
## editado a mano). Tamaños pensados para la resolución base 640x360 y para
## tocar con el dedo (botones de 24 px de alto mínimo = 48 px en 720p).

const BG := Color(0.08, 0.1, 0.14, 0.96)
const BG_SOFT := Color(1, 1, 1, 0.06)
const BORDER := Color(1, 1, 1, 0.12)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.66, 0.71, 0.78)
const ACCENT := Color("4f9dff")
const DANGER := Color("ff7b72")
const SUCCESS := Color("7ee787")

static var _theme: Theme


static func build() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 10

	t.set_stylebox("panel", "MenuPanel", _box(BG, 8, 10, BORDER))
	t.set_type_variation("MenuPanel", "PanelContainer")

	t.set_type_variation("MenuTitle", "Label")
	t.set_font_size("font_size", "MenuTitle", 14)
	t.set_color("font_color", "MenuTitle", TEXT)

	t.set_type_variation("SectionTitle", "Label")
	t.set_font_size("font_size", "SectionTitle", 12)
	t.set_color("font_color", "SectionTitle", TEXT)

	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 9)
	t.set_color("font_color", "HintLabel", TEXT_DIM)

	t.set_color("font_color", "Label", TEXT)

	# Botones normales
	t.set_stylebox("normal", "Button", _box(BG_SOFT, 5, 6))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.12), 5, 6))
	t.set_stylebox("pressed", "Button", _box(Color(1, 1, 1, 0.18), 5, 6))
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.03), 5, 6))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 5, 6, ACCENT))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	t.set_constant("h_separation", "Button", 6)

	# Botón principal
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(ACCENT.darkened(0.15), 5, 8))
	t.set_stylebox("hover", "PrimaryButton", _box(ACCENT, 5, 8))
	t.set_stylebox("pressed", "PrimaryButton", _box(ACCENT.darkened(0.3), 5, 8))
	t.set_stylebox("disabled", "PrimaryButton", _box(Color(ACCENT, 0.25), 5, 8))
	t.set_color("font_color", "PrimaryButton", Color.WHITE)

	# Navegación lateral
	t.set_type_variation("NavButton", "Button")
	t.set_stylebox("normal", "NavButton", _box(Color(0, 0, 0, 0), 5, 8))
	t.set_stylebox("hover", "NavButton", _box(BG_SOFT, 5, 8))
	t.set_stylebox("pressed", "NavButton", _box(Color(ACCENT, 0.22), 5, 8))
	t.set_stylebox("hover_pressed", "NavButton", _box(Color(ACCENT, 0.28), 5, 8))
	t.set_color("font_pressed_color", "NavButton", Color.WHITE)
	t.set_color("font_color", "NavButton", TEXT_DIM)

	# Botón sin fondo (iconos)
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", _box(Color(0, 0, 0, 0), 5, 4))

	# Campos de texto
	t.set_stylebox("normal", "LineEdit", _box(Color(0, 0, 0, 0.35), 5, 6, BORDER))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), 5, 6, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 11)

	t.set_stylebox("separator", "HSeparator", _line())
	t.set_constant("separation", "HSeparator", 4)

	_theme = t
	return t


static func _box(color: Color, radius: int, padding: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = maxf(padding / 2.0, 3.0)
	s.content_margin_bottom = maxf(padding / 2.0, 3.0)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	s.anti_aliasing = true
	return s


static func _line() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = BORDER
	s.thickness = 1
	return s


## Icono de menú (tres líneas), dibujado en píxeles.
static func menu_icon() -> Texture2D:
	var img := Image.create_empty(12, 10, false, Image.FORMAT_RGBA8)
	for y in [0, 1, 4, 5, 8, 9]:
		for x in 12:
			img.set_pixel(x, y, TEXT)
	return ImageTexture.create_from_image(img)


## Icono de cerrar (X).
static func close_icon() -> Texture2D:
	var img := Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	for i in 10:
		for d in [0, 1]:
			var x := clampi(i + d, 0, 9)
			img.set_pixel(x, i, TEXT)
			img.set_pixel(9 - x, i, TEXT)
	return ImageTexture.create_from_image(img)
