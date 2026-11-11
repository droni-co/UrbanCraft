class_name AccountSection
extends VBoxContainer
## Cuenta del jugador: iniciar sesión con Google, apodo y cerrar sesión.
## Se usa en el menú del juego y, en modo compacto, en la pantalla inicial.

## Compacto: sin título ni editor de apodo (pantalla inicial).
@export var compact := false

var _title: Label
var _status: Label
var _detail: Label
var _message: Label
var _google_button: Button
## Usuarios de prueba: solo en builds de depuración y si el servidor lo permite.
var _dev_box: HBoxContainer
var _dev_name: LineEdit
var _waiting_box: HFlowContainer
var _nickname_box: VBoxContainer
var _nickname_edit: LineEdit
var _save_button: Button
var _logout_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	_title = Label.new()
	_title.text = "Cuenta"
	_title.theme_type_variation = &"SectionTitle"
	_title.visible = not compact
	add_child(_title)

	_status = _label(&"", true)
	_detail = _label(&"HintLabel", true)

	_google_button = Button.new()
	_google_button.text = "Continuar con Google"
	_google_button.theme_type_variation = &"GoogleButton"
	_google_button.custom_minimum_size = Vector2(0, 26)
	_google_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_BEGIN
	_google_button.pressed.connect(_on_google_pressed)
	add_child(_google_button)

	_dev_box = HBoxContainer.new()
	_dev_box.add_theme_constant_override("separation", 6)
	_dev_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_BEGIN
	_dev_box.visible = false
	add_child(_dev_box)
	_dev_name = LineEdit.new()
	_dev_name.text = "tester"
	_dev_name.max_length = 20
	_dev_name.custom_minimum_size = Vector2(90, 24)
	_dev_name.tooltip_text = "El mismo nombre entra siempre al mismo usuario de prueba"
	_dev_name.text_submitted.connect(func(_t: String) -> void: _on_dev_pressed())
	_dev_box.add_child(_dev_name)
	_button(_dev_box, "Entrar como usuario de prueba", _on_dev_pressed)

	_waiting_box = HFlowContainer.new()
	_waiting_box.add_theme_constant_override("h_separation", 6)
	_waiting_box.add_theme_constant_override("v_separation", 6)
	add_child(_waiting_box)
	_button(_waiting_box, "Abrir el navegador otra vez", Auth.open_login_page)
	_button(_waiting_box, "Cancelar", Auth.cancel_login)

	_nickname_box = VBoxContainer.new()
	_nickname_box.add_theme_constant_override("separation", 2)
	add_child(_nickname_box)
	var nick_label := Label.new()
	nick_label.text = "Apodo (lo verán los demás jugadores)"
	nick_label.theme_type_variation = &"HintLabel"
	_nickname_box.add_child(nick_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_nickname_box.add_child(row)
	_nickname_edit = LineEdit.new()
	_nickname_edit.max_length = 20
	_nickname_edit.custom_minimum_size = Vector2(0, 24)
	_nickname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nickname_edit.text_submitted.connect(func(_t: String) -> void: _save_nickname())
	row.add_child(_nickname_edit)
	_save_button = _button(row, "Guardar", _save_nickname)

	_message = _label(&"HintLabel", true)
	_message.visible = false

	_logout_button = _button(self, "Cerrar sesión", _on_logout_pressed)
	_logout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_BEGIN

	Auth.session_changed.connect(func(_user: Dictionary) -> void: _refresh())
	Auth.login_progress.connect(_on_login_progress)
	_refresh()
	refresh_methods()


## Vuelve a preguntar al servidor qué métodos de login ofrece.
func refresh_methods() -> void:
	await Auth.fetch_methods()
	_refresh()


func focus_first() -> void:
	if Auth.is_signed_in() and not compact:
		_nickname_edit.grab_focus()
	elif _google_button.visible:
		_google_button.grab_focus()


# --- Interno ----------------------------------------------------------------------

func _refresh() -> void:
	var signed_in := Auth.is_signed_in()
	var waiting := Auth.is_logging_in
	_google_button.visible = not signed_in and not waiting
	_google_button.disabled = not Auth.methods.google
	_google_button.tooltip_text = "" if Auth.methods.google else "El servidor no tiene configurado el login con Google"
	_dev_box.visible = not signed_in and not waiting and OS.is_debug_build() and Auth.methods.dev
	_waiting_box.visible = waiting
	_nickname_box.visible = signed_in and not compact
	_logout_button.visible = signed_in and not waiting

	if waiting:
		_status.text = "Completa el inicio de sesión en el navegador…"
		_detail.text = "Cuando termines, vuelve aquí: el juego lo detecta solo."
	elif signed_in:
		_status.text = "Sesión iniciada como %s" % Auth.display_name()
		_detail.text = str(Auth.user.get("email", "")) if not compact else ""
		if not _nickname_edit.has_focus():
			_nickname_edit.text = str(Auth.user.get("nickname", ""))
	else:
		_status.text = "Inicia sesión para jugar." if compact else "No has iniciado sesión."
		_detail.text = "" if compact else "Inicia sesión para jugar. Se abrirá tu navegador."
		if not Auth.methods.google:
			_detail.text = "El login con Google no está configurado en el servidor (GOOGLE_CLIENT_ID)."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	_detail.visible = not _detail.text.is_empty()


func _on_google_pressed() -> void:
	_show_message("")
	await Auth.login_with_google()


func _on_dev_pressed() -> void:
	_show_message("")
	var dev_name := _dev_name.text.strip_edges()
	await Auth.login_dev(dev_name if not dev_name.is_empty() else "tester")


func _on_login_progress(state: String, message: String) -> void:
	match state:
		"complete":
			_show_message(message, MenuTheme.SUCCESS)
		"failed":
			_show_message(message, MenuTheme.DANGER)
		"cancelled":
			_show_message(message)
	_refresh()


func _on_logout_pressed() -> void:
	_logout_button.disabled = true
	await Auth.logout()
	_logout_button.disabled = false
	_show_message("Cerraste sesión.")


func _save_nickname() -> void:
	var nickname := _nickname_edit.text.strip_edges()
	if nickname == str(Auth.user.get("nickname", "")):
		return
	_save_button.disabled = true
	var result: Dictionary = await Auth.update_nickname(nickname)
	_save_button.disabled = false
	_show_message(result.message, MenuTheme.SUCCESS if result.ok else MenuTheme.DANGER)
	if result.ok:
		_nickname_edit.release_focus()
		_refresh()


func _show_message(text: String, color := MenuTheme.TEXT_DIM) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = not text.is_empty()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT


func _label(variation: StringName, wrap: bool) -> Label:
	var label := Label.new()
	if variation != &"":
		label.theme_type_variation = variation
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
	add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 24
	button.pressed.connect(action)
	parent.add_child(button)
	return button
