extends Control
## Pantalla inicial: verifica el backend, exige iniciar sesión y entra al mundo.
##
## Sin sesión no se puede jugar. Con una sesión guardada se puede entrar aunque
## el servidor no responda (se usa el mapa de demostración).
## Para depurar: botón de usuario de prueba (builds de depuración) o
##     godot --path apps/game -- --dev-login=ana

const WORLD_SCENE := "res://scenes/world/world.tscn"

@onready var status_label: Label = %StatusLabel
@onready var play_button: Button = %PlayButton
@onready var retry_button: Button = %RetryButton

var _account: AccountSection
var _online := false
var _first_check := true


func _ready() -> void:
	Online.stop()  # fuera del mundo no se aparece para los demás
	_account = AccountSection.new()
	_account.compact = true
	var center := play_button.get_parent()
	center.add_child(_account)
	center.move_child(_account, play_button.get_index())

	play_button.pressed.connect(_play)
	retry_button.pressed.connect(_check_backend)
	Auth.session_changed.connect(func(_user: Dictionary) -> void: _refresh_play())
	_refresh_play()
	_check_backend()


func _play() -> void:
	if Auth.is_signed_in():
		get_tree().change_scene_to_file(WORLD_SCENE)


func _refresh_play() -> void:
	var can_play := Auth.is_signed_in()
	play_button.disabled = not can_play
	play_button.tooltip_text = "" if can_play else "Inicia sesión para jugar"
	if can_play:
		play_button.grab_focus()


func _check_backend() -> void:
	retry_button.disabled = true
	status_label.text = "Conectando con %s ..." % Api.base_url
	var res := await Api.health()
	_online = res.ok
	if _online:
		status_label.text = "Servidor en línea"
		await Auth.wait_startup()
		if Auth.is_signed_in() and not _first_check:
			await Auth.refresh_profile()  # al reintentar: el token pudo caducar
		await _account.refresh_methods()
	elif Auth.is_signed_in():
		status_label.text = "Sin conexión con el servidor: se usará el mapa de demostración"
	else:
		status_label.text = "Sin conexión con el servidor: no se puede iniciar sesión"
	_first_check = false
	retry_button.disabled = false
	_refresh_play()
