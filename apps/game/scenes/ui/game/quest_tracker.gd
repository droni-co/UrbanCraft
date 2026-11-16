class_name QuestTracker
extends PanelContainer
## Lo que toca hacer, siempre a la vista: el capítulo de la historia con sus
## metas, los encargos en curso y el sector donde estás (tu rango y su dueño).
## Tocarlo abre Menú → Misiones.

signal pressed

const WIDTH := 150.0

var _column: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuTheme.build()
	UiArt.smooth(self)
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Abrir Misiones"
	var style := UiArt.chip(7, 0.72)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	Game.changed.connect(_refresh)
	Game.territory_changed.connect(_refresh)
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


func _refresh() -> void:
	GameWindow.clear(_column)
	visible = Game.ready_to_play
	if not visible:
		return

	var chapter: Variant = Game.story.get("chapter")
	if chapter is Dictionary:
		_line(str(chapter.title), 10, MenuTheme.GOLD.lightened(0.2), UiArt.FONT_DISPLAY)
		for goal: Dictionary in Game.story.get("goals", []):
			var done: bool = goal.get("done", false)
			var count := int(goal.get("count", 1))
			var text := str(goal.text)
			if count > 1:
				text += "  %s/%s" % [PlayerStats.format_number(goal.progress), PlayerStats.format_number(count)]
			_line(("• " if not done else "") + text, 8, MenuTheme.SUCCESS if done else MenuTheme.TEXT)
	elif Game.story.get("finished", false):
		_line("Leyenda del barrio", 10, MenuTheme.GOLD.lightened(0.2), UiArt.FONT_DISPLAY)

	var steps := Game.active_steps()
	if not steps.is_empty():
		_gap()
		_line("Encargos", 9, MenuTheme.GOLD, UiArt.FONT_BOLD)
		for entry: Dictionary in steps:
			_line("• " + JobList.step_text(entry.step), 8, MenuTheme.TEXT)

	var sector := Game.current_sector()
	if not sector.is_empty():
		_gap()
		_line(str(sector.name), 9, MenuTheme.GOLD, UiArt.FONT_BOLD)
		var owner: Variant = sector.get("owner")
		var who := "sin dueño"
		if owner is Dictionary:
			who = "es tuyo" if sector.get("mine", false) else "de %s" % owner.name
		_line("%s (%d) · %s" % [Game.rank_name(int(sector.rank)), int(sector.points), who], 8,
			MenuTheme.SUCCESS if sector.get("mine", false) else MenuTheme.TEXT_DIM)


func _line(text: String, font_size: int, color: Color, font: Font = null) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 12.0
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -2)
	if font:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(label)


func _gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 3
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(gap)
