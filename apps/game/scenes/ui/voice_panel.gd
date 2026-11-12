class_name VoicePanel
extends Control
## Interfaz de la voz con amigos (en el HUD):
##   - Botón de micrófono (junto al de chat): activa o desactiva la voz.
##     Verde con la voz activa; más brillante mientras transmites.
##   - Lista de amigos en la voz bajo los stats: nombre en verde = hablando, gris =
##     conectando, rojo = no se pudo conectar. Tocar un nombre lo silencia.
##   - Botón táctil "Voz" (mantener para hablar) sobre los botones A/B.
## Lógica: autoload Voice.

const ROW_FONT := 9
const COLOR_IDLE := Color(1, 1, 1, 0.85)
const COLOR_SPEAKING := MenuTheme.SUCCESS
const COLOR_CONNECTING := MenuTheme.TEXT_DIM
const COLOR_FAILED := MenuTheme.DANGER

## Botón de micrófono: lo coloca el HUD.
var button: Button
## Botón táctil de pulsar para hablar: lo agrega el HUD a los controles táctiles.
var talk_button: TouchActionButton

var _list: VBoxContainer
var _styles := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuTheme.build()

	button = Button.new()
	button.name = "VoiceButton"
	button.icon = _mic_icon()
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.pressed.connect(Voice.toggle)
	add_child(button)

	_list = VBoxContainer.new()
	_list.name = "VoicePeers"
	_list.add_theme_constant_override("separation", 1)
	_list.anchor_left = 1.0
	_list.anchor_right = 1.0
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_list.offset_right = -8.0
	_list.offset_left = -8.0
	_list.offset_top = 120.0
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)

	talk_button = TouchActionButton.new()
	talk_button.name = "TalkButton"
	talk_button.action = &"voice_talk"
	talk_button.text = "Voz"
	talk_button.radius = 22.0
	talk_button.color = Color(MenuTheme.SUCCESS, 0.35)
	talk_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	talk_button.anchor_left = 1.0
	talk_button.anchor_top = 1.0
	talk_button.anchor_right = 1.0
	talk_button.anchor_bottom = 1.0
	talk_button.offset_left = -78.0
	talk_button.offset_top = -158.0
	talk_button.offset_right = -34.0
	talk_button.offset_bottom = -114.0

	Voice.changed.connect(_refresh)
	Voice.speaking_changed.connect(func(_id: int, _on: bool) -> void: _refresh())
	Voice.transmitting_changed.connect(func(_on: bool) -> void: _refresh())
	GameSettings.online_settings_changed.connect(_refresh)
	_refresh()


## Dónde va la lista de amigos en la voz: su borde derecho (offset desde el
## borde de la pantalla) y su borde superior. Lo llama el HUD.
func place_list(right: float, top: float) -> void:
	_list.offset_right = right
	_list.offset_left = right
	_list.offset_top = top


func _refresh() -> void:
	var on := Voice.enabled
	button.tooltip_text = "Voz con amigos: %s" % ("activada (clic para salir)" if on else "desactivada")
	var alpha := 0.45
	var color := Color.BLACK
	if Voice.starting:
		color = MenuTheme.TEXT_DIM
	elif on:
		color = MenuTheme.SUCCESS.darkened(0.05 if Voice.transmitting else 0.35)
		alpha = 0.95 if Voice.transmitting else 0.85
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _style(color, alpha + (0.15 if state != "normal" else 0.0)))
	button.modulate.a = 1.0 if Voice.supported() else 0.55

	if talk_button:
		talk_button.visible = on and not GameSettings.voice_open_mic

	for child in _list.get_children():
		child.queue_free()
	if not on:
		return
	var me := _row("Tú · " + _my_status(), MenuTheme.SUCCESS if Voice.transmitting else COLOR_IDLE)
	me.disabled = true
	_list.add_child(me)
	if Voice.peers.is_empty():
		var empty := _row("Esperando amigos…", COLOR_CONNECTING)
		empty.disabled = true
		_list.add_child(empty)
	var ids := Voice.peers.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return str(Voice.peers[a].nickname) < str(Voice.peers[b].nickname))
	for id: int in ids:
		var p: Dictionary = Voice.peers[id]
		# Sin símbolos como ●: la fuente de la versión web no los tiene.
		var text := str(p.nickname)
		var row_color := COLOR_IDLE
		match p.state:
			"connecting":
				text += " · conectando"
				row_color = COLOR_CONNECTING
			"failed":
				text += " · sin conexión"
				row_color = COLOR_FAILED
		if p.muted:
			text += " · silenciado"
			row_color = Color(row_color, 0.5)
		elif p.speaking:
			row_color = COLOR_SPEAKING
		var row := _row(text, row_color)
		row.tooltip_text = "Activar su audio" if p.muted else "Silenciar"
		row.pressed.connect(func() -> void: Voice.set_muted(id, not bool(p.muted)))
		_list.add_child(row)


func _my_status() -> String:
	if Voice.transmitting:
		return "hablando"
	if GameSettings.voice_open_mic:
		return "micrófono abierto"
	return "mantén Voz" if GameSettings.touch_controls_enabled else "mantén V"


func _row(text: String, color: Color) -> Button:
	var row := Button.new()
	row.text = text
	row.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.focus_mode = Control.FOCUS_NONE
	row.add_theme_font_size_override("font_size", ROW_FONT)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		row.add_theme_color_override(state, color)
	row.add_theme_constant_override("outline_size", 3)
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var bg := _style(Color.BLACK, 0.3, 3)
	for state: String in ["normal", "disabled"]:
		row.add_theme_stylebox_override(state, bg)
	row.add_theme_stylebox_override("hover", _style(Color.BLACK, 0.5, 3))
	row.add_theme_stylebox_override("pressed", _style(Color.BLACK, 0.6, 3))
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	return row


func _style(color: Color, alpha: float, radius := 12) -> StyleBoxFlat:
	var key := "%s/%s/%d" % [color.to_html(), alpha, radius]
	if _styles.has(key):
		return _styles[key]
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, alpha)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if radius < 12:
		s.content_margin_left = 4
		s.content_margin_right = 4
		s.content_margin_top = 1
		s.content_margin_bottom = 1
	_styles[key] = s
	return s


## Icono de micrófono, dibujado en píxeles (como MenuTheme.menu_icon).
static func _mic_icon() -> Texture2D:
	var img := Image.create_empty(10, 13, false, Image.FORMAT_RGBA8)
	var c := MenuTheme.TEXT
	for y in range(0, 7):  # cápsula
		for x in range(3, 7):
			if not ((y == 0 or y == 6) and (x == 3 or x == 6)):
				img.set_pixel(x, y, c)
	for y in range(4, 9):  # soporte en U
		img.set_pixel(1, y, c)
		img.set_pixel(8, y, c)
	for x in range(2, 8):
		img.set_pixel(x, 9, c)
	for y in range(10, 12):  # pie
		img.set_pixel(4, y, c)
		img.set_pixel(5, y, c)
	for x in range(2, 8):
		img.set_pixel(x, 12, c)
	return ImageTexture.create_from_image(img)
