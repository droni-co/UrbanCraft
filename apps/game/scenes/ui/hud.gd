class_name Hud
extends CanvasLayer
## HUD del juego: info de depuración, estado del servidor, mensajes,
## controles táctiles y menú del jugador. Corre siempre (process_mode = ALWAYS).
##
## El menú (botón ☰, Esc o P) es un modal que pausa el juego. Sus secciones se
## registran en _build_menu(); el mundo se conecta a las señales de cada una.

@onready var info_label: Label = %InfoLabel
@onready var status_label: Label = %StatusLabel
@onready var message_label: Label = %MessageLabel
@onready var touch_controls: Control = %TouchControls
@onready var attribution_label: Label = %AttributionLabel
@onready var minimap: Minimap = %Minimap

const MENU_BUTTON_SIZE := 24.0
const MENU_BUTTON_TOP := 22.0

## Menú del jugador (modal) y sus secciones.
var menu: GameMenu
var teleport: TeleportSection
var account: AccountSection
var online: OnlineSection
var character: CharacterSection
var friends: FriendsSection
var menu_button: Button
## Hambre, nivel, dinero… bajo el botón de menú.
var stats_panel: StatsPanel
const STATS_GAP := 4.0
## Nombre de la calle o lugar actual, junto al minimapa.
var location_label: Label
var _location_text := ""
var _location_tween: Tween

var _message_tween: Tween
## Pantalla de carga con barra de progreso (encima del HUD, debajo del menú).
var loading_screen: LoadingScreen


func _ready() -> void:
	touch_controls.visible = GameSettings.touch_controls_enabled
	GameSettings.touch_controls_changed.connect(func(enabled: bool) -> void: touch_controls.visible = enabled)
	message_label.modulate.a = 0.0
	set_online(false)
	set_attribution("")
	location_label = _make_location_label()
	loading_screen = LoadingScreen.new()
	add_child(loading_screen)
	_build_menu()
	GameSettings.minimap_settings_changed.connect(_layout_around_minimap)
	GameSettings.labels_settings_changed.connect(_refresh_location)
	_layout_around_minimap()


## Esc/P/Start abren el menú. Con el menú abierto lo gestiona GameMenu (así
## escribir una "p" en un campo de texto no lo cierra).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not menu.visible:
		menu.open()
		get_viewport().set_input_as_handled()


func _build_menu() -> void:
	menu = GameMenu.new()
	menu.name = "GameMenu"
	add_child(menu)  # último hijo: queda encima de todo el HUD

	teleport = TeleportSection.new()
	menu.add_section("Teletransporte", teleport)
	character = CharacterSection.new()
	menu.add_section("Personaje", character)
	online = OnlineSection.new()
	menu.add_section("Multijugador", online)
	friends = FriendsSection.new()
	menu.add_section("Amigos", friends)
	Friends.changed.connect(_update_friends_badge)
	Friends.notified.connect(_on_friends_notified)
	account = AccountSection.new()
	menu.add_section("Cuenta", account)
	if OS.is_debug_build():
		_add_debug_section.call_deferred()
	# Para agregar más opciones: menu.add_section("Título", MiSeccion.new())

	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.theme = MenuTheme.build()
	menu_button.icon = MenuTheme.menu_icon()
	menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_button.tooltip_text = "Menú (Esc)"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.add_theme_stylebox_override("normal", _menu_button_style(0.45))
	menu_button.add_theme_stylebox_override("hover", _menu_button_style(0.65))
	menu_button.add_theme_stylebox_override("pressed", _menu_button_style(0.8))
	menu_button.pressed.connect(menu.open)
	menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(menu_button)
	move_child(menu_button, menu.get_index())

	stats_panel = StatsPanel.new()
	stats_panel.name = "StatsPanel"
	stats_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(stats_panel)
	move_child(stats_panel, menu.get_index())
	PlayerStats.level_up.connect(func(_key: String, level: int) -> void:
		show_message("¡Subiste al nivel %d!" % level, 3.0))


## "Amigos (2)" en el menú si hay solicitudes por responder.
func _update_friends_badge() -> void:
	var pending := Friends.pending_count()
	menu.set_section_label(friends, "Amigos (%d)" % pending if pending > 0 else "Amigos")


func _on_friends_notified(event: String, nickname: String) -> void:
	match event:
		"request":
			show_message("%s te envió una solicitud de amistad (Menú → Amigos)." % nickname, 4.0)
		"accepted":
			show_message("%s aceptó tu solicitud de amistad." % nickname, 3.0)


## Sección de depuración del menú: solo si el servidor permite herramientas de desarrollo.
func _add_debug_section() -> void:
	await Auth.fetch_methods()
	if Auth.methods.dev and is_instance_valid(menu):
		menu.add_section("Depuración", DebugSection.new())


func _menu_button_style(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, alpha)
	s.set_corner_radius_all(int(MENU_BUTTON_SIZE / 2.0))
	s.anti_aliasing = true
	return s


func set_info(text: String) -> void:
	info_label.text = text


## Evita que el botón de menú quede bajo el minimapa si está arriba a la derecha.
## TODO: si el minimapa va abajo, reubicar joystick/botones táctiles.
func _layout_around_minimap() -> void:
	var shift := 0.0
	if GameSettings.minimap_visible and GameSettings.minimap_corner == GameSettings.ScreenCorner.TOP_RIGHT:
		shift = GameSettings.minimap_size.x + GameSettings.minimap_margin.x
	menu_button.offset_right = -8.0 - shift
	menu_button.offset_left = menu_button.offset_right - MENU_BUTTON_SIZE
	menu_button.offset_top = MENU_BUTTON_TOP
	menu_button.offset_bottom = MENU_BUTTON_TOP + MENU_BUTTON_SIZE
	# Stats debajo del botón, alineados a su borde derecho (crecen hacia la izquierda).
	stats_panel.offset_right = menu_button.offset_right
	stats_panel.offset_left = menu_button.offset_right
	stats_panel.offset_top = menu_button.offset_bottom + STATS_GAP
	_layout_location_label()
	_refresh_location()


## Nombre de la calle o lugar donde está el jugador (vacío lo oculta).
func set_location(text: String) -> void:
	if text == _location_text:
		return
	_location_text = text
	if _location_tween:
		_location_tween.kill()
	_location_tween = create_tween()
	_location_tween.tween_property(location_label, "modulate:a", 0.0, 0.15)
	_location_tween.tween_callback(func() -> void: location_label.text = text)
	_location_tween.tween_property(location_label, "modulate:a", 1.0 if not text.is_empty() else 0.0, 0.3)


func _refresh_location() -> void:
	location_label.visible = GameSettings.current_street_visible


func _make_location_label() -> Label:
	var label := Label.new()
	label.name = "LocationLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.modulate.a = 0.0
	add_child(label)
	move_child(label, minimap.get_index() + 1)
	return label


## Coloca el nombre del lugar pegado al minimapa (debajo si está arriba, encima
## si está abajo), alineado con su lado exterior.
func _layout_location_label() -> void:
	var s := GameSettings.minimap_size
	var m := GameSettings.minimap_margin
	var right := GameSettings.minimap_corner in [GameSettings.ScreenCorner.TOP_RIGHT, GameSettings.ScreenCorner.BOTTOM_RIGHT]
	var bottom := GameSettings.minimap_corner in [GameSettings.ScreenCorner.BOTTOM_LEFT, GameSettings.ScreenCorner.BOTTOM_RIGHT]
	var shown := GameSettings.minimap_visible
	var width := maxf(s.x + 72.0, 160.0)
	var height := 12.0

	location_label.anchor_left = 1.0 if right else 0.0
	location_label.anchor_right = location_label.anchor_left
	location_label.anchor_top = 1.0 if bottom else 0.0
	location_label.anchor_bottom = location_label.anchor_top
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	location_label.offset_left = -m.x - width if right else m.x + 1.0
	location_label.offset_right = location_label.offset_left + width
	if bottom:
		var top := -m.x - (s.y + 2.0 if shown else 0.0) - height
		location_label.offset_top = top
	else:
		location_label.offset_top = m.y + (s.y + 2.0 if shown else 0.0)
	location_label.offset_bottom = location_label.offset_top + height


## Texto central de carga; vacío lo oculta.
## Muestra la pantalla de carga con este texto ("" = el mapa está listo).
## `progress` (0..1) adelanta la barra; < 0 la deja como está.
func set_loading(text: String, progress := -1.0) -> void:
	if text.is_empty():
		loading_screen.finish()
	else:
		loading_screen.set_status(text, progress)


## Atribución obligatoria de los datos del mapa (licencia ODbL de OSM).
func set_attribution(text: String) -> void:
	attribution_label.text = text
	attribution_label.visible = not text.is_empty()


func set_online(online: bool) -> void:
	status_label.text = "● En línea" if online else "● Sin conexión"
	status_label.modulate = Color("7ee787") if online else Color("ff7b72")


func show_message(text: String, duration := 2.0) -> void:
	message_label.text = text
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(message_label, "modulate:a", 1.0, 0.15)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)
