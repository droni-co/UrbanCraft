class_name ChatPanel
extends Control
## Interfaz del chat (en el HUD). Pensada para PC y para móvil:
##   - Botón de chat (junto al de menú) con el número de mensajes sin leer.
##   - Cerrado: los mensajes nuevos aparecen unos segundos a la izquierda
##     (no bloquean toques ni clics: el joystick y el mapa siguen funcionando).
##   - Abierto: ventana ARRIBA de la pantalla (en el móvil el teclado tapa la
##     mitad de abajo) con el historial, que se desliza con el dedo, y el campo.
## Teclado: Enter o T abren; Enter envía (con el campo vacío, cierra); Esc
## cierra. Mientras escribes el personaje no se mueve (ver Player._is_typing).
## Tocar o hacer clic fuera del chat suelta el teclado sin cerrarlo.
## Lógica e historial: autoload Chat.

const WINDOW_MAX_WIDTH := 380.0
const WINDOW_TOP := 4.0
const HISTORY_HEIGHT := 92.0
const FEED_WIDTH := 230.0
const FEED_MAX := 5
const FEED_SECONDS := 10.0

const COLOR_MINE := Color("ffd75e")
const COLOR_FRIEND := MenuTheme.SUCCESS
const COLOR_OTHER := Color("8cc8ff")

## Botón de chat: lo coloca el HUD (Hud._layout_around_minimap).
var button: Button
## Abre o cierra el menú del juego: con el menú abierto no se abre el chat.
var menu: GameMenu

var _window: PanelContainer
var _hint: Label
var _scroll: ScrollContainer
var _history: RichTextLabel
var _field: LineEdit
var _send: Button
var _badge: Label
var _feed: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuTheme.build()
	_build_feed()
	_build_button()
	_build_window()
	Chat.message_added.connect(_on_message)
	Chat.unread_changed.connect(_update_badge)
	Online.status_changed.connect(func(_s: String) -> void: _update_hint())
	GameSettings.online_settings_changed.connect(_update_hint)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_update_badge(Chat.unread)
	_update_hint()


func is_open() -> bool:
	return _window.visible


func open() -> void:
	if not is_open():
		_window.visible = true
		_feed.visible = false
		Chat.reading = true
		_rebuild_history()
	_focus_input()


func close() -> void:
	if not is_open():
		return
	_field.release_focus()
	_window.visible = false
	Chat.reading = false
	for line in _feed.get_children():
		line.queue_free()  # ya se leyeron
	_feed.visible = true


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## Dónde empiezan los mensajes flotantes (debajo del minimapa si está arriba
## a la izquierda). Lo llama el HUD.
func set_feed_top(top: float) -> void:
	_feed.offset_top = top


# --- Entrada ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open() or _menu_open():
		return
	# Esc cierra aunque el campo tenga el foco (si no, se la come).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	# Tocar/hacer clic fuera: se suelta el teclado (para caminar) sin cerrar.
	var pressed_at := Vector2.INF
	if event is InputEventMouseButton and event.pressed:
		pressed_at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed_at = event.position
	if pressed_at != Vector2.INF and _field.has_focus() \
			and not _window.get_global_rect().has_point(pressed_at) \
			and not button.get_global_rect().has_point(pressed_at):
		_field.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not event.is_echo() and not _menu_open():
		open()
		get_viewport().set_input_as_handled()


func _menu_open() -> bool:
	return menu != null and menu.visible


func _focus_input() -> void:
	_field.grab_focus()
	_field.edit()  # en el móvil abre el teclado


func _on_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		close()
		return
	_submit()


func _submit() -> void:
	var text := _field.text
	if text.strip_edges().is_empty():
		_focus_input()
		return
	if Chat.send(text) == "":
		_field.clear()
	_focus_input()


# --- Mensajes ---------------------------------------------------------------------

func _on_message(message: Dictionary) -> void:
	if is_open():
		_history.append_text(_format(message) + "\n")
		_scroll_to_bottom.call_deferred()
	elif not message.mine:
		_add_feed_line(message)


func _rebuild_history() -> void:
	_history.clear()
	if Chat.messages.is_empty():
		_history.append_text("[color=#%s][i]Aún no hay mensajes. Saluda a quienes estén cerca.[/i][/color]\n" % MenuTheme.TEXT_DIM.to_html(false))
	for message in Chat.messages:
		_history.append_text(_format(message) + "\n")
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame  # que el texto ya tenga su alto
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Texto con BBCode; lo que escriben los jugadores se escapa.
static func _format(message: Dictionary) -> String:
	var text := _escape(str(message.text))
	if message.system:
		return "[color=#%s][i]%s[/i][/color]" % [MenuTheme.TEXT_DIM.to_html(false), text]
	var color := COLOR_MINE if message.mine else (COLOR_FRIEND if message.friend else COLOR_OTHER)
	return "[color=#%s]%s[/color]: %s" % [color.to_html(false), _escape(str(message.nickname)), text]


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _add_feed_line(message: Dictionary) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size.x = FEED_WIDTH
	line.add_theme_font_size_override("normal_font_size", 9)
	line.add_theme_font_size_override("italics_font_size", 9)
	line.add_theme_constant_override("outline_size", 3)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.3)
	bg.set_corner_radius_all(3)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	line.add_theme_stylebox_override("normal", bg)
	line.append_text(_format(message))
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(FEED_SECONDS)
	tween.tween_property(line, "modulate:a", 0.0, 0.6)
	tween.tween_callback(line.queue_free)


func _update_badge(count: int) -> void:
	_badge.text = str(count) if count < 100 else "99+"
	_badge.visible = count > 0


func _update_hint() -> void:
	var online := Online.is_online()
	if not online:
		_hint.text = "Sin conexión"
	elif not GameSettings.online_visible:
		_hint.text = "Modo fantasma: solo te leen tus amigos"
	else:
		_hint.text = "Te leen quienes están cerca y tus amigos"
	_field.editable = online
	_send.disabled = not online
	_field.placeholder_text = "Escribe un mensaje…" if online else "Sin conexión"


# --- Construcción -----------------------------------------------------------------

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.name = "ChatFeed"
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 2)
	_feed.offset_left = 8.0
	_feed.offset_right = 8.0 + FEED_WIDTH
	_feed.offset_top = 112.0
	add_child(_feed)


func _build_button() -> void:
	button = Button.new()
	button.name = "ChatButton"
	button.icon = _chat_icon()
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = "Chat (Enter)"
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	for state: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, {"normal": 0.45, "hover": 0.65, "pressed": 0.8}[state])
		s.set_corner_radius_all(12)
		s.anti_aliasing = true
		button.add_theme_stylebox_override(state, s)
	button.pressed.connect(toggle)
	add_child(button)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 7)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = MenuTheme.DANGER.darkened(0.1)
	bg.set_corner_radius_all(5)
	bg.content_margin_left = 2
	bg.content_margin_right = 2
	_badge.add_theme_stylebox_override("normal", bg)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.custom_minimum_size = Vector2(10, 10)
	_badge.position = Vector2(15, -3)
	button.add_child(_badge)


func _build_window() -> void:
	_window = PanelContainer.new()
	_window.name = "ChatWindow"
	_window.theme_type_variation = &"MenuPanel"
	_window.visible = false
	_window.anchor_left = 0.5
	_window.anchor_right = 0.5
	add_child(_window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_window.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Chat"
	title.theme_type_variation = &"SectionTitle"
	header.add_child(title)
	_hint = Label.new()
	_hint.theme_type_variation = &"HintLabel"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_hint)
	var close_button := Button.new()
	close_button.theme_type_variation = &"FlatButton"
	close_button.icon = MenuTheme.close_icon()
	close_button.tooltip_text = "Cerrar (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(24, 20)
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.pressed.connect(close)
	header.add_child(close_button)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = HISTORY_HEIGHT
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = true
	_history.scroll_active = false  # lo desplaza el ScrollContainer (también con el dedo)
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.mouse_filter = Control.MOUSE_FILTER_PASS
	_history.add_theme_font_size_override("normal_font_size", 10)
	_history.add_theme_font_size_override("italics_font_size", 10)
	_scroll.add_child(_history)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	_field = LineEdit.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.custom_minimum_size.y = 24
	_field.max_length = Chat.MAX_LENGTH
	_field.clear_button_enabled = false
	_field.context_menu_enabled = false
	_field.keep_editing_on_text_submit = true  # en el móvil el teclado sigue abierto
	_field.text_submitted.connect(_on_submitted)
	row.add_child(_field)
	_send = Button.new()
	_send.text = "Enviar"
	_send.theme_type_variation = &"PrimaryButton"
	_send.focus_mode = Control.FOCUS_NONE
	_send.custom_minimum_size = Vector2(52, 24)
	_send.pressed.connect(_submit)
	row.add_child(_send)


func _fit() -> void:
	var width := minf(WINDOW_MAX_WIDTH, get_viewport_rect().size.x - 16.0)
	_window.offset_left = -width / 2.0
	_window.offset_right = width / 2.0
	_window.offset_top = WINDOW_TOP


## Icono de globo de diálogo, dibujado en píxeles (como MenuTheme.menu_icon).
static func _chat_icon() -> Texture2D:
	var img := Image.create_empty(12, 11, false, Image.FORMAT_RGBA8)
	var c := MenuTheme.TEXT
	for y in range(0, 8):
		for x in range(0, 12):
			var corner := (x == 0 or x == 11) and (y == 0 or y == 7)
			if not corner:
				img.set_pixel(x, y, c)
	for p: Vector2i in [Vector2i(2, 8), Vector2i(3, 8), Vector2i(2, 9), Vector2i(2, 10)]:
		img.set_pixel(p.x, p.y, c)
	# Tres puntos "…" en hueco.
	for x: int in [3, 6, 9]:
		img.set_pixel(x - 1, 4, Color.TRANSPARENT)
		img.set_pixel(x, 4, Color.TRANSPARENT)
	return ImageTexture.create_from_image(img)
