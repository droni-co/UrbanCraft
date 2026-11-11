class_name PoiMarker
extends Node2D
## Marcador de un punto de interés real (OSM): tiendas, cafés, monumentos...
## Base para futuras mecánicas tipo "parada" (recompensas, misiones, spawns).

var poi_id := ""
var poi_name := ""
var poi_kind := ""
var _time := randf() * TAU


func setup(poi: Dictionary) -> void:
	poi_id = str(poi.get("id", ""))
	poi_name = str(poi.get("name", ""))
	poi_kind = str(poi.get("kind", ""))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var bob := sin(_time * 3.0) * 2.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2.ZERO, Vector2(0, -16 + bob), Color("e6e6e6"), 2.0)
	draw_circle(Vector2(0, -20 + bob), 6.0, Color("2f81f7"))
	draw_arc(Vector2(0, -20 + bob), 6.0, 0.0, TAU, 20, Color.WHITE, 1.5, true)
