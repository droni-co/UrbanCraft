class_name QuestTracker
extends PanelContainer
## Lo que toca hacer, siempre a la vista: el capítulo de la historia y, bien
## destacado, el SIGUIENTE PASO (con un punto del mismo color que la flecha y
## el aro que lo marcan en el mapa). Debajo, el resto de metas y los encargos.
## (El sector y tu rango: TerritoryBadge.)
##
## Tocarlo abre Menú → Misiones. Para que se note que es un botón: cabecera
## "MISIÓN · Ver »", reacción al pasar/tocar y, hasta la primera vez que se
## toca, un aviso "Toca aquí…" con el borde latiendo. Cuando cambia el
## siguiente paso, el recuadro destella.

signal pressed

const WIDTH := 168.0
const HINT_KEY := "quest_tracker_opened"
## Mismos colores que TargetGuide (amarillo: encargos; celeste: hablar con alguien).
const JOB_COLOR := TargetGuide.COLOR
const STORY_COLOR := TargetGuide.STORY_COLOR
const FLASH_SECONDS := 2.5

var _column: VBoxContainer
var _style: StyleBoxFlat
var _hint: Label
var _show_hint := false
var _hovered := false
var _flash := 0.0
var _time := 0.0
var _last_now := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MenuTheme.build()
	UiArt.smooth(self)
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Abrir Misiones"
	_style = UiArt.chip(7, 0.8)
	_style.content_margin_left = 6
	_style.content_margin_right = 6
	_style.content_margin_top = 4
	_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", _style)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 1)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_show_hint = not GameSettings.has_seen(HINT_KEY)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	Game.changed.connect(_refresh)
	Game.territory_changed.connect(_refresh)
	_refresh()


func _gui_input(event: InputEvent) -> void:
	# En pantallas táctiles el toque también llega como clic (emulación de ratón).
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	if _show_hint:
		_show_hint = false
		GameSettings.mark_seen(HINT_KEY)
		_refresh()
	# Pequeño "apretón" para que se sienta como un botón.
	pivot_offset = size / 2.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(0.96, 0.96), 0.05)
	t.tween_property(self, "scale", Vector2.ONE, 0.08)
	pressed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_flash = maxf(_flash - delta, 0.0)
	var glow := 0.0
	if _flash > 0.0:
		glow = 0.5 + 0.5 * sin(_time * 10.0)
	elif _show_hint:
		glow = 0.5 + 0.5 * sin(_time * 4.0)
	var base := Color(MenuTheme.GOLD, 0.35)
	_style.border_color = base.lerp(MenuTheme.GOLD.lightened(0.3), glow)
	_style.bg_color = Color(MenuTheme.CHIP.lightened(0.12 if _hovered else 0.0), 0.86)
	if _hint:
		_hint.modulate.a = 0.6 + 0.4 * sin(_time * 4.0)


func _refresh() -> void:
	GameWindow.clear(_column)
	_hint = null
	visible = Game.ready_to_play
	if not visible:
		return

	_header()

	# El siguiente paso: la primera meta pendiente de la historia o, si no hay,
	# el primer paso de un encargo.
	var now := {}
	var others: Array[Dictionary] = []
	var chapter: Variant = Game.story.get("chapter")
	if chapter is Dictionary:
		_line(str(chapter.title), 10, MenuTheme.GOLD.lightened(0.2), UiArt.FONT_DISPLAY)
		for goal: Dictionary in Game.story.get("goals", []):
			if now.is_empty() and not goal.get("done", false):
				now = goal
			else:
				others.append(goal)
	elif Game.story.get("finished", false):
		_line("Leyenda del barrio", 10, MenuTheme.GOLD.lightened(0.2), UiArt.FONT_DISPLAY)

	var steps := Game.active_steps()
	var now_text := ""
	if not now.is_empty():
		var color := STORY_COLOR if now.get("type") == "talk" else Color(0, 0, 0, 0)
		now_text = str(now.text)
		_now_card(now_text, color, int(now.get("progress", 0)), int(now.get("count", 1)))
	elif not steps.is_empty():
		now_text = JobList.step_text(steps[0].step)
		_now_card(now_text, JOB_COLOR, 0, 1)
		steps = steps.slice(1)

	for goal: Dictionary in others:
		var done: bool = goal.get("done", false)
		var text := str(goal.text)
		var count := int(goal.get("count", 1))
		if count > 1 and not done:
			text += "  %s/%s" % [PlayerStats.format_number(goal.progress), PlayerStats.format_number(count)]
		_line(("Listo: " if done else "• ") + text, 8, MenuTheme.SUCCESS if done else MenuTheme.TEXT_DIM)

	if not steps.is_empty():
		_gap()
		_line("Encargos", 9, MenuTheme.GOLD, UiArt.FONT_BOLD)
		for entry: Dictionary in steps:
			_line("• " + JobList.step_text(entry.step), 8, MenuTheme.TEXT)

	if now_text.is_empty() and steps.is_empty() and others.is_empty():
		_line("Nada pendiente. Toca para buscar encargos.", 8, MenuTheme.TEXT_DIM)

	if _show_hint:
		_gap()
		_hint = _line("Toca aquí para ver tus misiones", 8, MenuTheme.GOLD.lightened(0.3), UiArt.FONT_BOLD)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Cambió el siguiente paso: que se note.
	if now_text != _last_now:
		if not _last_now.is_empty() and not now_text.is_empty():
			_flash = FLASH_SECONDS
		_last_now = now_text


## "MISIÓN ··· Ver »": deja claro qué es y que se puede tocar.
func _header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(row)
	var icon := TextureRect.new()
	icon.texture = GameArt.medal("libro")
	icon.custom_minimum_size = Vector2(12, 12)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var title := _label("MISIÓN", 8, MenuTheme.GOLD, UiArt.FONT_BOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var more := _label("Ver »", 8, Color.WHITE, UiArt.FONT_BOLD)
	var chip := StyleBoxFlat.new()
	chip.bg_color = MenuTheme.TERRACOTTA
	chip.set_corner_radius_all(4)
	chip.content_margin_left = 4
	chip.content_margin_right = 4
	more.add_theme_stylebox_override("normal", chip)
	row.add_child(more)


## Tarjeta del siguiente paso: resaltada, con el punto del color de su marca
## en el mapa (si la tiene) y barra de progreso si es de contar.
func _now_card(text: String, marker: Color, progress: int, count: int) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(MenuTheme.SLATE, 0.9)
	style.set_corner_radius_all(4)
	style.border_width_left = 3
	style.border_color = marker if marker.a > 0.0 else MenuTheme.TERRACOTTA
	style.content_margin_left = 5
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", style)
	_column.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var head := _label("AHORA", 7, Color(MenuTheme.TEXT, 0.7), UiArt.FONT_BOLD)
	if marker.a > 0.0:
		head.text = "AHORA · sigue la flecha"
		head.add_theme_color_override("font_color", marker)
	box.add_child(head)
	var label := _label(text, 9, Color.WHITE, UiArt.FONT_BOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 22.0
	box.add_child(label)
	if count > 1:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		bar.max_value = count
		bar.value = progress
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.4)
		bg.set_corner_radius_all(2)
		var fill := StyleBoxFlat.new()
		fill.bg_color = MenuTheme.SUCCESS
		fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(_label("%s/%s" % [PlayerStats.format_number(progress), PlayerStats.format_number(count)],
			7, MenuTheme.TEXT, UiArt.FONT_BOLD))
		box.add_child(row)


func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", -2)
	if font:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _line(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := _label(text, font_size, color, font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 12.0
	_column.add_child(label)
	return label


func _gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 3
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(gap)
