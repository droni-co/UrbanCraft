extends Control
## Escena inicial: verifica la conexión con el backend.

@onready var status_label: Label = %StatusLabel
@onready var retry_button: Button = %RetryButton


func _ready() -> void:
	retry_button.pressed.connect(_check_backend)
	_check_backend()


func _check_backend() -> void:
	retry_button.disabled = true
	status_label.text = "Conectando con %s ..." % Api.base_url
	var res := await Api.health()
	if res.ok:
		status_label.text = "Backend OK · base de datos: %s" % res.data.get("database", "?")
	else:
		status_label.text = "Sin conexión con el backend (%s)" % res.error
	retry_button.disabled = false
