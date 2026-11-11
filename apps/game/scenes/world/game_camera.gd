class_name GameCamera
extends Camera2D
## Cámara que sigue al jugador y centraliza el input de puntero sobre el mundo:
## - PC: clic izquierdo -> tapped, rueda -> zoom, mover ratón -> hovered
## - Móvil: toque corto -> tapped, pellizco -> zoom
## - Teclado/gamepad: acciones zoom_in / zoom_out

signal tapped(world_position: Vector2)
signal hovered(world_position: Vector2)

@export var target: Node2D
@export_range(0.25, 8.0, 0.05) var min_zoom := 0.75
@export_range(0.25, 8.0, 0.05) var max_zoom := 3.0
@export var zoom_step := 0.25
## Distancia máxima (px) que puede moverse un dedo para contar como "tap".
@export var tap_max_distance := 16.0

var _touches := {}  # index -> Vector2
var _tap_index := -1
var _tap_start := Vector2.ZERO
var _pinch_start_distance := 0.0
var _pinch_start_zoom := 1.0


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _physics_process(_delta: float) -> void:
	if target:
		global_position = target.global_position


func snap_to_target() -> void:
	if target:
		global_position = target.global_position
	reset_smoothing()


func apply_limits(bounds: Rect2) -> void:
	limit_left = floori(bounds.position.x)
	limit_top = floori(bounds.position.y)
	limit_right = ceili(bounds.end.x)
	limit_bottom = ceili(bounds.end.y)


func zoom_level() -> float:
	return zoom.x


func set_zoom_level(level: float) -> void:
	var z := clampf(level, min_zoom, max_zoom)
	zoom = Vector2(z, z)


func screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		set_zoom_level(zoom_level() + zoom_step)
	elif event.is_action_pressed("zoom_out"):
		set_zoom_level(zoom_level() - zoom_step)
	elif event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMagnifyGesture:
		set_zoom_level(zoom_level() * event.factor)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		hovered.emit(screen_to_world(event.position))


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			set_zoom_level(zoom_level() + zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_level(zoom_level() - zoom_step)
		MOUSE_BUTTON_LEFT:
			# Si el ratón emula toques (modo --touch), el tap llega por _on_touch.
			if not Input.emulate_touch_from_mouse:
				tapped.emit(screen_to_world(event.position))


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_start = event.position
		else:
			_tap_index = -1  # dos dedos = pellizco, no tap
			_begin_pinch()
		return

	if event.index == _tap_index and event.position.distance_to(_tap_start) <= tap_max_distance:
		tapped.emit(screen_to_world(event.position))
	_touches.erase(event.index)
	if event.index == _tap_index or _touches.is_empty():
		_tap_index = -1
	if _touches.size() >= 2:
		_begin_pinch()


func _on_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if event.index == _tap_index and event.position.distance_to(_tap_start) > tap_max_distance:
		_tap_index = -1
	if _touches.size() >= 2 and _pinch_start_distance > 0.0:
		set_zoom_level(_pinch_start_zoom * _pinch_distance() / _pinch_start_distance)


func _begin_pinch() -> void:
	_pinch_start_distance = _pinch_distance()
	_pinch_start_zoom = zoom_level()


func _pinch_distance() -> float:
	var points := _touches.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
