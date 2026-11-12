class_name PoiMarker
extends Node2D
## Marcador de un punto de interés real (OSM): tiendas, cafés, monumentos...
## Un pin con el color y el icono de su categoría (PoiCatalog).
## Base para futuras mecánicas tipo "parada" (recompensas, misiones, spawns).

var poi_id := ""
var poi_name := ""
var poi_kind := ""
var poi_category := "other"
var poi_detail := ""
var _time := randf() * TAU
var _icon: Texture2D
var _color := Color.WHITE


func setup(poi: Dictionary) -> void:
	poi_id = str(poi.get("id", ""))
	poi_name = str(poi.get("name", ""))
	poi_kind = str(poi.get("kind", ""))
	poi_category = str(poi.get("cat", "other"))
	poi_detail = str(poi.get("detail", ""))
	_icon = PoiCatalog.icon(poi_category)
	_color = PoiCatalog.color(poi_category)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## "Panadería La Espiga · Panadería"
func description() -> String:
	return "%s · %s" % [poi_name, PoiCatalog.describe(poi_kind, poi_detail)]


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var bob := roundf(sin(_time * 3.0) * 1.5)
	var head := Vector2(0, -22 + bob)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	# Pin: punta hacia el suelo y cabeza redonda con el icono.
	draw_colored_polygon(PackedVector2Array([head + Vector2(-5, 3), head + Vector2(5, 3), Vector2(0, -5 + bob)]), _color.darkened(0.25))
	draw_circle(head, 7.5, Color(0, 0, 0, 0.35))
	draw_circle(head, 6.5, _color)
	draw_arc(head, 6.5, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 1.0, true)
	if _icon:
		draw_texture(_icon, head - Vector2(3.5, 3.5))
