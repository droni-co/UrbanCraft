class_name Birds
extends Node2D
## Bandadas de pájaros que cruzan el cielo de vez en cuando (de día) y su
## sombra en el suelo. Se dibujan a mano (una "V" que aletea), sin texturas.
## De noche no salen.

const MIN_WAIT := 8.0
const MAX_WAIT := 22.0
## Altura del vuelo (px): separa el pájaro de su sombra.
const FLIGHT_HEIGHT := 90.0
const SPEED := 46.0

var day_night: DayNight
var view_provider: Callable  # -> Rect2 del mundo visible

var _flock: Array[Dictionary] = []  # {pos, vel, phase, size}
var _wait := 4.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 100
	_rng.randomize()


func _process(delta: float) -> void:
	if _flock.is_empty():
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(MIN_WAIT, MAX_WAIT)
			if day_night == null or day_night.night < 0.5:
				_spawn()
		return
	var view: Rect2 = view_provider.call() if view_provider.is_valid() else Rect2()
	var alive := false
	for bird in _flock:
		bird.pos += bird.vel * delta
		bird.phase += delta * bird.flap
		if view.grow(200.0).has_point(bird.pos):
			alive = true
	if not alive:
		_flock.clear()
	queue_redraw()


func _spawn() -> void:
	var view: Rect2 = view_provider.call() if view_provider.is_valid() else Rect2()
	if view.size == Vector2.ZERO:
		return
	# Entran por un borde y cruzan hacia el otro con algo de ángulo.
	var from_left := _rng.randf() < 0.5
	var dir := Vector2(1.0 if from_left else -1.0, _rng.randf_range(-0.35, 0.35)).normalized()
	var start := Vector2(view.position.x - 60.0 if from_left else view.end.x + 60.0,
		_rng.randf_range(view.position.y, view.end.y))
	var count := _rng.randi_range(3, 7)
	for i in count:
		# Formación en "V" suelta.
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := float((i + 1) / 2)
		var offset := -dir * rank * 14.0 + dir.orthogonal() * side * rank * 10.0
		_flock.append({
			"pos": start + offset + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
			"vel": dir * SPEED * _rng.randf_range(0.95, 1.05),
			"phase": _rng.randf() * TAU,
			"flap": _rng.randf_range(9.0, 12.0),
			"size": _rng.randf_range(3.2, 4.2),
		})


func _draw() -> void:
	for bird in _flock:
		var p: Vector2 = bird.pos
		var s: float = bird.size
		var wing := sin(bird.phase)  # -1..1: alas arriba / abajo
		# Sombra en el suelo, abajo del pájaro.
		var shadow := p + Vector2(FLIGHT_HEIGHT * 0.3, FLIGHT_HEIGHT * 0.5)
		draw_line(shadow + Vector2(-s, 0), shadow + Vector2(s, 0), Color(0.05, 0.05, 0.15, 0.18), 1.6)
		var tip_y := -wing * s * 0.8
		var points := PackedVector2Array([
			p + Vector2(-s, tip_y), p + Vector2(-s * 0.35, -wing * s * 0.25 + 0.6), p,
			p + Vector2(s * 0.35, -wing * s * 0.25 + 0.6), p + Vector2(s, tip_y),
		])
		draw_polyline(points, Color(0.13, 0.12, 0.16, 0.9), 1.1, true)
