class_name IsoPathfinder
extends RefCounted
## Pathfinding A* sobre la grilla del mapa isométrico (coordenadas de mapa).
## Una celda es transitable si su tile de suelo tiene walkable=true y no hay
## un prop no transitable encima.

var _grid := AStarGrid2D.new()


func build(ground: TileMapLayer, props: TileMapLayer) -> void:
	_grid.region = ground.get_used_rect()
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()

	var r := _grid.region
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var cell := Vector2i(x, y)
			_grid.set_point_solid(cell, not is_cell_walkable(ground, props, cell))


static func is_cell_walkable(ground: TileMapLayer, props: TileMapLayer, cell: Vector2i) -> bool:
	var ground_data := ground.get_cell_tile_data(cell)
	if ground_data == null or not ground_data.get_custom_data(WorldTiles.WALKABLE):
		return false
	var prop_data := props.get_cell_tile_data(cell)
	if prop_data != null and not prop_data.get_custom_data(WorldTiles.WALKABLE):
		return false
	return true


func is_in_bounds(cell: Vector2i) -> bool:
	return _grid.is_in_boundsv(cell)


func is_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not _grid.is_point_solid(cell)


## Para cambios dinámicos del mapa (construir, destruir, puertas...).
func set_walkable(cell: Vector2i, walkable: bool) -> void:
	if is_in_bounds(cell):
		_grid.set_point_solid(cell, not walkable)


## Devuelve el camino de celdas (incluye origen y destino) o [] si no hay.
## Si el destino no es transitable, usa la celda transitable más cercana.
func find_path(from: Vector2i, to: Vector2i, search_radius := 2) -> Array[Vector2i]:
	if not is_in_bounds(from):
		return []
	var target: Variant = _nearest_walkable(to, search_radius)
	if target == null:
		return []

	# El jugador puede quedar en el borde de una celda sólida; no bloquear el origen.
	var origin_solid := _grid.is_point_solid(from)
	_grid.set_point_solid(from, false)
	var path := _grid.get_id_path(from, target, true)
	_grid.set_point_solid(from, origin_solid)
	return path


func _nearest_walkable(cell: Vector2i, radius: int) -> Variant:
	if is_walkable(cell):
		return cell
	var best: Variant = null
	var best_dist := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := cell + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d < best_dist and is_walkable(c):
				best = c
				best_dist = d
	return best
