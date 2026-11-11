class_name Player
extends CharacterBody2D
## Jugador controlable.
## - Movimiento directo: teclado / gamepad / joystick virtual (acciones move_*).
## - Movimiento por camino: set_path() (tocar/clic en el mapa, ver world.gd).
##
## El dibujo actual es un placeholder (_draw). Para usar sprites reales, agrega
## un AnimatedSprite2D con animaciones "idle_<dir>" / "walk_<dir>" (dir en
## DIRECTIONS) y reproduce animation_name() en cada frame.

signal interacted(facing: Vector2)
signal path_ended

const DIRECTIONS: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const ARRIVE_DISTANCE := 3.0
const STUCK_TIMEOUT := 0.5

@export var walk_speed := 80.0
@export var run_speed := 150.0
@export var body_color := Color("e85d4a")

var facing := Vector2.DOWN
var is_moving := false

var _path: Array[Vector2] = []
var _stuck_time := 0.0
var _walk_time := 0.0


func set_path(points: Array[Vector2]) -> void:
	_path = points
	_stuck_time = 0.0


func stop() -> void:
	if not _path.is_empty():
		_path.clear()
		path_ended.emit()


func has_path() -> bool:
	return not _path.is_empty()


## Dirección (8 vías) hacia la que mira: "e", "se", "s", ...
func facing_direction() -> String:
	return DIRECTIONS[wrapi(roundi(facing.angle() / (TAU / 8.0)), 0, 8)]


func animation_name() -> String:
	return ("walk_" if is_moving else "idle_") + facing_direction()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector2.ZERO
	var strength := 0.0

	if input != Vector2.ZERO:
		stop()  # el input directo cancela el camino
		direction = input.normalized()
		strength = minf(input.length(), 1.0)
	elif not _path.is_empty():
		direction = _next_path_direction()
		strength = 1.0

	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = direction * speed * strength
	move_and_slide()

	if not _path.is_empty():
		# Si algo nos bloquea (esquina, otro jugador) abandonamos el camino.
		_stuck_time = _stuck_time + delta if get_real_velocity().length() < 10.0 else 0.0
		if _stuck_time > STUCK_TIMEOUT:
			stop()

	is_moving = get_real_velocity().length() > 1.0
	if direction != Vector2.ZERO:
		facing = direction
	_walk_time = _walk_time + delta if is_moving else 0.0

	if Input.is_action_just_pressed("interact"):
		interacted.emit(facing)

	queue_redraw()


func _next_path_direction() -> Vector2:
	var to_next := _path[0] - global_position
	if to_next.length() <= ARRIVE_DISTANCE:
		_path.pop_front()
		if _path.is_empty():
			path_ended.emit()
			return Vector2.ZERO
		to_next = _path[0] - global_position
	return to_next.normalized()


# --- Placeholder visual -------------------------------------------------------

func _draw() -> void:
	var step := sin(_walk_time * 14.0)
	var bob := -absf(step) * 1.5 if is_moving else 0.0

	# Sombra (elipse) e indicador de dirección en el suelo
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	draw_line(Vector2.ZERO, facing * 12.0, Color(1, 1, 1, 0.5), 2.0)

	draw_set_transform(Vector2(0, bob))
	var legs := body_color.darkened(0.45)
	var leg_offset := step * 1.5 if is_moving else 0.0
	draw_rect(Rect2(-4, -6 + leg_offset, 3, 6 - leg_offset), legs)
	draw_rect(Rect2(1, -6 - leg_offset, 3, 6 + leg_offset), legs)
	draw_rect(Rect2(-5, -17, 10, 12), body_color)
	draw_circle(Vector2(0, -22), 5.5, Color("f1c27d"))
	if facing.y > -0.4:  # ojos solo si mira hacia la cámara
		var eye := Vector2(0, -22) + Vector2(facing.x * 2.5, 1.0)
		draw_rect(Rect2(eye + Vector2(-2.5, -1), Vector2(1.5, 2)), Color.BLACK)
		draw_rect(Rect2(eye + Vector2(1, -1), Vector2(1.5, 2)), Color.BLACK)
