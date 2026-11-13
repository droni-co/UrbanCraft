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
## jugadores. Un nodo por chunk: solo se redibuja lo que cambia.

## Desplazamiento en pantalla de la sombra por cada píxel de altura.
const SUN := Vector2(0.78, 0.30)
## Sombras de árboles: tipo de prop -> [altura en px, radio de la copa en px].
const PROP_SHADOWS := {
	WorldTiles.Prop.TREE: [40.0, 15.0],
	WorldTiles.Prop.PINE: [42.0, 11.0],
	WorldTiles.Prop.BUSH: [12.0, 10.0],
}
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


func _ready() -> void:
	use_mipmaps = true
	fit_margin = 8.0
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	material.set_shader_parameter("tint", TINT)
	self.material = material


## Arma las sombras del chunk leyendo los bloques ya puestos en las capas de edificios.
## `props`: capa de props, para la sombra larga de los árboles (opcional).
func add_chunk(chunk: Vector2i, base: Vector2i, size: int, layers: Array[TileMapLayer], props: TileMapLayer = null) -> void:
	remove_chunk(chunk)
	if layers.is_empty() or layers[0] == null:
		return
	var map := layers[0]
	var half := Vector2(WorldTiles.TILE_SIZE) / 2.0
	var polygons: Array[PackedVector2Array] = []
	for y in size:
		for x in size:
			var cell := base + Vector2i(x, y)
			if props and props.get_cell_source_id(cell) == WorldTiles.SOURCE_PROPS:
				var shape: Array = PROP_SHADOWS.get(props.get_cell_atlas_coords(cell).x, [])
				if not shape.is_empty():
					polygons.append(_canopy_shadow(map.map_to_local(cell), shape[0], shape[1]))
			var source := -1
			for layer in layers:
				source = layer.get_cell_source_id(cell)
				if source != -1:
					break
			if not WorldTiles.is_building_source(source):
				continue
			var center := map.map_to_local(cell)
			var offset := SUN * float(WorldTiles.building_wall_height(source))
			var diamond := PackedVector2Array([
				center + Vector2(0, -half.y), center + Vector2(half.x, 0),
				center + Vector2(0, half.y), center + Vector2(-half.x, 0),
			])
			var points := diamond.duplicate()
			for p in diamond:
				points.append(p + offset)
			var hull := Geometry2D.convex_hull(points)
			hull.resize(hull.size() - 1)  # convex_hull repite el primer punto al final
			polygons.append(hull)
	if polygons.is_empty():
		return
	var node := _ChunkShadow.new()
	node.polygons = polygons
	node.position = map.position
	add_child(node)
	_chunks[chunk] = node


## Sombra de un árbol: el tronco (una franja desde el pie) y la copa (un óvalo
## aplastado como el suelo), desplazados por el sol según su altura.
func _canopy_shadow(feet: Vector2, height: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array([feet + Vector2(-2, 0), feet + Vector2(2, 0)])
	var center := feet + SUN * height
	for i in 16:
		var a := TAU * i / 16.0
		points.append(center + Vector2(cos(a) * radius, sin(a) * radius * 0.55))
	var hull := Geometry2D.convex_hull(points)
	hull.resize(hull.size() - 1)
	return hull


func remove_chunk(chunk: Vector2i) -> void:
	var node: Node = _chunks.get(chunk)
	if node:
		node.queue_free()
	_chunks.erase(chunk)


func clear() -> void:
	for chunk: Vector2i in _chunks.keys():
		remove_chunk(chunk)


class _ChunkShadow extends Node2D:
	var polygons: Array[PackedVector2Array] = []

	func _draw() -> void:
		for polygon in polygons:
			draw_colored_polygon(polygon, Color.WHITE)
