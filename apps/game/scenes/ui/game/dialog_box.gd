class_name DialogBox
extends Control
## Diálogo con un personaje: retrato, nombre y texto que se va escribiendo.
## Un toque, clic, Espacio o E pasa a la línea siguiente (o completa la que se
## está escribiendo). Los diálogos que llegan mientras hay uno abierto esperan
## en fila. Pausa el juego mientras se lee.

signal finished

const CHARS_PER_SECOND := 55.0
const HEIGHT := 78.0

var _queue: Array = []  # [{ npc, lines }]
var _lines: Array = []
var _line := 0
var _shown := 0.0
var _open := false

var _portrait: TextureRect
var _name: Label
var _role: Label
var _text: Label
var _more: Label
var _panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuTheme.build()
	UiArt.smooth(self)
	visible = false

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"MenuPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	# Si el texto pide más alto, el panel crece hacia arriba (no se sale por abajo).
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(54, 54)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	column.add_child(head)
	_name = Label.new()
	_name.add_theme_font_override("font", UiArt.FONT_DISPLAY)
	_name.add_theme_font_size_override("font_size", 12)
	_name.add_theme_color_override("font_color", MenuTheme.GOLD.lightened(0.2))
	head.add_child(_name)
	_role = Label.new()
	_role.theme_type_variation = &"HintLabel"
	_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(_role)
	_more = Label.new()
	_more.add_theme_font_size_override("font_size", 8)
	_more.add_theme_color_override("font_color", MenuTheme.GOLD)
	head.add_child(_more)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 10)
	_text.add_theme_constant_override("line_spacing", -1)
	column.add_child(_text)

	resized.connect(_fit)
	UiArt.keep_fitted(_panel, _fit)
	_fit()


func is_open() -> bool:
	return _open


## Pone un diálogo en la fila: `npc` es la clave del personaje (Game.npc).
func say(npc_key: String, lines: Array) -> void:
	if lines.is_empty():
		return
	_queue.append({"npc": npc_key, "lines": lines})
	if not _open:
		GameAudio.play("scroll")
		_next_dialog()


func _next_dialog() -> void:
	if _queue.is_empty():
		_close()
		return
	var entry: Dictionary = _queue.pop_front()
	var npc := Game.npc(str(entry.npc))
	_portrait.texture = GameArt.portrait(str(npc.get("portrait", "vecino")))
	_name.text = str(npc.get("name", ""))
	_role.text = str(npc.get("role", ""))
	_lines = entry.lines
	_line = 0
	_show_line()
	if not _open:
		_open = true
		visible = true
		Game.push_modal()
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _show_line() -> void:
	_text.text = str(_lines[_line])
	_text.visible_characters = 0
	_shown = 0.0
	_more.text = "%d/%d  »" % [_line + 1, _lines.size()]


func _close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Game.pop_modal()
	finished.emit()


func _process(delta: float) -> void:
	if not _open:
		return
	_shown += delta * CHARS_PER_SECOND
	_text.visible_characters = int(_shown) if _shown < _text.text.length() else -1


func _advance() -> void:
	if _text.visible_characters != -1:
		_shown = 1e9  # completa la línea de una
		_text.visible_characters = -1
		return
	_line += 1
	if _line < _lines.size():
		_show_line()
	else:
		_next_dialog()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		_advance()
		accept_event()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		# Esc salta el diálogo entero.
		_queue.clear()
		_close()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	var width := minf(440.0, get_viewport_rect().size.x - 16.0)
	_panel.offset_left = -width / 2.0
	_panel.offset_right = width / 2.0
	# Vuelve al alto normal: si una línea larga lo agrandó, se encoge otra vez.
	_panel.offset_top = -HEIGHT - 10.0
	_panel.offset_bottom = -10.0
