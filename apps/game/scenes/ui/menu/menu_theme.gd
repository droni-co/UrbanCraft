class_name MenuTheme
extends RefCounted
## Tema visual de los menús (construido en código para no depender de un .tres
## editado a mano). Tamaños pensados para la resolución base 640x360 y para
## tocar con el dedo (botones de 24 px de alto mínimo = 48 px en 720p).
##
## Estilo: paneles azul marino con marco de latón (UiArt.panel, pintado en
## Layer.ai), botones con relieve (terracota el principal, como los techos de
## teja) y fuentes Nunito (texto) y Fredoka (títulos).

# Paleta
const BG := Color("13233d")
const BG_SOFT := Color(1, 1, 1, 0.06)
const BORDER := Color(1, 1, 1, 0.12)
const TEXT := Color("f5efe3")
const TEXT_DIM := Color("aab5c8")
## Latón de los marcos: foco, selección, detalles.
const GOLD := Color("e6b85c")
## Terracota de los techos: botón principal.
const TERRACOTTA := Color("e2703a")
## Fondo de los botones secundarios.
const SLATE := Color("2a4268")
## Fondo de los botones y chips del HUD.
const CHIP := Color("162a47")
const ACCENT := GOLD
const DANGER := Color("ff7b72")
const SUCCESS := Color("7ee787")

static var _theme: Theme


static func build() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = UiArt.FONT_BODY
	t.default_font_size = 10

	t.set_stylebox("panel", "MenuPanel", UiArt.panel(12))
	t.set_type_variation("MenuPanel", "PanelContainer")

	t.set_type_variation("MenuTitle", "Label")
	t.set_font("font", "MenuTitle", UiArt.FONT_DISPLAY)
	t.set_font_size("font_size", "MenuTitle", 16)
	t.set_color("font_color", "MenuTitle", GOLD.lightened(0.25))
	t.set_color("font_shadow_color", "MenuTitle", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "MenuTitle", 1)
	t.set_constant("shadow_offset_x", "MenuTitle", 0)

	t.set_type_variation("SectionTitle", "Label")
	t.set_font("font", "SectionTitle", UiArt.FONT_DISPLAY)
	t.set_font_size("font_size", "SectionTitle", 13)
	t.set_color("font_color", "SectionTitle", TEXT)

	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 9)
	t.set_color("font_color", "HintLabel", TEXT_DIM)

	t.set_color("font_color", "Label", TEXT)

	# Botones normales (secundarios): pizarra con relieve.
	t.set_font("font", "Button", UiArt.FONT_BOLD)
	t.set_stylebox("normal", "Button", _raised(SLATE, 6))
	t.set_stylebox("hover", "Button", _raised(SLATE.lightened(0.1), 6))
	t.set_stylebox("pressed", "Button", _raised(SLATE.darkened(0.15), 6, true))
	t.set_stylebox("disabled", "Button", _raised(Color(SLATE, 0.45), 6, false, 0.4))
	t.set_stylebox("focus", "Button", _focus(6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_constant("h_separation", "Button", 6)

	# Botón principal: terracota con relieve.
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _raised(TERRACOTTA, 8))
	t.set_stylebox("hover", "PrimaryButton", _raised(TERRACOTTA.lightened(0.12), 8))
	t.set_stylebox("pressed", "PrimaryButton", _raised(TERRACOTTA.darkened(0.12), 8, true))
	t.set_stylebox("disabled", "PrimaryButton", _raised(Color(TERRACOTTA, 0.35), 8, false, 0.4))
	t.set_color("font_color", "PrimaryButton", Color.WHITE)
	t.set_color("font_hover_color", "PrimaryButton", Color.WHITE)
	t.set_color("font_pressed_color", "PrimaryButton", Color(1, 1, 1, 0.9))
	t.set_color("font_outline_color", "PrimaryButton", Color(0.35, 0.12, 0.03, 0.6))
	t.set_constant("outline_size", "PrimaryButton", 3)

	# Navegación lateral del menú: la sección abierta, con una barra de latón.
	t.set_type_variation("NavButton", "Button")
	t.set_stylebox("normal", "NavButton", _box(Color(0, 0, 0, 0), 6, 8))
	t.set_stylebox("hover", "NavButton", _box(Color(1, 1, 1, 0.07), 6, 8))
	t.set_stylebox("pressed", "NavButton", _nav_selected())
	t.set_stylebox("hover_pressed", "NavButton", _nav_selected(0.26))
	t.set_stylebox("focus", "NavButton", _focus(6))
	t.set_color("font_pressed_color", "NavButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "NavButton", Color.WHITE)
	t.set_color("font_hover_color", "NavButton", TEXT)
	t.set_color("font_color", "NavButton", TEXT_DIM)
	t.set_constant("h_separation", "NavButton", 7)

	# Tarjetas seleccionables (selector de personaje)
	t.set_type_variation("CardButton", "Button")
	t.set_stylebox("normal", "CardButton", _box(Color(0, 0, 0, 0.22), 7, 4, BORDER))
	t.set_stylebox("hover", "CardButton", _box(Color(1, 1, 1, 0.08), 7, 4, Color(GOLD, 0.5)))
	t.set_stylebox("pressed", "CardButton", _box(Color(GOLD, 0.18), 7, 4, GOLD, 2))
	t.set_stylebox("hover_pressed", "CardButton", _box(Color(GOLD, 0.24), 7, 4, GOLD, 2))
	# Foco (teclado/gamepad): borde claro, distinto del latón de "elegido".
	t.set_stylebox("focus", "CardButton", _box(Color(0, 0, 0, 0), 7, 4, Color(1, 1, 1, 0.55)))
	t.set_font("font", "CardButton", UiArt.FONT_BODY)
	t.set_font_size("font_size", "CardButton", 9)
	t.set_color("font_color", "CardButton", TEXT_DIM)
	t.set_color("font_pressed_color", "CardButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "CardButton", Color.WHITE)

	# "Continuar con Google": botón claro, como pide la guía de marca de Google.
	# (Para el logo oficial "G", ver docs/login-google.md.)
	t.set_type_variation("GoogleButton", "Button")
	t.set_stylebox("normal", "GoogleButton", _box(Color.WHITE, 6, 10, Color("dadce0")))
	t.set_stylebox("hover", "GoogleButton", _box(Color("f2f5fa"), 6, 10, Color("c6cad1")))
	t.set_stylebox("pressed", "GoogleButton", _box(Color("e3e8ef"), 6, 10, Color("c6cad1")))
	t.set_stylebox("focus", "GoogleButton", _focus(6))
	t.set_stylebox("disabled", "GoogleButton", _box(Color(1, 1, 1, 0.4), 6, 10))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "GoogleButton", Color("1f1f1f"))

	# Botón sin fondo (iconos)
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", _box(Color(0, 0, 0, 0), 6, 4))
	t.set_stylebox("hover", "FlatButton", _box(Color(1, 1, 1, 0.08), 6, 4))
	t.set_stylebox("pressed", "FlatButton", _box(Color(1, 1, 1, 0.14), 6, 4))

	# Campos de texto: hundidos.
	var field := _box(Color(0.02, 0.05, 0.11, 0.6), 6, 7, Color(1, 1, 1, 0.1))
	field.border_width_top = 2
	field.border_color = Color(0, 0, 0, 0.35)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), 6, 7, GOLD))
	t.set_stylebox("read_only", "LineEdit", _box(Color(0, 0, 0, 0.2), 6, 7))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_font_size("font_size", "LineEdit", 11)

	# Interruptores y casillas: el latón marca "activado".
	for type in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, _box(Color(0, 0, 0, 0), 6, 4))
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.06), 6, 4))
		t.set_stylebox("pressed", type, _box(Color(0, 0, 0, 0), 6, 4))
		t.set_stylebox("hover_pressed", type, _box(Color(1, 1, 1, 0.06), 6, 4))
		t.set_stylebox("focus", type, _focus(6))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))

	# Barras de desplazamiento finas.
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _box(Color(0, 0, 0, 0.2), 3, 0))
		t.set_stylebox("grabber", type, _box(Color(GOLD, 0.45), 3, 0))
		t.set_stylebox("grabber_highlight", type, _box(Color(GOLD, 0.7), 3, 0))
		t.set_stylebox("grabber_pressed", type, _box(GOLD, 3, 0))

	# Desplegables y su lista.
	t.set_stylebox("panel", "PopupMenu", _box(BG, 6, 4, Color(GOLD, 0.6)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(GOLD, 0.22), 4, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# Ayudas emergentes (tooltips).
	var tip := _box(Color(BG, 0.97), 6, 6, Color(GOLD, 0.6))
	tip.shadow_color = Color(0, 0, 0, 0.4)
	tip.shadow_size = 4
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 9)

	t.set_stylebox("separator", "HSeparator", _line())
	t.set_constant("separation", "HSeparator", 6)

	_theme = t
	return t


static func _box(color: Color, radius: int, padding: int, border := Color(0, 0, 0, 0), border_width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = maxf(padding / 2.0, 3.0)
	s.content_margin_bottom = maxf(padding / 2.0, 3.0)
	if border.a > 0.0:
		s.set_border_width_all(border_width)
		s.border_color = border
	s.anti_aliasing = true
	return s


## Botón con relieve: un labio más oscuro abajo que desaparece al presionarlo
## (el texto baja 2 px, como si se hundiera).
static func _raised(color: Color, padding: int, pressed := false, alpha := 1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, color.a * alpha)
	s.set_corner_radius_all(7)
	s.border_color = Color(color.darkened(0.45), color.a * alpha)
	s.set_border_width_all(1)
	s.border_width_bottom = 1 if pressed else 3
	s.content_margin_left = padding + 2
	s.content_margin_right = padding + 2
	s.content_margin_top = 6.0 if pressed else 4.0
	s.content_margin_bottom = 4.0 if pressed else 6.0
	if not pressed:
		s.shadow_color = Color(0, 0, 0, 0.25 * alpha)
		s.shadow_size = 2
		s.shadow_offset = Vector2(0, 1)
	s.anti_aliasing = true
	return s


static func _focus(radius: int) -> StyleBoxFlat:
	var s := _box(Color(0, 0, 0, 0), radius + 1, 0, Color(GOLD, 0.9), 2)
	s.set_expand_margin_all(2)
	return s


static func _nav_selected(alpha := 0.2) -> StyleBoxFlat:
	var s := _box(Color(GOLD, alpha), 6, 8)
	s.border_color = GOLD
	s.border_width_left = 3
	return s


static func _line() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(GOLD, 0.3)
	s.thickness = 1
	return s


## Interruptor (CheckButton) dibujado a x4: cápsula con una perilla.
static func _switch_icon(on: bool) -> Texture2D:
	var w := 88
	var h := 48
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := SUCCESS.darkened(0.25) if on else Color("3a4d6c")
	var knob_x := w - h / 2.0 if on else h / 2.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Cápsula: distancia al segmento central.
			var cx := clampf(p.x, h / 2.0, w - h / 2.0)
			var d_track := p.distance_to(Vector2(cx, h / 2.0)) - h / 2.0
			var d_knob := p.distance_to(Vector2(knob_x, h / 2.0)) - (h / 2.0 - 6.0)
			var c := Color(0, 0, 0, 0)
			var a_track := clampf(0.5 - d_track, 0.0, 1.0)
			if a_track > 0.0:
				c = Color(track, a_track)
			var a_knob := clampf(0.5 - d_knob, 0.0, 1.0)
			if a_knob > 0.0:
				var knob := TEXT.lerp(Color.WHITE, 0.5) if on else TEXT_DIM
				c = c.blend(Color(knob, a_knob))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	return _Scaled.new(tex, 4.0)


## Icono de cerrar (X), dibujado a x4 con bordes suaves.
static func close_icon() -> Texture2D:
	var n := 40
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var a := Vector2(8, 8)
	var b := Vector2(n - 8, n - 8)
	var c := Vector2(n - 8, 8)
	var d := Vector2(8, n - 8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := minf(Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p),
				Geometry2D.get_closest_point_to_segment(p, c, d).distance_to(p))
			var alpha := clampf(3.5 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(TEXT, alpha))
	img.generate_mipmaps()
	return _Scaled.new(ImageTexture.create_from_image(img), 4.0)


## Textura dibujada a x`scale` que dice medir su tamaño lógico (como HDTexture).
class _Scaled:
	extends Texture2D
	var _tex: Texture2D
	var _scale: float

	func _init(tex: Texture2D, scale: float) -> void:
		_tex = tex
		_scale = scale

	func _get_width() -> int:
		return roundi(_tex.get_width() / _scale)

	func _get_height() -> int:
		return roundi(_tex.get_height() / _scale)

	func _has_alpha() -> bool:
		return true

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
		_tex.draw_rect(to_canvas_item, Rect2(pos, get_size()), false, modulate, transpose)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
		_tex.draw_rect(to_canvas_item, rect, tile, modulate, transpose)

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
		_tex.draw_rect_region(to_canvas_item, rect, Rect2(src_rect.position * _scale, src_rect.size * _scale), modulate, transpose, clip_uv)
