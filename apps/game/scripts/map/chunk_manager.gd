class_name ChunkManager
extends Node
## Streaming de chunks del mapa real alrededor del jugador (estilo Minecraft).
##
## Dos niveles:
##   - Datos: chunks descargados y decodificados (baratos, ~1 KB). Incluye los
##     alrededor del jugador y los "fijados" (pinned), p. ej. toda la zona de
##     juego para el minimapa. Señales chunk_data_ready / chunk_data_released.
##   - Tiles: chunks dentro de `load_radius` se dibujan en los TileMapLayer y se
##     quitan al salir de `keep_radius` (histéresis: sin carga/descarga continua
##     al caminar por un borde). Señales chunk_loaded / chunk_unloaded.
##
## Además: caché en disco (user://map_cache/v<versión>/) para cargar al instante
## y jugar sin conexión en zonas visitadas; reintentos tras 202 (el servidor
## está generando la zona); y aplicación de tiles por partes (rows_per_frame).
##
## Coordenadas: "global" = celda Web Mercator a cellZoom; "local" = global -
## origin_cell, que es lo que usan los TileMapLayer (evita floats enormes).

signal chunk_loaded(chunk: Vector2i, data: Dictionary)
signal chunk_unloaded(chunk: Vector2i)
signal chunk_data_ready(chunk: Vector2i, data: Dictionary)
signal chunk_data_released(chunk: Vector2i)
## El servidor está generando la zona; `progress`: cómo va (ver ChunkProgress
## en el backend: stage, ahead, elapsed, expected, attempts). Vacío en un 429.
signal chunk_pending(chunk: Vector2i, progress: Dictionary)
signal chunk_failed(chunk: Vector2i, reason: String)

const CACHE_ROOT := "user://map_cache"
const RETRY_NETWORK_SECONDS := 10.0
const RETRY_FAILED_SECONDS := 60.0

## Radio (en chunks) que se dibuja alrededor del jugador: 1 => 3x3 chunks.
@export var load_radius := 1
## Los chunks dibujados a más de este radio se quitan del TileMap.
@export var keep_radius := 2
@export var max_concurrent_requests := 4
## Filas de celdas que se aplican al TileMap por frame.
@export var rows_per_frame := 16

var ground: TileMapLayer
var props: TileMapLayer
## Bloques de edificio en 3D (y su capa semitransparente, ver BuildingFader).
var buildings: TileMapLayer
var buildings_faded: TileMapLayer
var config: Dictionary = {}
var origin_cell := Vector2i.ZERO
var chunk_size := 64

var _loaded := {}  # Vector2i -> Dictionary (datos decodificados)
var _tiled := {}  # Vector2i -> true (tiles en cola o ya puestos en el TileMap)
var _applied := {}  # Vector2i -> true (tiles completos)
var _pinned := {}  # Vector2i -> true (datos que se mantienen siempre)
var _requested := {}  # Vector2i -> true (en cola, en vuelo o esperando reintento)
var _queue: Array[Vector2i] = []
var _apply_queue: Array[Dictionary] = []  # {chunk, data, row}
var _in_flight := 0
var _center := Vector2i(-1, -1)
var _cache_dir := ""


func setup(ground_layer: TileMapLayer, props_layer: TileMapLayer, map_config: Dictionary, origin: Vector2i,
		buildings_layer: TileMapLayer = null, buildings_faded_layer: TileMapLayer = null) -> void:
	ground = ground_layer
	props = props_layer
	buildings = buildings_layer
	buildings_faded = buildings_faded_layer
	WorldTiles.load_variants(ground.tile_set)
	config = map_config
	chunk_size = int(config.chunkSize)
	origin_cell = origin
	_cache_dir = "%s/v%d" % [CACHE_ROOT, int(config.generatorVersion)]
	DirAccess.make_dir_recursive_absolute(_cache_dir)


func global_to_local(cell: Vector2i) -> Vector2i:
	return cell - origin_cell


func local_to_global(cell: Vector2i) -> Vector2i:
	return cell + origin_cell


func chunk_of_global(cell: Vector2i) -> Vector2i:
	return Geo.cell_to_chunk(cell, chunk_size)


func is_chunk_ready(chunk: Vector2i) -> bool:
	return _applied.has(chunk)


func get_chunk_data(chunk: Vector2i) -> Dictionary:
	return _loaded.get(chunk, {})


func loaded_chunks() -> Array:
	return _applied.keys()


## Chunks cuyos datos se mantienen siempre (además de los cercanos al jugador).
func set_pinned_chunks(chunks: Array[Vector2i]) -> void:
	_pinned.clear()
	for chunk in chunks:
		_pinned[chunk] = true
	if _center != Vector2i(-1, -1):
		_refresh()


## Chunks que intersecan un círculo (celdas globales): útil para fijar la zona de juego.
func chunks_in_circle(center_cell: Vector2i, radius_cells: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var c0 := chunk_of_global(center_cell - Vector2i.ONE * ceili(radius_cells))
	var c1 := chunk_of_global(center_cell + Vector2i.ONE * ceili(radius_cells))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var origin := Vector2(Geo.chunk_origin(Vector2i(cx, cy), chunk_size))
			var nearest := Vector2(center_cell).clamp(origin, origin + Vector2.ONE * chunk_size)
			if nearest.distance_to(Vector2(center_cell)) <= radius_cells:
				result.append(Vector2i(cx, cy))
	return result


## Llamar cada frame con la celda global del jugador; solo actúa al cambiar de chunk.
func update_center(global_cell: Vector2i) -> void:
	var chunk := chunk_of_global(global_cell)
	if chunk == _center:
		return
	_center = chunk
	_refresh()


func _refresh() -> void:
	var wanted: Array[Vector2i] = []
	for dy in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			wanted.append(_center + Vector2i(dx, dy))
	for chunk: Vector2i in _pinned:
		if _distance(chunk) > load_radius:
			wanted.append(chunk)
	# Primero el chunk actual, luego los más cercanos al jugador.
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _distance(a) < _distance(b))

	for chunk in wanted:
		if not _loaded.has(chunk) and not _requested.has(chunk):
			_requested[chunk] = true
			_queue.append(chunk)

	for chunk: Vector2i in _loaded.keys():
		var d := _distance(chunk)
		if d <= load_radius and not _tiled.has(chunk):
			_queue_apply(chunk)
		elif d > keep_radius and _tiled.has(chunk):
			_remove_tiles(chunk)
		if not _wants_data(chunk):
			_release(chunk)

	_pump()


func _distance(chunk: Vector2i) -> int:
	return maxi(absi(chunk.x - _center.x), absi(chunk.y - _center.y))


func _wants_data(chunk: Vector2i) -> bool:
	return _pinned.has(chunk) or _distance(chunk) <= keep_radius


func _pump() -> void:
	while _in_flight < max_concurrent_requests and not _queue.is_empty():
		var chunk: Vector2i = _queue.pop_front()
		if not _wants_data(chunk) or _loaded.has(chunk):
			_requested.erase(chunk)
			continue
		var cached := _read_cache(chunk)
		if not cached.is_empty():
			_on_data(chunk, cached)
			continue
		_in_flight += 1
		_fetch_remote(chunk)


func _fetch_remote(chunk: Vector2i) -> void:
	var path := "/api/v1/map/chunks/%d/%d/%d?v=%d" % [
		int(config.chunkZoom), chunk.x, chunk.y, int(config.generatorVersion)]
	var res := await Api.request_json(HTTPClient.METHOD_GET, path)
	_in_flight -= 1

	match res.status:
		200:
			var data := _decode(res.data)
			if data.is_empty():
				chunk_failed.emit(chunk, "chunk inválido")
				_retry_later(chunk, RETRY_FAILED_SECONDS)
			else:
				_write_cache(chunk, res.data)
				_on_data(chunk, data)
		202, 429:
			var wait := 5.0
			var progress := {}
			if typeof(res.data) == TYPE_DICTIONARY:
				wait = float(res.data.get("retryAfter", wait))
				if res.data.has("stage"):
					progress = res.data
			chunk_pending.emit(chunk, progress)
			_retry_later(chunk, wait)
		503:
			chunk_failed.emit(chunk, "el servidor no pudo obtener datos de esta zona")
			_retry_later(chunk, RETRY_FAILED_SECONDS)
		_:
			chunk_failed.emit(chunk, res.error)
			_retry_later(chunk, RETRY_NETWORK_SECONDS)
	_pump()


func _retry_later(chunk: Vector2i, seconds: float) -> void:
	get_tree().create_timer(maxf(seconds, 1.0)).timeout.connect(func() -> void:
		if _wants_data(chunk) and not _loaded.has(chunk):
			_queue.append(chunk)
			_pump()
		else:
			_requested.erase(chunk)
	)


func _on_data(chunk: Vector2i, data: Dictionary) -> void:
	_requested.erase(chunk)
	if not _wants_data(chunk) or _loaded.has(chunk):
		return
	_loaded[chunk] = data
	chunk_data_ready.emit(chunk, data)
	if _distance(chunk) <= load_radius:
		_queue_apply(chunk)


func _queue_apply(chunk: Vector2i) -> void:
	_tiled[chunk] = true
	_apply_queue.append({"chunk": chunk, "data": _loaded[chunk], "row": 0})


func _process(_delta: float) -> void:
	var rows_left := rows_per_frame
	while rows_left > 0 and not _apply_queue.is_empty():
		var job: Dictionary = _apply_queue[0]
		var chunk: Vector2i = job.chunk
		var data: Dictionary = job.data
		var base := global_to_local(Geo.chunk_origin(chunk, chunk_size))
		var ground_bytes: PackedByteArray = data.ground
		var prop_bytes: PackedByteArray = data.props
		var level_bytes: PackedByteArray = data.get("levels", PackedByteArray())
		var roof_bytes: PackedByteArray = data.get("roofs", PackedByteArray())
		var row: int = job.row
		var end_row := mini(row + rows_left, chunk_size)

		for y in range(row, end_row):
			for x in chunk_size:
				var i := y * chunk_size + x
				var cell := base + Vector2i(x, y)
				var gx := cell.x + origin_cell.x
				var gy := cell.y + origin_cell.y
				var kind := ground_bytes[i]
				ground.set_cell(cell, WorldTiles.SOURCE_GROUND, WorldTiles.pick_ground(kind, gx, gy))
				if buildings and WorldTiles.is_building(kind):
					var levels := level_bytes[i] if i < level_bytes.size() else 0
					var source := WorldTiles.building_source(WorldTiles.building_floors(kind, levels))
					var coords := WorldTiles.pick_building(kind, gx, gy)
					var roof := roof_bytes[i] if i < roof_bytes.size() else 0
					buildings.set_cell(cell, source, coords, RoofStyles.alternative(buildings.tile_set, source, coords, roof))
				var prop := prop_bytes[i]
				if prop != WorldTiles.NO_PROP:
					props.set_cell(cell, WorldTiles.SOURCE_PROPS, WorldTiles.pick_prop(prop, gx, gy))

		rows_left -= end_row - row
		job.row = end_row
		if end_row >= chunk_size:
			_apply_queue.pop_front()
			_applied[chunk] = true
			chunk_loaded.emit(chunk, data)


## Quita los tiles de un chunk del TileMap (los datos se conservan si se quieren).
func _remove_tiles(chunk: Vector2i) -> void:
	for i in range(_apply_queue.size() - 1, -1, -1):
		if _apply_queue[i].chunk == chunk:
			_apply_queue.remove_at(i)
	var base := global_to_local(Geo.chunk_origin(chunk, chunk_size))
	for y in chunk_size:
		for x in chunk_size:
			var cell := base + Vector2i(x, y)
			ground.erase_cell(cell)
			props.erase_cell(cell)
			if buildings:
				buildings.erase_cell(cell)
				buildings_faded.erase_cell(cell)
	_tiled.erase(chunk)
	if _applied.erase(chunk):
		chunk_unloaded.emit(chunk)


func _release(chunk: Vector2i) -> void:
	if _tiled.has(chunk):
		_remove_tiles(chunk)
	_loaded.erase(chunk)
	chunk_data_released.emit(chunk)


# --- Formato y caché -----------------------------------------------------------

func _decode(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var p: Dictionary = payload
	if int(p.get("size", 0)) != chunk_size:
		return {}
	var ground_bytes := Marshalls.base64_to_raw(str(p.get("ground", "")))
	var prop_bytes := Marshalls.base64_to_raw(str(p.get("props", "")))
	var expected := chunk_size * chunk_size
	if ground_bytes.size() != expected or prop_bytes.size() != expected:
		return {}
	return {
		"ground": ground_bytes,
		"props": prop_bytes,
		# Pisos por celda (chunks sin este campo: se usan los típicos por estilo).
		"levels": _decode_levels(p.get("levels")),
		# Tejado de cada celda (ver RoofStyles); chunks viejos: techos planos.
		"roofs": _decode_levels(p.get("roofs")),
		"pois": p.get("pois", []),
		"labels": p.get("labels", []),
		"district": str(p.get("district", "")) if p.get("district") != null else "",
		"osm_timestamp": p.get("osmTimestamp", ""),
	}


func _decode_levels(value: Variant) -> PackedByteArray:
	if typeof(value) != TYPE_STRING:
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(value)
	return bytes if bytes.size() == chunk_size * chunk_size else PackedByteArray()


func _cache_path(chunk: Vector2i) -> String:
	return "%s/%d_%d_%d.json" % [_cache_dir, int(config.chunkZoom), chunk.x, chunk.y]


func _read_cache(chunk: Vector2i) -> Dictionary:
	var path := _cache_path(chunk)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data := _decode(JSON.parse_string(text))
	if data.is_empty():
		DirAccess.remove_absolute(path)  # corrupto: se vuelve a pedir
	return data


func _write_cache(chunk: Vector2i, payload: Variant) -> void:
	var file := FileAccess.open(_cache_path(chunk), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(payload))
