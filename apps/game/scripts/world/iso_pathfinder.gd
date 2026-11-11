class_name IsoPathfinder
extends RefCounted
## Pathfinding A* sobre la grilla del mapa isométrico (coordenadas de mapa).
##
## Como el mapa se carga por chunks y no tiene límites fijos, la grilla A* se
## construye bajo demanda solo para el rectángulo que cubre origen y destino
## (más un margen). Así no hay que reconstruir nada al cargar/descargar chunks.
##
## Una celda es transitable si su tile de suelo tiene walkable=true y no hay un
## prop no transitable encima. Las celdas sin cargar no son transitables.

## Lado máximo (en celdas) del área de búsqueda: limita el costo por toque.
const MAX_SPAN := 160

var ground: TileMapLayer
var props: TileMapLayer


func _init(ground_layer: TileMapLayer, props_layer: TileMapLayer) -> void:
	ground = ground_layer
	props = props_layer


static func is_cell_walkable(ground_layer: TileMapLayer, props_layer: TileMapLayer, cell: Vector2i) -> bool:
	var ground_data := ground_layer.get_cell_tile_data(cell)
	if ground_data == null or not ground_data.get_custom_data(WorldTiles.WALKABLE):
		return false
	var prop_data := props_layer.get_cell_tile_data(cell)
	if prop_data != null and not prop_data.get_custom_data(WorldTiles.WALKABLE):
		return false
	return true


func is_walkable(cell: Vector2i) -> bool:
	return is_cell_walkable(ground, props, cell)


## Celda transitable más cercana (incluida la propia) o null.
func nearest_walkable(cell: Vector2i, radius: int) -> Variant:
	if is_walkable(cell):
		return cell
	var best: Variant = null
	var best_dist := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d := Vector2(dx, dy).length()
			if d < best_dist and is_walkable(cell + Vector2i(dx, dy)):
				best = cell + Vector2i(dx, dy)
				best_dist = d
	return best


## Camino de celdas (incluye origen y destino) o [] si no hay o está muy lejos.
## Si el destino no es transitable, usa la celda transitable más cercana.
func find_path(from: Vector2i, to: Vector2i, margin := 12) -> Array[Vector2i]:
	var target: Variant = nearest_walkable(to, 2)
	if target == null:
		return []

	var region := Rect2i(from, Vector2i.ONE).merge(Rect2i(target, Vector2i.ONE)).grow(margin)
	if region.size.x > MAX_SPAN or region.size.y > MAX_SPAN:
		return []

	var grid := AStarGrid2D.new()
	grid.region = region
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, y)
			if not is_walkable(cell):
				grid.set_point_solid(cell, true)
	# El jugador puede quedar en el borde de una celda sólida: no bloquear el origen.
	grid.set_point_solid(from, false)
	return grid.get_id_path(from, target, true)
