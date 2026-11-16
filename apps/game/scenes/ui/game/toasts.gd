class_name Toasts
extends VBoxContainer
## Avisos del juego, arriba al centro: recompensas ("+30 $ · +12 xp"), objetos
## que llegan al morral, lugares nuevos, sectores y logros (con su medalla).
## Cada uno aparece, se queda unos segundos y se va; se apilan hacia abajo.

const MAX_VISIBLE := 5
const WIDTH := 230.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuTheme.build()
	UiArt.smooth(self)
	add_theme_constant_override("separation", 3)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = 3.0
	Game.events_received.connect(show_events)


func show_events(events: Array) -> void:
	for event: Dictionary in events:
		match event.get("type"):
			"toast":
				_add(null, str(event.text), MenuTheme.TEXT)
			"reward":
				_reward(event)
			"discover":
				_add(PoiCatalog.icon(str(event.cat)), "Lugar nuevo: %s" % event.name, MenuTheme.GOLD.lightened(0.2), 3.5,
					PoiCatalog.color(str(event.cat)))
			"achievement":
				_achievement(event)
			"story":
				_add(GameArt.medal("libro"), "%s · %s" % [event.title, event.text], MenuTheme.GOLD.lightened(0.25), 4.0)
			"sector":
				_sector(event)


func _reward(event: Dictionary) -> void:
	var parts: PackedStringArray = []
	if event.get("money") != null:
		parts.append("+$%s" % PlayerStats.format_number(event.money))
	if event.get("xp") != null:
		parts.append("+%s xp" % PlayerStats.format_number(event.xp))
	var reason := str(event.get("reason", ""))
	if not parts.is_empty():
		var text := " · ".join(parts)
		_add(UiArt.icon("money" if event.get("money") != null else "xp"),
			text if reason.is_empty() else "%s  (%s)" % [text, reason], Color("ffe08a"))
	var items: Dictionary = event.get("items", {}) if event.get("items") is Dictionary else {}
	for key: String in items:
		_add(GameArt.item(key), "+%d  %s" % [int(items[key]), Game.item_name(key)], MenuTheme.TEXT)


func _sector(event: Dictionary) -> void:
	var icon := GameArt.medal("bandera")
	match event.get("kind"):
		"rank":
			_add(icon, "%s: ahora eres %s" % [event.name, event.rankName], MenuTheme.SUCCESS, 4.0)
		"owned":
			_add(GameArt.medal("corona"), "¡%s es tuyo!" % event.name, MenuTheme.GOLD.lightened(0.25), 5.0)
		"lost":
			_add(icon, "Perdiste el dominio de %s" % event.name, MenuTheme.DANGER, 5.0)


func _achievement(event: Dictionary) -> void:
	var medal := MedalIcon.new()
	medal.setup(str(event.emblem), int(event.tier), true)
	medal.custom_minimum_size = Vector2(26, 26)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Label.new()
	head.text = "¡Logro!  %s" % event.name
	head.add_theme_font_override("font", UiArt.FONT_DISPLAY)
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", GameArt.tier_color(int(event.tier)).lightened(0.25))
	column.add_child(head)
	var desc := Label.new()
	desc.text = str(event.desc)
	desc.theme_type_variation = &"HintLabel"
	desc.add_theme_font_size_override("font_size", 8)
	column.add_child(desc)
	_push([medal, column], 5.5, GameArt.tier_color(int(event.tier)))


func _add(icon: Texture2D, text: String, color: Color, seconds := 3.0, icon_tint := Color.WHITE) -> void:
	var nodes: Array = []
	if icon:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.modulate = icon_tint
		rect.custom_minimum_size = Vector2(15, 15)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nodes.append(rect)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", UiArt.FONT_BOLD)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", color)
	nodes.append(label)
	_push(nodes, seconds, MenuTheme.GOLD)


func _push(nodes: Array, seconds: float, border: Color) -> void:
	while get_child_count() >= MAX_VISIBLE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	var style := UiArt.chip(7, 0.9)
	style.border_color = Color(border, 0.75)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	for node: Control in nodes:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(node)
	add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(seconds)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)
