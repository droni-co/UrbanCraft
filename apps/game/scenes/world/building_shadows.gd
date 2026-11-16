class_name BuildingShadows
extends CanvasGroup
## Sombras que proyectan los edificios sobre el suelo.
##
## El sol viene de arriba a la izquierda de la pantalla, así que la sombra de
## cada bloque cae hacia abajo a la derecha, más larga cuanto más alto es. Cada
## celda de edificio dibuja la envolvente de su rombo base y del mismo rombo
## desplazado (SUN * altura): es la sombra exacta de un prisma sobre el plano.
##
## Los polígonos se dibujan opacos dentro de este CanvasGroup y el grupo entero
## se pinta con un solo tono semitransparente (shader de abajo): donde se
## cruzan las sombras de dos celdas no se oscurece el doble. Va entre el suelo
## y las entidades, así que oscurece el suelo pero no a los edificios ni a los
## jugadores. Un nodo por chunk, con todas sus sombras en una sola malla (una
## sola orden de dibujo): miles de polígonos sueltos son miles de órdenes por
## frame, demasiado para un teléfono.

## Desplazamiento en pantalla de la sombra por cada píxel de altura.
const SUN := Vector2(0.78, 0.30)
## Sombras de árboles: tipo de prop -> [altura en px, radio de la copa en px].
const PROP_SHADOWS := {
	WorldTiles.Prop.TREE: [40.0, 15.0],
	WorldTiles.Prop.PINE: [42.0, 11.0],
	WorldTiles.Prop.BUSH: [12.0, 10.0],
}
## Filas de celdas que se procesan por frame al armar un chunk.
const ROWS_PER_FRAME := 16
## Color y opacidad de la sombra (azulada, como la luz de cielo que la ilumina).
const TINT := Color(0.10, 0.12, 0.28, 0.40)

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint : source_color;
// Desenfoque barato con mipmaps: bordes suaves sin pasadas extra.
uniform float softness = 1.2;
void fragment() {
	float a = textureLod(screen_texture, SCREEN_UV, softness).a;
	COLOR = vec4(tint.rgb, a * tint.a);
}
"""

var _chunks := {}  # chunk -> _ChunkShadow
var _building := {}  # chunk -> id del armado en curso (se cancela al quitarlo)
var _next_build := 0


func _ready() -> void:
	# El desenfoque usa mipmaps de la pantalla, que se generan en cada frame:
	# con gráficos livianos las sombras quedan de borde duro.
	use_mipmaps = not GameSettings.low_graphics
	fit_margin = 8.0
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	material.set_shader_parameter("tint", TINT)
	material.set_shader_parameter("softness", 0.0 if GameSettings.low_graphics else 1.2)
	self.material = material


## Arma las sombras de un chunk a partir de sus datos (suelo, pisos y props),
## repartido en varios frames. `base` es su esquina en celdas locales y `map`
## la capa que define la proyección celda -> mundo.
func add_chunk(chunk: Vector2i, base: Vector2i, size: int, data: Dictionary, map: TileMapLayer) -> void:
	remove_chunk(chunk)
	if map == null:
		return
	var ground: PackedByteArray = data.get("ground", PackedByteArray())
	var props: PackedByteArray = data.get("props", PackedByteArray())
	var levels: PackedByteArray = data.get("levels", PackedByteArray())
	if ground.size() < size * size:
		return
	_next_build += 1
	var build := _next_build
	_building[chunk] = build

	var half := Vector2(WorldTiles.TILE_SIZE) / 2.0
	var zero := map.map_to_local(Vector2i.ZERO)
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in size:
		for x in size:
			var i := y * size + x
			var kind := ground[i]
			var prop := props[i] if i < props.size() else WorldTiles.NO_PROP
			var is_building := WorldTiles.is_building(kind)
			if not is_building and prop == WorldTiles.NO_PROP:
				continue
			var cell := base + Vector2i(x, y)
			var center := zero + Vector2((cell.x - cell.y) * half.x, (cell.x + cell.y) * half.y)
			if prop != WorldTiles.NO_PROP and PROP_SHADOWS.has(prop):
				var shape: Array = PROP_SHADOWS[prop]
				_add_fan(points, indices, _canopy_shadow(center, shape[0], shape[1]))
			if is_building:
				var floors := WorldTiles.building_floors(kind, levels[i] if i < levels.size() else 0)
				var offset := SUN * float(floors * WorldTiles.BUILDING_FLOOR_PX)
				# Envolvente del rombo y del rombo desplazado por el sol (que va
				# hacia abajo a la derecha, más plano que los lados del rombo).
				var top := center + Vector2(0, -half.y)
				var bottom := center + Vector2(0, half.y)
				_add_fan(points, indices, PackedVector2Array([
					top, top + offset, center + Vector2(half.x, 0) + offset,
					bottom + offset, bottom, center + Vector2(-half.x, 0),
				]))
		if y % ROWS_PER_FRAME == ROWS_PER_FRAME - 1 and y < size - 1:
			await get_tree().process_frame
			if _building.get(chunk) != build:
				return  # se quitó (o se volvió a pedir) mientras se armaba
	_building.erase(chunk)
	if indices.is_empty():
		return
	var node := _ChunkShadow.new()
	node.points = points
	node.indices = indices
	node.position = map.position
	add_child(node)
	_chunks[chunk] = node


## Agrega un polígono convexo a la malla, como abanico de triángulos.
func _add_fan(points: PackedVector2Array, indices: PackedInt32Array, polygon: PackedVector2Array) -> void:
	var first := points.size()
	points.append_array(polygon)
	for i in range(1, polygon.size() - 1):
		indices.append(first)
		indices.append(first + i)
		indices.append(first + i + 1)


## Sombra de un árbol: el tronco (una franja desde el pie) y la copa (un óvalo
## aplastado como el suelo), desplazados por el sol según su altura.
func _canopy_shadow(feet: Vector2, height: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array([feet + Vector2(-2, 0), feet + Vector2(2, 0)])
	var center := feet + SUN * height
	for i in 12:
		var a := TAU * i / 12.0
		points.append(center + Vector2(cos(a) * radius, sin(a) * radius * 0.55))
	var hull := Geometry2D.convex_hull(points)
	hull.resize(hull.size() - 1)  # convex_hull repite el primer punto al final
	return hull


func remove_chunk(chunk: Vector2i) -> void:
	_building.erase(chunk)
	var node: Node = _chunks.get(chunk)
	if node:
		node.queue_free()
	_chunks.erase(chunk)


func clear() -> void:
	for chunk: Vector2i in _chunks.keys() + _building.keys():
		remove_chunk(chunk)


class _ChunkShadow extends Node2D:
	var points := PackedVector2Array()
	var indices := PackedInt32Array()

	func _draw() -> void:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, PackedColorArray([Color.WHITE]))
