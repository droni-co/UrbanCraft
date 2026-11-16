class_name GameWindow
extends Control
## Base de las ventanas del juego (lugar, morral, objetos): fondo oscuro, panel
## con marco, título y botón de cerrar. Mientras está abierta el juego se pausa
## (Game.push_modal), igual que con el menú. Esc o el botón la cierran.
##
## Las subclases llenan `body` (VBoxContainer) y llaman open() / close().

signal closed

## Tamaño máximo del panel (se encoge en pantallas pequeñas).
var panel_size := Vector2(430, 280)
var title_text := "":
	set(value):
		title_text = value
		if _title:
			_title.text = value

var body: VBoxContainer
var _panel: PanelContainer
var _title: Label
var _header: HBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuTheme.build()
	UiArt.smooth(self)
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.08, 0.5)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"MenuPanel"
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_panel.add_child(column)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 6)
	column.add_child(_header)
	_title = Label.new()
	_title.text = title_text
	_title.theme_type_variation = &"MenuTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.add_child(_title)
	var close_button := Button.new()
	close_button.icon = MenuTheme.close_icon()
	close_button.tooltip_text = "Cerrar (Esc)"
	close_button.theme_type_variation = &"FlatButton"
	close_button.custom_minimum_size = Vector2(24, 22)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	_header.add_child(close_button)

	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	column.add_child(body)

	resized.connect(_fit)
	_build()


## Para las subclases: arma el contenido fijo de la ventana.
func _build() -> void:
	pass


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	Game.push_modal()
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func close() -> void:
	if not visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	visible = false
	Game.pop_modal()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed \
			and not event.echo and event.physical_keycode == KEY_ESCAPE):
		# Escribiendo en un campo, "P" es una letra (Esc sí cierra).
		if get_viewport().gui_get_focus_owner() is LineEdit and not (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
			return
		close()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null:
		return
	var screen := get_viewport_rect().size
	var fitted := Vector2(minf(panel_size.x, screen.x - 12), minf(panel_size.y, screen.y - 12))
	_panel.size = fitted
	_panel.position = ((screen - fitted) / 2.0).floor()


# --- Piezas que usan varias ventanas ---------------------------------------------

## Fila con icono, nombre, detalle a la derecha y botones. Con `wrap` el
## nombre ocupa las líneas que necesite en vez de recortarse.
static func row(icon: Texture2D, text: String, detail := "", detail_color := MenuTheme.TEXT_DIM, wrap := false) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	if icon:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(20, 20)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(label)
	if not detail.is_empty():
		var extra := Label.new()
		extra.text = detail
		extra.add_theme_color_override("font_color", detail_color)
		extra.add_theme_font_override("font", UiArt.FONT_BOLD)
		extra.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(extra)
	return box


static func small_button(parent: Node, text: String, action: Callable, variation := &"") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", 9)
	button.custom_minimum_size = Vector2(0, 20)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Lista con desplazamiento que ocupa el espacio que sobra.
static func scroll_list(parent: Node, separation := 3) -> VBoxContainer:
	var scroll := TouchScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", separation)
	scroll.add_child(list)
	return list


static func hint(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HintLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## "45 s", "8 min", "3 h".
static func format_wait(seconds: float) -> String:
	if seconds < 90.0:
		return "%d s" % maxi(1, ceili(seconds))
	if seconds < 5400.0:
		return "%d min" % ceili(seconds / 60.0)
	return "%d h" % ceili(seconds / 3600.0)
