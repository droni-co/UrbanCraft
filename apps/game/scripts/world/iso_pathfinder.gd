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
## Suelos de calle: desde ahí siempre se puede ir a otra parte.
const STREET_GROUNDS: Array[int] = [WorldTiles.Ground.ASPHALT, WorldTiles.Ground.CROSSWALK, WorldTiles.Ground.CYCLEWAY]
## Un área transitable de al menos tantas celdas cuenta como abierta (un parque,
## una plaza) aunque no toque una calle.
const OPEN_AREA := 400

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


func is_street(cell: Vector2i) -> bool:
	return ground.get_cell_source_id(cell) != -1 \
		and WorldTiles.ground_kind(ground.get_cell_atlas_coords(cell)) in STREET_GROUNDS \
		and is_walkable(cell)


## Si desde `cell` se puede salir caminando: llega a una calle, a un área
## grande o al borde de lo cargado (lo que no se ve no cuenta como encierro).
## false = patio o rincón cerrado entre edificios.
func has_exit(cell: Vector2i, limit := OPEN_AREA) -> bool:
	if not is_walkable(cell):
		return false
	var seen := {cell: true}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if is_street(c) or queue.size() >= limit:
			return true
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n := c + step
			if seen.has(n):
				continue
			seen[n] = true
			if ground.get_cell_source_id(n) == -1:
				return true  # sin cargar: no se sabe, mejor no rescatar
			if is_walkable(n):
				queue.append(n)
	return false


## Calle transitable más cercana a `cell` (a `radius` celdas) o null.
func nearest_street(cell: Vector2i, radius: int) -> Variant:
	for r in range(0, radius + 1):
		var best: Variant = null
		var best_dist := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # solo el anillo de este radio
				var c := cell + Vector2i(dx, dy)
				var d := Vector2(dx, dy).length()
				if d < best_dist and is_street(c):
					best = c
					best_dist = d
		if best != null:
			return best
	return null


## Celda para poner al jugador cerca de `cell`: transitable y con salida. Si lo
## más cercano es un patio cerrado, la calle más cercana.
func safe_cell(cell: Vector2i, radius := 16) -> Variant:
	var near: Variant = nearest_walkable(cell, radius)
	if near != null and has_exit(near):
		return near
	var street: Variant = nearest_street(cell, 48)
	return street if street != null else near


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
