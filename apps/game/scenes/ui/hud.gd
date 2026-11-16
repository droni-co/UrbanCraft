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
## Teletransporte libre: solo para depurar (se agrega al menú con la sección Depuración).
var teleport: TeleportSection
var missions: MissionsSection
var territory: TerritorySection
var achievements: AchievementsSection
## Mecánicas: morral, ventana de lugar, ventana de objeto, diálogos y avisos.
var bag: BagPanel
var bag_button: Button
var place_panel: PlacePanel
var object_panel: ObjectPanel
var dialog: DialogBox
var toasts: Toasts
var tracker: QuestTracker
var account: AccountSection
var online: OnlineSection
var character: CharacterSection
var friends: FriendsSection
var menu_button: Button
## Chat con los jugadores cercanos y los amigos (botón, mensajes y ventana).
var chat: ChatPanel
## Voz con amigos (botón de micrófono, lista de amigos en la voz).
var voice: VoicePanel
const CHAT_BUTTON_GAP := 6.0
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
	message_label.add_theme_font_override("font", UiArt.FONT_BOLD)
	message_label.add_theme_color_override("font_outline_color", Color(0.06, 0.08, 0.14, 0.9))
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
	elif event.is_action_pressed("bag") and not menu.visible and Game.ready_to_play:
		bag.open_bag()
		get_viewport().set_input_as_handled()


func _build_menu() -> void:
	menu = GameMenu.new()
	menu.name = "GameMenu"
	add_child(menu)  # último hijo: queda encima de todo el HUD

	chat = ChatPanel.new()
	chat.name = "Chat"
	chat.menu = menu
	add_child(chat)
	move_child(chat, menu.get_index())
	menu.opened.connect(chat.close)

	voice = VoicePanel.new()
	voice.name = "Voice"
	add_child(voice)
	move_child(voice, menu.get_index())
	touch_controls.add_child(voice.talk_button)
	Voice.notice.connect(func(text: String) -> void: show_message(text, 3.0))

	teleport = TeleportSection.new()
	missions = MissionsSection.new()
	menu.add_section("Misiones", missions, GameArt.medal("libro"))
	territory = TerritorySection.new()
	menu.add_section("Territorio", territory, GameArt.medal("bandera"))
	achievements = AchievementsSection.new()
	menu.add_section("Logros", achievements, GameArt.medal("trofeo"))
	character = CharacterSection.new()
	menu.add_section("Personaje", character, "character")
	online = OnlineSection.new()
	menu.add_section("Multijugador", online, "multiplayer")
	friends = FriendsSection.new()
	menu.add_section("Amigos", friends, "friends")
	Friends.changed.connect(_update_friends_badge)
	Friends.notified.connect(_on_friends_notified)
	account = AccountSection.new()
	menu.add_section("Cuenta", account, "account")
	if OS.is_debug_build():
		_add_debug_section.call_deferred()
	# Para agregar más opciones: menu.add_section("Título", MiSeccion.new(), "icono")
	# (el icono es assets/art/ui/icons/<icono>.png).

	menu_button = UiArt.hud_button("settings", MENU_BUTTON_SIZE)
	menu_button.name = "MenuButton"
	menu_button.theme = MenuTheme.build()
	menu_button.tooltip_text = "Menú (Esc)"
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
	stats_panel.resized.connect(_layout_voice_list)
	_build_game_ui()
	# La pantalla de carga tapa todo el HUD menos el menú.
	move_child(loading_screen, menu.get_index())
	PlayerStats.level_up.connect(func(_key: String, level: int) -> void:
		show_message("¡Subiste al nivel %d!" % level, 3.0))


## Morral, ventanas de lugar y de objeto, diálogos, avisos y rastreador de misión.
func _build_game_ui() -> void:
	bag_button = UiArt.hud_button("menu", MENU_BUTTON_SIZE)
	bag_button.name = "BagButton"
	bag_button.theme = MenuTheme.build()
	bag_button.tooltip_text = "Morral (I)"
	bag_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(bag_button)

	tracker = QuestTracker.new()
	tracker.name = "QuestTracker"
	tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.pressed.connect(func() -> void: menu.open("Misiones"))
	tracker.resized.connect(_layout_voice_list)
	tracker.visibility_changed.connect(_layout_voice_list)
	add_child(tracker)

	toasts = Toasts.new()
	toasts.name = "Toasts"
	add_child(toasts)

	bag = BagPanel.new()
	bag.name = "Bag"
	place_panel = PlacePanel.new()
	place_panel.name = "PlacePanel"
	object_panel = ObjectPanel.new()
	object_panel.name = "ObjectPanel"
	dialog = DialogBox.new()
	dialog.name = "Dialog"
	for window: Control in [bag, place_panel, object_panel]:
		add_child(window)
	bag_button.pressed.connect(func() -> void: bag.open_bag())
	# Sin las mecánicas cargadas (mapa de demostración, sin servidor) no hay morral.
	bag_button.visible = Game.ready_to_play
	Game.changed.connect(func() -> void: bag_button.visible = Game.ready_to_play)
	# Orden (de abajo arriba): HUD, carga, ventanas, menú, avisos, diálogos.
	for node: Node in [bag_button, tracker]:
		move_child(node, loading_screen.get_index())
	add_child(dialog)
	move_child(toasts, dialog.get_index())
	menu.opened.connect(func() -> void:
		for window: GameWindow in [bag, place_panel, object_panel]:
			window.close())
	Game.events_received.connect(func(events: Array) -> void:
		for event: Dictionary in events:
			if event.get("type") == "dialog":
				dialog.say(str(event.npc), event.get("lines", [])))


## Bajo los stats van el rastreador de misión y, debajo, la lista de la voz.
func _layout_voice_list() -> void:
	if voice == null:
		return
	var bottom := stats_panel.offset_top + (stats_panel.size.y if stats_panel.visible else 0.0)
	if tracker:
		tracker.offset_right = menu_button.offset_right
		tracker.offset_left = menu_button.offset_right
		tracker.offset_top = bottom + STATS_GAP
		if tracker.visible:
			bottom = tracker.offset_top + tracker.size.y
	voice.place_list(menu_button.offset_right, bottom + STATS_GAP * 2.0)


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
		menu.add_section("Depuración", DebugSection.new(), "debug")
		menu.add_section("Teletransporte", teleport, "teleport")


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
	# Chat: a la izquierda del botón de menú; sus mensajes, bajo el minimapa
	# si este está arriba a la izquierda.
	chat.button.offset_right = menu_button.offset_left - CHAT_BUTTON_GAP
	chat.button.offset_left = chat.button.offset_right - MENU_BUTTON_SIZE
	chat.button.offset_top = MENU_BUTTON_TOP
	chat.button.offset_bottom = MENU_BUTTON_TOP + MENU_BUTTON_SIZE
	var feed_top := MENU_BUTTON_TOP + 6.0
	if GameSettings.minimap_visible and GameSettings.minimap_corner == GameSettings.ScreenCorner.TOP_LEFT:
		feed_top = GameSettings.minimap_margin.y + GameSettings.minimap_size.y + 20.0
	chat.set_feed_top(feed_top)
	voice.button.offset_right = chat.button.offset_left - CHAT_BUTTON_GAP
	voice.button.offset_left = voice.button.offset_right - MENU_BUTTON_SIZE
	voice.button.offset_top = MENU_BUTTON_TOP
	voice.button.offset_bottom = MENU_BUTTON_TOP + MENU_BUTTON_SIZE
	bag_button.offset_right = voice.button.offset_left - CHAT_BUTTON_GAP
	bag_button.offset_left = bag_button.offset_right - MENU_BUTTON_SIZE
	bag_button.offset_top = MENU_BUTTON_TOP
	bag_button.offset_bottom = MENU_BUTTON_TOP + MENU_BUTTON_SIZE
	_layout_voice_list()
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
	label.add_theme_font_override("font", UiArt.FONT_BOLD)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
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
