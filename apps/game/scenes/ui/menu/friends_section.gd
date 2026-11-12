class_name FriendsSection
extends VBoxContainer
## Sección "Amigos" del menú: buscar jugadores por su apodo exacto y enviarles
## una solicitud, la bandeja de solicitudes recibidas (aceptar / rechazar) y la
## lista de amigos con sus acciones.
##
## Acciones con un amigo: por ahora "Ir" (teletransportarse a donde está). Para
## agregar otra, súmala en _friend_row(). No mueve al jugador por sí misma:
## emite teleport_requested y el mundo hace el resto.

signal teleport_requested(latitude: float, longitude: float, nickname: String)

var _search_edit: LineEdit
var _search_button: Button
var _result_box: HBoxContainer
var _message: Label
var _incoming_title: Label
var _incoming_list: VBoxContainer
var _outgoing_title: Label
var _outgoing_list: VBoxContainer
var _friends_title: Label
var _friends_list: VBoxContainer
var _empty_hint: Label
## Botón "Eliminar" que espera la confirmación (segundo clic).
var _confirm_remove: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	var title := Label.new()
	title.text = "Amigos"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	# Buscar
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	add_child(search_row)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Apodo exacto del jugador"
	_search_edit.max_length = 20
	_search_edit.clear_button_enabled = true
	_search_edit.custom_minimum_size.y = 24
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_submitted.connect(func(_t: String) -> void: _search())
	_search_edit.text_changed.connect(func(_t: String) -> void: _clear_result())
	search_row.add_child(_search_edit)
	_search_button = _button(search_row, "Buscar", _search, &"PrimaryButton")

	_result_box = HBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 6)
	_result_box.visible = false
	add_child(_result_box)

	_message = Label.new()
	_message.theme_type_variation = &"HintLabel"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false
	add_child(_message)

	add_child(HSeparator.new())
	_incoming_title = _section_title("Solicitudes recibidas")
	_incoming_list = _list()
	_friends_title = _section_title("Mis amigos")
	_friends_list = _list()
	_empty_hint = Label.new()
	_empty_hint.text = "Aún no tienes amigos. Busca a alguien por su apodo para enviarle una solicitud."
	_empty_hint.theme_type_variation = &"HintLabel"
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_hint)
	_outgoing_title = _section_title("Solicitudes enviadas")
	_outgoing_list = _list()

	var note := Label.new()
	note.text = "«Ir» te lleva a donde está tu amigo si está conectado y visible. " \
		+ "Tus amigos también pueden ir a donde estás tú (el modo fantasma lo impide)."
	note.theme_type_variation = &"HintLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)

	Friends.changed.connect(_rebuild)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			Friends.refresh())
	_rebuild()


func focus_first() -> void:
	_search_edit.grab_focus()


# --- Buscar y enviar --------------------------------------------------------------

func _search() -> void:
	var nickname := _search_edit.text.strip_edges()
	if nickname.is_empty():
		_show_message("Escribe el apodo exacto del jugador.", MenuTheme.DANGER)
		return
	_search_button.disabled = true
	var res: Dictionary = await Friends.search(nickname)
	_search_button.disabled = false
	_clear_result()
	if not res.ok:
		_show_message(res.message, MenuTheme.DANGER)
		return
	_show_message("")
	_show_result(res.user)


func _show_result(user: Dictionary) -> void:
	_result_box.visible = true
	var nick_label := Label.new()
	nick_label.text = str(user.nickname)
	nick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick_label.clip_text = true
	_result_box.add_child(nick_label)
	match str(user.relation):
		"none":
			_button(_result_box, "Enviar solicitud", func() -> void: _send(str(user.nickname)), &"PrimaryButton")
		"incoming":
			_button(_result_box, "Aceptar su solicitud", func() -> void: _send(str(user.nickname)), &"PrimaryButton")
		"outgoing":
			_disabled(_result_box, "Solicitud enviada")
		"friend":
			_disabled(_result_box, "Ya son amigos")
		"self":
			_disabled(_result_box, "Eres tú")


func _send(nickname: String) -> void:
	_set_buttons_disabled(_result_box, true)
	var res: Dictionary = await Friends.send_request(nickname)
	_show_message(res.message, MenuTheme.SUCCESS if res.ok else MenuTheme.DANGER)
	if res.ok:
		_clear_result()
		_search_edit.text = ""
	else:
		_set_buttons_disabled(_result_box, false)


func _clear_result() -> void:
	for child in _result_box.get_children():
		child.queue_free()
	_result_box.visible = false


# --- Listas -----------------------------------------------------------------------

func _rebuild() -> void:
	_confirm_remove = null
	for list: Container in [_incoming_list, _outgoing_list, _friends_list]:
		for child in list.get_children():
			child.queue_free()

	for request: Dictionary in Friends.incoming:
		var row := _row(_incoming_list, str(request.user.nickname))
		var id := int(request.id)
		_button(row, "Aceptar", _act.bind(row, Friends.accept.bind(id)), &"PrimaryButton")
		_button(row, "Rechazar", _act.bind(row, Friends.reject.bind(id)))
	_incoming_title.text = "Solicitudes recibidas (%d)" % Friends.incoming.size()
	_incoming_title.visible = not Friends.incoming.is_empty()
	_incoming_list.visible = _incoming_title.visible

	for friend: Dictionary in Friends.friends:
		_friend_row(friend)
	_friends_title.text = "Mis amigos (%d)" % Friends.friends.size()
	_empty_hint.visible = Friends.friends.is_empty()

	for request: Dictionary in Friends.outgoing:
		var row := _row(_outgoing_list, str(request.user.nickname))
		var id := int(request.id)
		_button(row, "Cancelar", _act.bind(row, Friends.reject.bind(id)))
	_outgoing_title.visible = not Friends.outgoing.is_empty()
	_outgoing_list.visible = _outgoing_title.visible


func _friend_row(friend: Dictionary) -> void:
	var online := bool(friend.get("online", false))
	var row := _row(_friends_list, "● " + str(friend.nickname))
	var nick_label: Label = row.get_child(0)
	nick_label.add_theme_color_override("font_color", MenuTheme.SUCCESS if online else MenuTheme.TEXT_DIM)
	nick_label.tooltip_text = "En línea" if online else "Desconectado"
	nick_label.mouse_filter = Control.MOUSE_FILTER_PASS

	var go := _button(row, "Ir", Callable(), &"PrimaryButton")
	go.disabled = not online
	go.tooltip_text = "Teletransportarte a donde está" if online else "Solo si está conectado"
	go.pressed.connect(_go_to.bind(friend, go))

	var remove := _button(row, "Eliminar", Callable())
	remove.pressed.connect(_remove.bind(friend, remove))


func _go_to(friend: Dictionary, button: Button) -> void:
	button.disabled = true
	var res: Dictionary = await Friends.locate(int(friend.id))
	if is_instance_valid(button):
		button.disabled = false
	if not res.ok:
		_show_message(res.message, MenuTheme.DANGER)
		return
	teleport_requested.emit(res.lat, res.lon, str(friend.nickname))


## Eliminar pide confirmación: el primer clic cambia el texto, el segundo elimina.
func _remove(friend: Dictionary, button: Button) -> void:
	if _confirm_remove != button:
		if is_instance_valid(_confirm_remove):
			_confirm_remove.text = "Eliminar"
		_confirm_remove = button
		button.text = "¿Seguro?"
		return
	var res: Dictionary = await Friends.remove(int(friend.id))
	_show_message("Ya no eres amigo de %s." % friend.nickname if res.ok else res.message,
		MenuTheme.TEXT_DIM if res.ok else MenuTheme.DANGER)


## Ejecuta una acción de la bandeja (aceptar, rechazar, cancelar) con los
## botones de la fila deshabilitados mientras tanto.
func _act(row: Container, action: Callable) -> void:
	_set_buttons_disabled(row, true)
	var res: Dictionary = await action.call()
	if not res.ok:
		_show_message(res.message, MenuTheme.DANGER)
		if is_instance_valid(row):
			_set_buttons_disabled(row, false)


# --- Utilidades -------------------------------------------------------------------

func _show_message(text: String, color := MenuTheme.TEXT_DIM) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = not text.is_empty()


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label


func _list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	return list


func _row(list: Container, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	return row


func _button(parent: Container, text: String, action: Callable, variation := &"") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 24
	if variation != &"":
		button.theme_type_variation = variation
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button


func _disabled(parent: Container, text: String) -> void:
	_button(parent, text, Callable()).disabled = true


func _set_buttons_disabled(container: Container, disabled: bool) -> void:
	for child in container.get_children():
		if child is Button:
			child.disabled = disabled
