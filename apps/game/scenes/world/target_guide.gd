class_name TargetGuide
extends Node2D
## Guía hacia lo que toca hacer: marca en el mapa los lugares de los encargos
## en curso y, si la historia pide hablar con alguien, el lugar más cercano
## donde encontrarlo. Junto al jugador, una flecha apunta al más cercano con
## la distancia en metros.

const COLOR := Color("ffd24d")
const STORY_COLOR := Color("7fe0ff")
const REFRESH_SECONDS := 0.5

var player: Node2D
## Celdas globales (x, y con decimales) → posición en el mundo.
var global_to_world: Callable
## Devuelve los PoiMarker cargados (para buscar dónde está un personaje).
var markers: Callable
var meters_per_cell := 2.4
## Celdas lógicas por metro en pantalla: la mitad del ancho de un tile son 0,5 celdas.
var cell_pixels := 32.0

var _targets: Array = []  # [{ position: Vector2, color: Color }]
var _elapsed := REFRESH_SECONDS
var _time := 0.0


func _ready() -> void:
	z_index = 90
	z_as_relative = false
	Game.changed.connect(func() -> void: _elapsed = REFRESH_SECONDS)


func _process(delta: float) -> void:
	_time += delta
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_collect()
	queue_redraw()


func _collect() -> void:
	_targets.clear()
	if player == null or not global_to_world.is_valid():
		return
	for entry: Dictionary in Game.active_steps():
		var poi: Dictionary = entry.step.get("poi", {})
		var position: Vector2 = global_to_world.call(float(poi.get("x", 0)) + 0.5, float(poi.get("y", 0)) + 0.5)
		_targets.append({"position": position, "color": COLOR})
	var talk := Game.talk_goal()
	if not talk.is_empty() and markers.is_valid():
		var cats: Array = talk.get("cats", [])
		var best: Node2D = null
		var best_distance := INF
		for marker: PoiMarker in markers.call():
			if not cats.has(marker.poi_category):
				continue
			var d := marker.global_position.distance_squared_to(player.global_position)
			if d < best_distance:
				best = marker
				best_distance = d
		if best:
			_targets.append({"position": best.global_position, "color": STORY_COLOR})


## Pin flotante con "!" sobre el destino, que sube y baja: se ve de lejos y
## dice "aquí es" sin leer nada.
func _draw_pin(at: Vector2, color: Color) -> void:
	var bob := 3.0 * sin(_time * 3.0)
	var center := at + Vector2(0, -30.0 + bob)
	var outline := Color(0.1, 0.07, 0.02, 0.9)
	var point := PackedVector2Array([center + Vector2(-5, 4), center + Vector2(5, 4), center + Vector2(0, 12)])
	draw_colored_polygon(point, color)
	draw_circle(center, 8.0, color)
	draw_arc(center, 8.0, 0.0, TAU, 24, outline, 1.2, true)
	var font := UiArt.FONT_BOLD
	draw_string(font, center + Vector2(-2.5, 4.5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, outline)


func _draw() -> void:
	if player == null or _targets.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var nearest := {}
	var nearest_distance := INF
	for target: Dictionary in _targets:
		var local := to_local(target.position)
		# Aro que late en el suelo, bajo el pin.
		draw_set_transform(local, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 12.0 + 4.0 * pulse, 0.0, TAU, 32, Color(target.color, 0.9 - 0.5 * pulse), 1.5, true)
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 24, Color(target.color, 0.5), 1.0, true)
		draw_set_transform(Vector2.ZERO)
		_draw_pin(local, target.color)
		var d: float = target.position.distance_to(player.global_position)
		if d < nearest_distance:
			nearest = target
			nearest_distance = d
	if nearest_distance < 70.0:
		return  # ya está ahí
	var origin := to_local(player.global_position) + Vector2(0, -20)
	var direction: Vector2 = (to_local(nearest.position) - origin).normalized()
	var tip := origin + direction * (30.0 + 2.0 * pulse)
	var side := direction.orthogonal() * 4.0
	var arrow := PackedVector2Array([tip, tip - direction * 9.0 + side, tip - direction * 6.5, tip - direction * 9.0 - side])
	draw_colored_polygon(arrow, nearest.color)
	arrow.append(arrow[0])
	draw_polyline(arrow, Color(0.1, 0.07, 0.02, 0.9), 1.0, true)
	# Distancia en metros: en pantalla, una celda mide cell_pixels de ancho y la mitad de alto.
	var delta: Vector2 = nearest.position - player.global_position
	var cells := Vector2(delta.x / cell_pixels, delta.y / (cell_pixels / 2.0)).length() * 0.7071
	var meters := cells * meters_per_cell
	var text := "%d m" % (roundi(meters / 5.0) * 5) if meters < 1000.0 else "%.1f km" % (meters / 1000.0)
	var font := UiArt.FONT_BOLD
	var text_position := tip + direction * 4.0 + Vector2(-10, 3)
	draw_string_outline(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color(0.08, 0.06, 0.02, 0.9))
	draw_string(font, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, nearest.color)
