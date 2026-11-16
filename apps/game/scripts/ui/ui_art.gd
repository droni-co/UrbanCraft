class_name UiArt
extends RefCounted
## Arte de la interfaz (generado en Layer.ai, ver assets/art/ui/README.md):
## iconos, marcos, logo, ilustraciones de pantalla completa y fuentes.

const ICON_DIR := "res://assets/art/ui/icons/"
const SCREEN_DIR := "res://assets/art/ui/screens/"
const LOGO := preload("res://assets/art/ui/logo.png")
const PANEL := preload("res://assets/art/ui/frames/panel.png")
## Bordes del marco del panel, en píxeles del PNG (izquierda, arriba, derecha, abajo).
const PANEL_MARGINS := Vector4(37, 39, 36, 40)

const FONT_BODY := preload("res://assets/fonts/ui_body.tres")
const FONT_BOLD := preload("res://assets/fonts/ui_bold.tres")
const FONT_DISPLAY := preload("res://assets/fonts/ui_display.tres")

## Ilustraciones de la pantalla de carga (la de título va aparte).
const LOADING_SCREENS: Array[String] = ["city", "plaza", "park", "night"]

static var _icons := {}
static var _screens := {}


## Icono de assets/art/ui/icons/<name>.png (96x96, se muestra reducido).
static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICON_DIR + icon_name + ".png"
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[icon_name]


## Ilustración de assets/art/ui/screens/<name>.jpg.
static func screen(screen_name: String) -> Texture2D:
	if not _screens.has(screen_name):
		_screens[screen_name] = load(SCREEN_DIR + screen_name + ".jpg")
	return _screens[screen_name]


## Panel con marco de latón (menús, chat, tarjetas).
static func panel(padding := 10.0, alpha := 1.0) -> ArtStyleBox:
	var s := ArtStyleBox.new()
	s.texture = PANEL
	s.margins = PANEL_MARGINS
	s.art_scale = 3.0
	s.modulate = Color(1, 1, 1, alpha)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s


## El arte de la interfaz está a mayor resolución que la pantalla lógica: se
## dibuja con filtro lineal y mipmaps (el proyecto usa *nearest* por el pixel art).
static func smooth(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## TextureRect para un icono a `icon_size` px lógicos.
static func icon_rect(icon_name: String, icon_size := 12.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(icon_name)
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smooth(rect)
	return rect


## Botón redondo del HUD (menú, chat, voz) con un icono pintado.
static func hud_button(icon_name: String, button_size := 24.0) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(button_size, button_size)
	smooth(b)
	set_hud_button_tint(b, MenuTheme.CHIP)
	return b


## Color de fondo del botón del HUD (la voz lo cambia según su estado).
static func set_hud_button_tint(b: Button, color: Color) -> void:
	var states := {"normal": 0.0, "hover": 0.12, "pressed": -0.12}
	for state: String in states:
		var s := StyleBoxFlat.new()
		var shift: float = states[state]
		s.bg_color = color.lightened(shift) if shift > 0.0 else color.darkened(-shift)
		s.set_corner_radius_all(64)
		s.border_color = MenuTheme.GOLD.darkened(0.15)
		s.set_border_width_all(1)
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 3
		s.shadow_offset = Vector2(0, 1.5)
		s.anti_aliasing = true
		s.set_content_margin_all(3.5)
		b.add_theme_stylebox_override(state, s)


## Fondo de los textos sueltos del HUD y de las tarjetas pequeñas (chip oscuro).
static func chip(radius := 6.0, alpha := 0.82) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(MenuTheme.CHIP, alpha)
	s.set_corner_radius_all(int(radius))
	s.border_color = Color(MenuTheme.GOLD, 0.45)
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 1)
	s.anti_aliasing = true
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
