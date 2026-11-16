class_name ArtStyleBox
extends StyleBox
## StyleBox de 9 partes (nine-slice) con una textura en alta resolución.
##
## StyleBoxTexture dibuja la textura a 1 píxel de textura por píxel lógico, así
## que un marco pintado a x3 saldría el triple de grande. Esta versión divide
## los bordes entre `art_scale`: el marco se ve del tamaño lógico que toca y la
## pantalla muestra todos los píxeles del PNG (como HDTexture en el mundo).
##
## El nodo que la usa necesita un filtro lineal (el del proyecto es *nearest*,
## para el pixel art): UiArt.smooth(control) lo deja listo.

## Textura del marco (assets/art/ui/frames/*.png).
var texture: Texture2D
## Bordes que no se estiran, en píxeles de la textura: izquierda, arriba, derecha, abajo.
var margins := Vector4(0, 0, 0, 0)
## Píxeles de la textura por píxel lógico.
var art_scale := 3.0
var modulate := Color.WHITE
var draw_center := true


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	var tex_size := texture.get_size()
	var src_l := margins.x
	var src_t := margins.y
	var src_r := margins.z
	var src_b := margins.w
	var dst_l := src_l / art_scale
	var dst_t := src_t / art_scale
	var dst_r := src_r / art_scale
	var dst_b := src_b / art_scale
	# Si el rectángulo es más chico que los dos bordes juntos, se encogen igual.
	var fit_x := minf(1.0, rect.size.x / maxf(dst_l + dst_r, 0.001))
	var fit_y := minf(1.0, rect.size.y / maxf(dst_t + dst_b, 0.001))
	var fit := minf(fit_x, fit_y)
	dst_l *= fit
	dst_t *= fit
	dst_r *= fit
	dst_b *= fit

	var sx := [0.0, src_l, tex_size.x - src_r, tex_size.x]
	var sy := [0.0, src_t, tex_size.y - src_b, tex_size.y]
	var dx := [rect.position.x, rect.position.x + dst_l, rect.end.x - dst_r, rect.end.x]
	var dy := [rect.position.y, rect.position.y + dst_t, rect.end.y - dst_b, rect.end.y]
	var rid := texture.get_rid()
	for j in 3:
		for i in 3:
			if i == 1 and j == 1 and not draw_center:
				continue
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dst, rid, src, modulate, false, true)
