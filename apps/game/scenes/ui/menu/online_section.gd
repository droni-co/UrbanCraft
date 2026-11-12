class_name OnlineSection
extends VBoxContainer
## Sección "Multijugador" del menú: estado de la conexión, jugadores en tu
## radio, modo fantasma (que no te vean) y saludar.

signal wave_requested

var _status: Label
var _visible_check: CheckButton
var _voice_button: Button
var _open_mic_check: CheckButton
var _voice_hint: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if theme == null:
		theme = MenuTheme.build()

	var title := Label.new()
	title.text = "Multijugador"
	title.theme_type_variation = &"SectionTitle"
	add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_visible_check = CheckButton.new()
	_visible_check.text = "Visible para otros jugadores"
	_visible_check.button_pressed = GameSettings.online_visible
	_visible_check.toggled.connect(func(on: bool) -> void: GameSettings.online_visible = on)
	add_child(_visible_check)

	var hint := Label.new()
	hint.text = "Los demás te ven en el mapa y tú a ellos. Empiezas en tu ubicación real: " \
		+ "si no quieres que te vean cerca de casa, desactívalo (modo fantasma) o teletranspórtate. " \
		+ "En el minimapa los jugadores lejanos salen como puntos aproximados."
	hint.theme_type_variation = &"HintLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	add_child(HSeparator.new())
	var voice_title := Label.new()
	voice_title.text = "Voz con amigos"
	voice_title.theme_type_variation = &"SectionTitle"
	add_child(voice_title)

	_voice_button = Button.new()
	_voice_button.custom_minimum_size.y = 24
	_voice_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_voice_button.pressed.connect(Voice.toggle)
	add_child(_voice_button)

	_open_mic_check = CheckButton.new()
	_open_mic_check.text = "Micrófono abierto (sin mantener V)"
	_open_mic_check.button_pressed = GameSettings.voice_open_mic
	_open_mic_check.toggled.connect(func(on: bool) -> void: GameSettings.voice_open_mic = on)
	add_child(_open_mic_check)

	_voice_hint = Label.new()
	_voice_hint.theme_type_variation = &"HintLabel"
	_voice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_voice_hint)
	Voice.changed.connect(_refresh)

	add_child(HSeparator.new())
	var wave := Button.new()
	wave.text = "Saludar (G)"
	wave.custom_minimum_size.y = 24
	wave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wave.pressed.connect(func() -> void: wave_requested.emit())
	add_child(wave)

	Online.status_changed.connect(func(_s: String) -> void: _refresh())
	Online.radar_updated.connect(_refresh)
	GameSettings.online_settings_changed.connect(_refresh)
	_refresh()


func focus_first() -> void:
	_visible_check.grab_focus()


func _refresh() -> void:
	_visible_check.set_pressed_no_signal(GameSettings.online_visible)
	_open_mic_check.set_pressed_no_signal(GameSettings.voice_open_mic)
	if Voice.starting:
		_voice_button.text = "Pidiendo el micrófono…"
	elif Voice.enabled:
		var n := Voice.connected_count()
		_voice_button.text = "Salir de la voz (%s)" % ("sin amigos conectados" if n == 0 else "1 amigo" if n == 1 else "%d amigos" % n)
	else:
		_voice_button.text = "Activar voz"
	var reason := Voice.unavailable_reason() if not Voice.enabled else ""
	_voice_button.disabled = reason != "" and not Voice.starting
	_voice_hint.text = (reason + "\n" if reason != "" else "") \
		+ "Oyes a tus amigos en línea que también tengan la voz activa, y ellos a ti. " \
		+ "El audio va directo entre jugadores, así que tus amigos pueden ver tu dirección IP. " \
		+ "Toca un nombre en la lista de la derecha para silenciarlo. Con micrófono abierto usa audífonos para evitar eco."
	match Online.status:
		"online":
			var others := Online.others_in_range()
			var radius := Online.radar_radius_meters
			var where := ("%d m" % radius) if radius < 1000.0 else ("%s km" % String.num(radius / 1000.0, 1).trim_suffix(".0"))
			_status.text = "● Conectado · %s a menos de %s" % [
				"nadie" if others == 0 else ("1 jugador" if others == 1 else "%d jugadores" % others), where]
			_status.add_theme_color_override("font_color", MenuTheme.SUCCESS)
		"connecting":
			_status.text = "● Conectando…"
			_status.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		_:
			_status.text = "● Sin conexión (solo con el mapa real y el servidor en línea)"
			_status.add_theme_color_override("font_color", MenuTheme.DANGER)
