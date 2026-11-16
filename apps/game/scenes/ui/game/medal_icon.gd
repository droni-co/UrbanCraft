class_name MedalIcon
extends Control
## Medalla de un logro: un disco con el aro del color de su nivel (bronce,
## plata, oro, diamante) y el dibujo del logro encima. Sin conseguir se ve apagada.

var _emblem: Texture2D
var _tier := 1
var _unlocked := false


func setup(emblem: String, tier: int, unlocked: bool) -> void:
	_emblem = GameArt.medal(emblem)
	_tier = tier
	_unlocked = unlocked
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 1.0
	var color := GameArt.tier_color(_tier)
	if not _unlocked:
		color = color.lerp(Color(0.25, 0.3, 0.38), 0.75)
	draw_circle(center + Vector2(0, 1), radius, Color(0, 0, 0, 0.35))
	draw_circle(center, radius, color.darkened(0.35))
	draw_circle(center, radius - 1.5, color)
	draw_circle(center, radius - 3.0, Color("1b2f52") if _unlocked else Color("1a2436"))
	# Brillo arriba a la izquierda.
	draw_arc(center, radius - 0.8, PI * 1.05, PI * 1.55, 12, Color(1, 1, 1, 0.55 if _unlocked else 0.12), 1.0, true)
	if _emblem:
		var inner := (radius - 3.5) * 1.5
		var rect := Rect2(center - Vector2(inner, inner) / 2.0, Vector2(inner, inner))
		draw_texture_rect(_emblem, rect, false, Color.WHITE if _unlocked else Color(0.2, 0.24, 0.32, 0.9))
