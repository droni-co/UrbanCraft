class_name Compass
extends Control
## Brújula discreta: la aguja roja apunta al norte real en pantalla.
## Con la cámara isométrica actual el norte queda arriba a la derecha.

## Dirección del norte en coordenadas de pantalla.
@export var north := Vector2(1.0, -0.5).normalized():
	set(value):
		north = value.normalized()
		queue_redraw()
@export var radius := 8.0:
	set(value):
		radius = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	draw_circle(c, radius, Color(0, 0, 0, 0.35))
	draw_arc(c, radius, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 1.0, true)

	var perp := north.orthogonal() * 2.0
	draw_colored_polygon(PackedVector2Array([c + north * (radius - 1.5), c + perp, c - perp]), Color(1.0, 0.42, 0.42, 0.9))
	draw_colored_polygon(PackedVector2Array([c - north * (radius - 2.5), c + perp, c - perp]), Color(1, 1, 1, 0.5))

	var font := get_theme_default_font()
	var label_pos := c + north * (radius + 4.0)
	var text_size := font.get_string_size("N", HORIZONTAL_ALIGNMENT_CENTER, -1, 7)
	draw_string_outline(font, label_pos + Vector2(-text_size.x / 2.0, text_size.y / 3.0), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 7, 2, Color(0, 0, 0, 0.6))
	draw_string(font, label_pos + Vector2(-text_size.x / 2.0, text_size.y / 3.0), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color(1, 1, 1, 0.75))
