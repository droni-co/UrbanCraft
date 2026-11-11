extends Control
## Pantalla inicial: verifica el backend y entra al mundo (también sin conexión).

const WORLD_SCENE := "res://scenes/world/world.tscn"

@onready var status_label: Label = %StatusLabel
@onready var play_button: Button = %PlayButton
@onready var retry_button: Button = %RetryButton


func _ready() -> void:
	play_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(WORLD_SCENE))
	retry_button.pressed.connect(_check_backend)
	play_button.grab_focus()
	_check_backend()


func _check_backend() -> void:
	retry_button.disabled = true
	status_label.text = "Conectando con %s ..." % Api.base_url
	var res := await Api.health()
	if res.ok:
		status_label.text = "Servidor en línea"
	else:
		status_label.text = "Sin conexión con el servidor — puedes jugar offline"
	retry_button.disabled = false
