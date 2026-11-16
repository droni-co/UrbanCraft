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
## Chunk del mapa al que pertenece (con el id identifica el lugar en el servidor).
var chunk := Vector2i.ZERO
var _icon: Texture2D
var _color := Color.WHITE
var _pin: Node2D

## El pin sube y baja en la GPU (cada marcador con su fase, según su posición):
## así no hay que redibujar cientos de marcadores en cada frame.
const BOB_SHADER := """
shader_type canvas_item;
void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].y * 0.23;
	VERTEX.y += floor(sin(TIME * 3.0 + phase) * 1.5 + 0.5);
}
"""
static var _bob_material: ShaderMaterial


func setup(poi: Dictionary) -> void:
	poi_id = str(poi.get("id", ""))
	poi_name = str(poi.get("name", ""))
	poi_kind = str(poi.get("kind", ""))
	poi_category = str(poi.get("cat", "other"))
	poi_detail = str(poi.get("detail", ""))
	_icon = PoiCatalog.icon(poi_category)
	_color = PoiCatalog.color(poi_category)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## "Panadería La Espiga · Panadería"
func description() -> String:
	return "%s · %s" % [poi_name, PoiCatalog.describe(poi_kind, poi_detail)]


func _ready() -> void:
	if _bob_material == null:
		_bob_material = ShaderMaterial.new()
		_bob_material.shader = Shader.new()
		_bob_material.shader.code = BOB_SHADER
	_pin = Node2D.new()
	_pin.material = _bob_material
	_pin.draw.connect(_draw_pin)
	add_child(_pin)


## Sombra en el suelo (no se mueve).
func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)


## Pin: punta hacia el suelo y cabeza redonda con el icono.
func _draw_pin() -> void:
	var head := Vector2(0, -22)
	_pin.draw_colored_polygon(PackedVector2Array([head + Vector2(-5, 3), head + Vector2(5, 3), Vector2(0, -5)]), _color.darkened(0.25))
	_pin.draw_circle(head, 7.5, Color(0, 0, 0, 0.35))
	_pin.draw_circle(head, 6.5, _color)
	_pin.draw_arc(head, 6.5, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 1.0, true)
	if _icon:
		# 7x7 px del mundo (el PNG es x4: 28x28).
		_pin.draw_texture_rect(_icon, Rect2(head - Vector2(3.5, 3.5), Vector2(7, 7)), false)
