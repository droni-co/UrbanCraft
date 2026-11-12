class_name BuildingFader
extends Node
## Transparenta los edificios que tapan al jugador.
##
## Los edificios son bloques altos (WorldTiles.SOURCE_BUILDINGS) en la capa
## Buildings, ordenados por profundidad con el jugador: si camina por detrás de
## uno, el bloque se dibuja encima y lo taparía. Cada frame se buscan los
## bloques que están delante del jugador y cuyo dibujo se cruza con el suyo, y
## se pasan a la capa BuildingsFaded (semitransparente); al dejar de taparlo
## vuelven a su capa. Mover una celda de capa solo redibuja su zona.

## Rectángulo (en píxeles, relativo a los pies) que ocupa el jugador en pantalla,
## con un poco de margen para que no se asome a medias.
const PLAYER_RECT := Rect2(-20, -54, 40, 58)
## Celdas alrededor del jugador que se revisan (los bloques más altos tapan hasta ~12 filas).
const SEARCH := 13

var solid: TileMapLayer
var faded: TileMapLayer
var _faded := {}  # Vector2i -> true


func setup(solid_layer: TileMapLayer, faded_layer: TileMapLayer) -> void:
	solid = solid_layer
	faded = faded_layer


## `feet`: posición de los pies del jugador en coordenadas de la capa.
func update(feet: Vector2) -> void:
	if solid == null:
		return
	var player_rect := Rect2(feet + PLAYER_RECT.position, PLAYER_RECT.size)
	var here := solid.local_to_map(feet)
	var tile := Vector2(WorldTiles.TILE_SIZE)
	var want := {}
	for dy in range(-2, SEARCH):
		for dx in range(-2, SEARCH):
			var cell := here + Vector2i(dx, dy)
			var layer := solid if solid.get_cell_source_id(cell) != -1 else faded
			if layer.get_cell_source_id(cell) == -1:
				continue
			var center := solid.map_to_local(cell)
			if center.y <= feet.y:
				continue  # detrás del jugador: lo dibuja antes, no lo tapa
			var wall := WorldTiles.building_wall_height(layer.get_cell_atlas_coords(cell))
			var block := Rect2(center.x - tile.x / 2.0, center.y - tile.y / 2.0 - wall, tile.x, tile.y + wall)
			if block.intersects(player_rect):
				want[cell] = true

	for cell: Vector2i in _faded.keys():
		if want.has(cell):
			continue
		_faded.erase(cell)
		if faded.get_cell_source_id(cell) != -1:
			solid.set_cell(cell, WorldTiles.SOURCE_BUILDINGS, faded.get_cell_atlas_coords(cell))
			faded.erase_cell(cell)
	for cell: Vector2i in want:
		if solid.get_cell_source_id(cell) != -1:
			faded.set_cell(cell, WorldTiles.SOURCE_BUILDINGS, solid.get_cell_atlas_coords(cell))
			solid.erase_cell(cell)
		_faded[cell] = true


## Devuelve todo a su capa (al recargar la zona).
func clear() -> void:
	for cell: Vector2i in _faded.keys():
		if faded.get_cell_source_id(cell) != -1:
			solid.set_cell(cell, WorldTiles.SOURCE_BUILDINGS, faded.get_cell_atlas_coords(cell))
			faded.erase_cell(cell)
	_faded.clear()
