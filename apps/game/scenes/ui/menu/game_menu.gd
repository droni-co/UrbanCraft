class_name GameMenu
extends Control
## Menú del jugador: modal centrado sobre un fondo oscuro, con secciones.
##
## Para agregar una opción de configuración nueva, crea un Control (como
## TeleportSection) y regístralo con add_section("Título", control).
## En pantallas angostas (móvil en vertical) la lista de secciones pasa arriba.
##
## Mientras está abierto el juego se pausa (el jugador no se mueve al escribir).
## El nodo procesa siempre (process_mode = ALWAYS) para funcionar en pausa.

signal opened
signal closed

const PANEL_MAX := Vector2(600, 320)
const NARROW_WIDTH := 480.0

var _backdrop: ColorRect
var _panel: PanelContainer
var _layout: BoxContainer
var _nav: BoxContainer
var _content: MarginContainer
var _nav_group := ButtonGroup.new()
var _sections: Array[Dictionary] = []  # {title, control, button}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# "and_offsets": set_anchors_preset() solo conservaría el tamaño actual (0x0)
	# y el menú no seguiría al viewport al cambiar la ventana (maximizar).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuTheme.build()
	visible = false

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.55)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"MenuPanel"
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)

	# Cabecera: título y cerrar
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Menú"
	title.theme_type_variation = &"MenuTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.icon = MenuTheme.close_icon()
	close_button.tooltip_text = "Cerrar (Esc)"
	close_button.theme_type_variation = &"FlatButton"
	close_button.custom_minimum_size = Vector2(24, 24)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(HSeparator.new())

	# Cuerpo: navegación + contenido
	_layout = BoxContainer.new()
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 8)
	column.add_child(_layout)

	_nav = BoxContainer.new()
	_nav.vertical = true
	_nav.custom_minimum_size.x = 120
	_nav.add_theme_constant_override("separation", 2)
	_layout.add_child(_nav)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_layout.add_child(scroll)
	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("margin_right", 6)
	scroll.add_child(_content)

	resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit()


## Esc cierra siempre, incluso escribiendo en un campo (que si no se la come).
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## P / Start cierran si no los consumió un campo de texto.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


# --- API --------------------------------------------------------------------------

func add_section(title: String, control: Control) -> void:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.button_group = _nav_group
	button.theme_type_variation = &"NavButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_nav.add_child(button)
	var section := {"title": title, "control": control, "button": button}
	button.pressed.connect(_show_section.bind(_sections.size()))
	_sections.append(section)
	control.visible = false
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(control)
	if _sections.size() == 1:
		_show_section(0)


## Cambia el texto del botón de una sección (p. ej. "Amigos (2)"); el título
## con el que se abre (open()) no cambia.
func set_section_label(control: Control, text: String) -> void:
	for s in _sections:
		if s.control == control:
			s.button.text = text


func open(section_title := "") -> void:
	for i in _sections.size():
		if _sections[i].title == section_title:
			_show_section(i)
	visible = true
	get_tree().paused = true
	_fit()
	# Foco para teclado/gamepad (en táctil no, para no abrir el teclado virtual).
	if not GameSettings.touch_controls_enabled:
		var current := _current_section()
		if current and current.has_method("focus_first"):
			current.focus_first()
	opened.emit()


func close() -> void:
	if not visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	visible = false
	get_tree().paused = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


# --- Interno ----------------------------------------------------------------------

func _show_section(index: int) -> void:
	# set_pressed_no_signal() no desmarca a los demás del ButtonGroup: se hace a mano.
	for i in _sections.size():
		_sections[i].control.visible = i == index
		_sections[i].button.set_pressed_no_signal(i == index)


func _current_section() -> Control:
	for s in _sections:
		if s.control.visible:
			return s.control
	return null


## Tamaño del panel según la pantalla; en pantallas angostas la navegación va arriba.
func _fit() -> void:
	if _panel == null:
		return
	var screen := get_viewport_rect().size
	var panel_size := Vector2(minf(PANEL_MAX.x, screen.x - 16), minf(PANEL_MAX.y, screen.y - 16))
	_panel.size = panel_size
	_panel.position = ((screen - panel_size) / 2.0).floor()
	var narrow := screen.x < NARROW_WIDTH
	_layout.vertical = narrow
	_nav.vertical = not narrow
	_nav.custom_minimum_size.x = 0 if narrow else 120
