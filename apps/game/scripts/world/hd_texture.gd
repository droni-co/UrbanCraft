@tool
class_name HDTexture
extends Texture2D
## Textura en alta resolución que se comporta como una de tamaño lógico.
##
## El arte del mundo se dibuja a WorldTiles.ART_SCALE (x4): un tile de suelo
## es un PNG de 256x128, pero el mundo sigue midiendo 64x32 por tile. Esta
## textura envuelve el atlas grande (`source`), dice medir `source / scale` y,
## al dibujar una región, la pide escalada al atlas real. Así el TileSet, los
## TileMapLayer y todas las coordenadas del juego no cambian, y la pantalla
## muestra los píxeles de verdad (con filtro lineal y mipmaps en las capas).

@export var source: Texture2D:
	set(value):
		if source == value:
			return
		if source and source.changed.is_connected(emit_changed):
			source.changed.disconnect(emit_changed)
		source = value
		if source:
			source.changed.connect(emit_changed)
		emit_changed()

## Píxeles reales por píxel lógico.
@export_range(1, 8) var scale := 1:
	set(value):
		scale = maxi(1, value)
		emit_changed()


static func wrap(texture: Texture2D, art_scale: int) -> HDTexture:
	var t := HDTexture.new()
	t.source = texture
	t.scale = art_scale
	return t


func _get_width() -> int:
	return source.get_width() / scale if source else 1


func _get_height() -> int:
	return source.get_height() / scale if source else 1


func _has_alpha() -> bool:
	return source.has_alpha() if source else false


func _is_pixel_opaque(x: int, y: int) -> bool:
	return true


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	if source:
		source.draw_rect(to_canvas_item, Rect2(pos, get_size()), false, modulate, transpose)


func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	if source:
		source.draw_rect(to_canvas_item, rect, tile, modulate, transpose)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if source:
		source.draw_rect_region(to_canvas_item, rect,
			Rect2(src_rect.position * scale, src_rect.size * scale), modulate, transpose, clip_uv)
