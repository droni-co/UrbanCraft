class_name TeleportSection
extends VBoxContainer
## Sección del menú: teletransportarse a una latitud/longitud.
##
## Acepta decimales con punto o coma ("4,6097") y pegar el par completo
## ("4.6097, -74.0817", como lo copia Google Maps) en cualquiera de los campos.
## No mueve al jugador por sí misma: emite señales y el mundo hace el resto.

signal teleport_requested(latitude: float, longitude: float)
signal home_requested

const MAX_LAT := 85.0  # límite de la proyección Web Mercator

## Devuelve la posición actual del jugador como PackedFloat64Array [lat, lon], o null.
var current_position_provider: Callable

var _lat_edit: LineEdit
var _lon_edit: LineEdit
var _error_label: Label
var _status_label: Label
var _go_button: Button
var _home_button: Button

# Par "lat, lon": separado por "; ", ", " o espacios, o "4.1,-74.2" (con puntos).
# "4,6097" sin espacio es un decimal con coma, no un par.
var _pair_regexes: Array[RegEx] = [
	RegEx.create_from_string("^\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:;|,\\s|\\s)\\s*(-?\\d+(?:\\.\\d+)?)\\s*$"),
	RegEx.create_from_string("^\\s*(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)\\s*$"),
]
var _number_regex := RegEx.create_from_string("^\\s*-?\\d+(?:[.,]\\d+)?\\s*$")


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Teletransporte"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"HintLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	add_child(fields)
	_lat_edit = _field(fields, "Latitud", "4.6097")
	_lon_edit = _field(fields, "Longitud", "-74.0817")

	var hint := Label.new()
	hint.text = "Puedes pegar «lat, lon» en cualquier campo (p. ej. copiado de Google Maps)."
	hint.theme_type_variation = &"HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", MenuTheme.DANGER)
	_error_label.add_theme_font_size_override("font_size", 9)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	add_child(_error_label)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	add_child(actions)
	_go_button = _button(actions, "Teletransportarse", &"PrimaryButton", _submit)
	_button(actions, "Usar posición actual", &"", _fill_current)
	_home_button = _button(actions, "Volver a mi ubicación real", &"", func() -> void: home_requested.emit())

	var note := Label.new()
	note.text = "Si nadie ha visitado la zona, el mapa puede tardar hasta un minuto en generarse."
	note.theme_type_variation = &"HintLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)

	visibility_changed.connect(_refresh)
	LocationService.location_changed.connect(func(_lat: float, _lon: float) -> void: _refresh())
	_refresh()


func focus_first() -> void:
	_lat_edit.grab_focus()
	_lat_edit.select_all()


## Lee los campos. Devuelve PackedFloat64Array [lat, lon] (float64, sin perder
## precisión) o null (y muestra el error).
func parse_fields() -> Variant:
	if not _split_pair(_lat_edit):
		_split_pair(_lon_edit)
	var lat_text := _lat_edit.text.strip_edges()
	var lon_text := _lon_edit.text.strip_edges()
	if lat_text.is_empty() or lon_text.is_empty():
		return _fail("Escribe la latitud y la longitud.")
	if not _number_regex.search(lat_text):
		return _fail("La latitud no es un número válido.")
	if not _number_regex.search(lon_text):
		return _fail("La longitud no es un número válido.")
	var lat := float(lat_text.replace(",", "."))
	var lon := float(lon_text.replace(",", "."))
	if absf(lat) > MAX_LAT:
		return _fail("La latitud debe estar entre -%d y %d." % [MAX_LAT, MAX_LAT])
	if absf(lon) > 180.0:
		return _fail("La longitud debe estar entre -180 y 180.")
	_error_label.visible = false
	return PackedFloat64Array([lat, lon])


# --- Interno ----------------------------------------------------------------------

func _submit() -> void:
	var value: Variant = parse_fields()
	if value == null:
		return
	teleport_requested.emit(value[0], value[1])


func _fill_current() -> void:
	var pos: Variant = current_position_provider.call() if current_position_provider.is_valid() else null
	if pos == null:
		pos = PackedFloat64Array([LocationService.latitude, LocationService.longitude])
	_set_fields(pos[0], pos[1])
	_error_label.visible = false


func _set_fields(lat: float, lon: float) -> void:
	_lat_edit.text = "%.5f" % lat
	_lon_edit.text = "%.5f" % lon
	_lat_edit.set_meta(&"prev_len", _lat_edit.text.length())
	_lon_edit.set_meta(&"prev_len", _lon_edit.text.length())


## Si se pega "lat, lon" en un campo, reparte los dos valores. Solo al pegar
## (entran varios caracteres de golpe), para no partir lo que se va tecleando.
func _on_text_changed(text: String, edit: LineEdit) -> void:
	var previous: int = edit.get_meta(&"prev_len", 0)
	edit.set_meta(&"prev_len", text.length())
	_error_label.visible = false
	if text.length() - previous > 1:
		_split_pair(edit)


func _split_pair(edit: LineEdit) -> bool:
	var clean := edit.text.replace("°", "")
	for regex in _pair_regexes:
		var m := regex.search(clean)
		if m:
			_lat_edit.text = m.get_string(1)
			_lon_edit.text = m.get_string(2)
			_lat_edit.set_meta(&"prev_len", _lat_edit.text.length())
			_lon_edit.set_meta(&"prev_len", _lon_edit.text.length())
			edit.caret_column = edit.text.length()
			return true
	return false


func _refresh() -> void:
	if _status_label == null:
		return
	var here := "%.5f, %.5f" % [LocationService.latitude, LocationService.longitude]
	if LocationService.is_teleported():
		_status_label.text = "Estás teletransportado en %s." % here
	else:
		_status_label.text = "Tu zona actual: %s (%s)." % [here, LocationService.source_name()]
	_home_button.visible = LocationService.is_teleported()


func _fail(message: String) -> Variant:
	_error_label.text = message
	_error_label.visible = true
	return null


func _field(parent: Container, label_text: String, placeholder: String) -> LineEdit:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"HintLabel"
	box.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = 24
	# Teclado por defecto: el numérico de algunos móviles no tiene el signo menos.
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	edit.clear_button_enabled = true
	edit.text_changed.connect(_on_text_changed.bind(edit))
	edit.text_submitted.connect(func(_t: String) -> void: _submit())
	box.add_child(edit)
	return edit


func _button(parent: Container, text: String, variation: StringName, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 24
	if variation != &"":
		button.theme_type_variation = variation
	button.pressed.connect(action)
	parent.add_child(button)
	return button
