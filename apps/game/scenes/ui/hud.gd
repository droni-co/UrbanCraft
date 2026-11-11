class_name Hud
extends CanvasLayer
## HUD del juego: info de depuración, estado del servidor, mensajes,
## controles táctiles y pausa. Corre siempre (process_mode = ALWAYS).

@onready var info_label: Label = %InfoLabel
@onready var status_label: Label = %StatusLabel
@onready var message_label: Label = %MessageLabel
@onready var touch_controls: Control = %TouchControls
@onready var pause_overlay: Control = %PauseOverlay

var _message_tween: Tween


func _ready() -> void:
	touch_controls.visible = GameSettings.touch_controls_enabled
	GameSettings.touch_controls_changed.connect(func(enabled: bool) -> void: touch_controls.visible = enabled)
	pause_overlay.visible = false
	message_label.modulate.a = 0.0
	set_online(false)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		toggle_pause()


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_overlay.visible = get_tree().paused


func set_info(text: String) -> void:
	info_label.text = text


func set_online(online: bool) -> void:
	status_label.text = "● En línea" if online else "● Sin conexión"
	status_label.modulate = Color("7ee787") if online else Color("ff7b72")


func show_message(text: String, duration := 2.0) -> void:
	message_label.text = text
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(message_label, "modulate:a", 1.0, 0.15)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.4)
