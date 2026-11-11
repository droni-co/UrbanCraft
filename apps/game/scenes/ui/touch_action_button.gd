@tool
class_name TouchActionButton
extends Control
## Botón táctil circular multitáctil que presiona una acción del InputMap.
## Funciona a la vez que el joystick (cada uno sigue su propio dedo).

@export var action := &"interact"
@export var text := "A":
	set(value):
		text = value
		queue_redraw()
@export var radius := 28.0:
	set(value):
		radius = value
		queue_redraw()
@export var color := Color(1, 1, 1, 0.3)
## Si es true, cada toque alterna la acción (útil para "correr").
@export var toggle := false

var _touch_index := -1
var _toggled := false


func is_pressed() -> bool:
	return _touch_index != -1 or _toggled


func _ready() -> void:
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_touch_index = -1
			_toggled = false
			if not Engine.is_editor_hint():
				Input.action_release(action)
			queue_redraw()
	)


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree() or not event is InputEventScreenTouch:
		return
	var center := global_position + size / 2.0
	if event.pressed and _touch_index == -1 and event.position.distance_to(center) <= radius * 1.25:
		_touch_index = event.index
		if toggle:
			_toggled = not _toggled
			if _toggled:
				Input.action_press(action)
			else:
				Input.action_release(action)
		else:
			Input.action_press(action)
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif not event.pressed and event.index == _touch_index:
		_touch_index = -1
		if not toggle:
			Input.action_release(action)
		get_viewport().set_input_as_handled()
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var fill := Color(color, color.a + 0.3) if is_pressed() else color
	draw_circle(center, radius, Color(0, 0, 0, 0.3))
	draw_circle(center, radius - 2.0, fill)
	draw_arc(center, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.0, true)
	var font := get_theme_default_font()
	var font_size := int(radius * 0.7)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x / 2.0, text_size.y / 3.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
