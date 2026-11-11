class_name TileCursor
extends Node2D
## Dibuja el rombo de la celda bajo el ratón (PC) y el destino del jugador.

const HOVER_FILL := Color(1, 1, 1, 0.18)
const HOVER_LINE := Color(1, 1, 1, 0.55)
const TARGET_COLOR := Color(1.0, 0.85, 0.2)

var ground: TileMapLayer

var _hover: Variant = null
var _target: Variant = null
var _time := 0.0


func set_hover(cell: Variant) -> void:
	if cell != _hover:
		_hover = cell
		queue_redraw()


func set_target(cell: Vector2i) -> void:
	_target = cell
	queue_redraw()


func clear_target() -> void:
	_target = null
	queue_redraw()


func _process(delta: float) -> void:
	if _target != null:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if ground == null:
		return
	if _hover != null:
		_draw_diamond(_hover, HOVER_FILL, HOVER_LINE)
	if _target != null:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		_draw_diamond(_target, Color(TARGET_COLOR, 0.15 + 0.2 * pulse), TARGET_COLOR)


func _draw_diamond(cell: Vector2i, fill: Color, line: Color) -> void:
	var center := to_local(ground.to_global(ground.map_to_local(cell)))
	var half := Vector2(ground.tile_set.tile_size) / 2.0
	var points := PackedVector2Array([
		center + Vector2(0, -half.y),
		center + Vector2(half.x, 0),
		center + Vector2(0, half.y),
		center + Vector2(-half.x, 0),
	])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, line, 1.0)
