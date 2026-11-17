class_name PlayerPanel
extends GameWindow
## Perfil de otro jugador: se abre al tocarlo en el mapa. Muestra su
## personaje, nivel, algunas cifras y sus medallas más recientes, con botones
## para saludarlo y para enviarle (o aceptar) una solicitud de amistad.
## Los datos vienen de GET /api/v1/players/:id (Friends.profile).

## Pide al mundo que el jugador salude (animación + aviso a los cercanos).
signal wave_requested

const MEDAL := Vector2(30, 30)
const COUNTER_TEXT := {
	"distance_m": "Caminado",
	"pois_discovered": "Lugares visitados",
	"jobs_completed": "Encargos hechos",
	"items_crafted": "Cosas fabricadas",
	"days_played": "Días jugados",
	"friends": "Amigos",
}

var _player_id := 0
var _player := {}
var _busy := false

var _portrait: TextureRect
var _name: Label
var _level: Label
var _since: Label
var _content: VBoxContainer
var _actions: HBoxContainer
var _status: Label


func _build() -> void:
	panel_size = Vector2(380, 290)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(36, 54)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	head.add_child(column)
	_name = Label.new()
	_name.add_theme_font_override("font", UiArt.FONT_DISPLAY)
	_name.add_theme_font_size_override("font_size", 14)
	_name.add_theme_color_override("font_color", MenuTheme.GOLD.lightened(0.2))
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_name)
	_level = Label.new()
	_level.add_theme_font_override("font", UiArt.FONT_BOLD)
	_level.add_theme_font_size_override("font_size", 10)
	column.add_child(_level)
	_since = Label.new()
	_since.theme_type_variation = &"HintLabel"
	column.add_child(_since)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	body.add_child(_actions)

	_content = GameWindow.scroll_list(body, 4)
	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	body.add_child(_status)


## Abre el perfil del jugador `player_id` (los datos de Online se ven al
## instante; el resto llega del servidor).
func open_player(player_id: int) -> void:
	_player_id = player_id
	_player = {
		"id": player_id,
		"nickname": Online.nickname(player_id),
		"level": Online.level(player_id),
		"skin": Online.skin(player_id),
	}
	_status.visible = false
	title_text = "Jugador"
	_refresh(true)
	open()
	var res := await Friends.profile(player_id)
	if not visible or _player_id != player_id:
		return
	if res.ok:
		_player = res.player
		_refresh(false)
	else:
		_show_status(res.message, true)
		GameWindow.clear(_content)


func _refresh(loading: bool) -> void:
	var skin := CharacterSkins.resolve(_player.get("skin"))
	_portrait.texture = CharacterSkins.frame(CharacterSkins.sheet_texture(skin), 0, 2) if not skin.is_empty() else null
	_name.text = str(_player.get("nickname", "Jugador"))
	_level.text = "Nivel %d" % int(_player.get("level", 1))
	_since.text = _since_text(_player.get("since"))
	_fill_actions(loading)
	GameWindow.clear(_content)
	if loading:
		GameWindow.hint(_content, "Cargando su perfil…")
		return
	_fill_counters()
	_fill_medals()


func _fill_actions(loading: bool) -> void:
	GameWindow.clear(_actions)
	var wave := GameWindow.small_button(_actions, "Saludar", func() -> void:
		close()
		wave_requested.emit())
	wave.custom_minimum_size = Vector2(0, 26)
	if loading:
		return
	var relation := str(_player.get("relation", "none"))
	var button: Button
	match relation:
		"none":
			button = GameWindow.small_button(_actions, "Agregar amigo", _send_request, &"PrimaryButton")
		"outgoing":
			button = GameWindow.small_button(_actions, "Solicitud enviada", func() -> void: pass)
			button.disabled = true
		"incoming":
			button = GameWindow.small_button(_actions, "Aceptar solicitud", _accept_request, &"PrimaryButton")
		"friend":
			button = GameWindow.small_button(_actions, "Ya son amigos", func() -> void: pass)
			button.disabled = true
	if button:
		button.custom_minimum_size = Vector2(0, 26)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _fill_counters() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for entry: Dictionary in _player.get("counters", []):
		var key := str(entry.key)
		var value := float(entry.value)
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", -2)
		var number := Label.new()
		number.text = _format_counter(key, value)
		number.add_theme_font_override("font", UiArt.FONT_BOLD)
		number.add_theme_font_size_override("font_size", 12)
		number.add_theme_color_override("font_color", MenuTheme.TEXT)
		cell.add_child(number)
		var label := Label.new()
		label.text = str(COUNTER_TEXT.get(key, key))
		label.theme_type_variation = &"HintLabel"
		label.add_theme_font_size_override("font_size", 8)
		cell.add_child(label)
		grid.add_child(cell)


func _fill_medals() -> void:
	var achievements: Dictionary = _player.get("achievements", {})
	var title := Label.new()
	title.text = "Logros  %d / %d" % [int(achievements.get("unlocked", 0)), int(achievements.get("total", 0))]
	title.add_theme_font_override("font", UiArt.FONT_BOLD)
	title.add_theme_color_override("font_color", MenuTheme.GOLD)
	_content.add_child(title)
	var recent: Array = achievements.get("recent", [])
	if recent.is_empty():
		GameWindow.hint(_content, "Todavía no tiene medallas.")
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	_content.add_child(row)
	var detail := GameWindow.hint(_content, "Toca una medalla para ver qué es.")
	for def: Dictionary in recent:
		var medal := MedalIcon.new()
		medal.setup(str(def.emblem), int(def.tier), true)
		medal.custom_minimum_size = MEDAL
		medal.mouse_filter = Control.MOUSE_FILTER_STOP
		var text := "%s (%s): %s" % [def.name, GameArt.TIER_NAMES[clampi(int(def.tier) - 1, 0, 3)], def.desc]
		medal.tooltip_text = text
		medal.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				detail.text = text)
		row.add_child(medal)


func _send_request() -> void:
	if _busy:
		return
	_busy = true
	var res := await Friends.send_request_to(_player_id)
	_busy = false
	_after_friend_action(res)


func _accept_request() -> void:
	if _busy or _player.get("requestId") == null:
		return
	_busy = true
	var res := await Friends.accept(int(_player.requestId))
	_busy = false
	if res.ok:
		res.message = "¡Ahora eres amigo de %s!" % _player.get("nickname", "")
	_after_friend_action(res)


func _after_friend_action(res: Dictionary) -> void:
	if not visible:
		return
	_show_status(res.message, not res.ok)
	if res.ok:
		var again := await Friends.profile(_player_id)
		if visible and again.ok:
			_player = again.player
			_fill_actions(false)


func _show_status(text: String, error: bool) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	_status.add_theme_color_override("font_color", MenuTheme.DANGER if error else MenuTheme.SUCCESS)


static func _format_counter(key: String, value: float) -> String:
	if key == "distance_m":
		return "%.1f km" % (value / 1000.0) if value >= 1000.0 else "%d m" % roundi(value)
	return PlayerStats.format_number(value)


## "En el barrio desde marzo de 2026".
static func _since_text(since: Variant) -> String:
	if not since is String or str(since).length() < 7:
		return ""
	const MONTHS := ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
		"agosto", "septiembre", "octubre", "noviembre", "diciembre"]
	var year := str(since).substr(0, 4)
	var month := clampi(int(str(since).substr(5, 2)), 1, 12)
	return "En el barrio desde %s de %s" % [MONTHS[month - 1], year]
