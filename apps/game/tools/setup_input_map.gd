extends SceneTree
## Define el InputMap del juego (teclado, gamepad) y lo guarda en project.godot.
## Uso:  pnpm game:input
## Edita aquí y vuelve a ejecutar, o ajústalo luego en Proyecto > Configuración > Mapa de entrada.


func _initialize() -> void:
	var actions := {
		"move_up": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP)],
		"move_down": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)],
		"run": [_key(KEY_SHIFT), _button(JOY_BUTTON_B)],
		"interact": [_key(KEY_E), _key(KEY_SPACE), _button(JOY_BUTTON_A)],
		"zoom_in": [_key(KEY_EQUAL), _key(KEY_KP_ADD), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		"zoom_out": [_key(KEY_MINUS), _key(KEY_KP_SUBTRACT), _button(JOY_BUTTON_LEFT_SHOULDER)],
		"pause": [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)],
	}
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, {"deadzone": 0.2, "events": actions[action_name]})
	var err := ProjectSettings.save()
	print("InputMap guardado (%d acciones): %s" % [actions.size(), error_string(err)])
	quit(0 if err == OK else 1)


func _key(physical: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = physical
	return e


func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e
