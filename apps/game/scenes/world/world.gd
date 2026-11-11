extends Node2D
## Mundo isométrico.
##
## Modo REAL: mapa de OpenStreetMap cargado por chunks desde el backend,
## centrado en la ubicación real del jugador (LocationService). Modo híbrido:
## el jugador se mueve libremente dentro de playRadiusMeters de esa ubicación.
##
## Modo DEMO: sin servidor (o con --demo) se genera un mapa procedural local.

enum Mode { LOADING, REAL, DEMO }

@export var demo_map_size := Vector2i(64, 64)
@export var demo_seed := 1337
## Fuerza el mapa procedural aunque haya servidor (también: -- --demo).
@export var force_demo := false

const PROP_DESCRIPTIONS := {
	WorldTiles.Prop.TREE: "Un árbol frondoso.",
	WorldTiles.Prop.PINE: "Un pino alto. Huele a resina.",
	WorldTiles.Prop.ROCK: "Una roca. Quizá algo se esconde debajo...",
	WorldTiles.Prop.BUSH: "Un arbusto. Algo se mueve entre las hojas.",
}
const GROUND_DESCRIPTIONS := {
	WorldTiles.Ground.WATER: "Agua. Todavía no sabes nadar.",
	WorldTiles.Ground.BUILDING: "Un edificio. Las puertas aún no se abren.",
}

@onready var ground: TileMapLayer = $Ground
@onready var props: TileMapLayer = $Entities/Props
@onready var entities: Node2D = $Entities
@onready var player: Player = $Entities/Player
@onready var camera: GameCamera = $Camera
@onready var cursor: TileCursor = $TileCursor
@onready var hud: Hud = $HUD
@onready var chunks: ChunkManager = $ChunkManager
@onready var map_labels: MapLabels = $MapLabels

var mode := Mode.LOADING
var pathfinder: IsoPathfinder
var player_cell := Vector2i.ZERO
var map_config := {}
## Celda global de la ubicación real del jugador (centro de su zona de juego).
var anchor_cell := Vector2i.ZERO
var play_radius_cells := INF

## Celda local que el minimapa usa como centro (ancla en modo real).
var _minimap_center_local := Vector2i.ZERO
var _last_valid_position := Vector2.ZERO
var _limit_message_cooldown := 0.0
var _pois := {}  # celda local -> PoiMarker
var _poi_markers := {}  # chunk -> Array[PoiMarker]
var _location_cell := Vector2i(-99999, -99999)
## Ciudad y país de la zona ("Madrid, España"), del backend (Nominatim/OSM).
var _place_label := ""


func _ready() -> void:
	# Corre después del jugador para validar su posición en el mismo frame.
	process_physics_priority = 10
	pathfinder = IsoPathfinder.new(ground, props)
	cursor.ground = ground
	map_labels.ground = ground

	player.interacted.connect(_on_player_interacted)
	player.path_ended.connect(cursor.clear_target)
	player.set_physics_process(false)  # hasta que haya mapa bajo sus pies

	camera.target = player
	camera.tapped.connect(_on_tapped)
	camera.hovered.connect(_on_hovered)

	if force_demo or "--demo" in OS.get_cmdline_user_args():
		_start_demo("Modo demo: mapa procedural")
		return

	hud.set_loading("Conectando con el servidor...")
	var res := await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/map/config")
	hud.set_online(res.ok)
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		_start_demo("Sin conexión: mapa de demostración")
		return

	if not LocationService.is_located:
		hud.set_loading("Buscando tu ubicación...")
		await LocationService.locate()
	_start_real(res.data)
	_fetch_place()


# --- Modos --------------------------------------------------------------------

func _start_real(config: Dictionary) -> void:
	map_config = config
	_check_catalog(config)
	mode = Mode.REAL

	var cell_zoom := int(config.cellZoom)
	var size := int(config.chunkSize)
	anchor_cell = Geo.lat_lon_to_cell(LocationService.latitude, LocationService.longitude, cell_zoom)
	var meters_per_cell := Geo.meters_per_cell(LocationService.latitude, cell_zoom)
	play_radius_cells = float(config.playRadiusMeters) / meters_per_cell

	var origin := Geo.chunk_origin(Geo.cell_to_chunk(anchor_cell, size), size)
	chunks.setup(ground, props, config, origin)
	chunks.chunk_loaded.connect(_on_chunk_loaded)
	chunks.chunk_unloaded.connect(_on_chunk_unloaded)
	chunks.chunk_pending.connect(_on_chunk_pending)
	chunks.chunk_failed.connect(_on_chunk_failed)
	chunks.chunk_data_ready.connect(func(chunk: Vector2i, data: Dictionary) -> void:
		hud.minimap.add_chunk(Geo.chunk_origin(chunk, size), size, data.ground, data.pois))
	chunks.chunk_data_released.connect(func(chunk: Vector2i) -> void:
		hud.minimap.remove_chunk(Geo.chunk_origin(chunk, size)))
	# Toda la zona de juego queda fijada como datos: el minimapa muestra el mapa
	# general aunque el TileMap solo dibuje los chunks cercanos.
	chunks.set_pinned_chunks(chunks.chunks_in_circle(anchor_cell, play_radius_cells))
	_minimap_center_local = chunks.global_to_local(anchor_cell)
	hud.minimap.set_view(anchor_cell, play_radius_cells)

	hud.set_attribution(str(config.attribution))
	hud.set_loading("Cargando mapa...")
	chunks.update_center(anchor_cell)


func _start_demo(message: String) -> void:
	mode = Mode.DEMO
	var spawn := demo_map_size / 2
	WorldGenerator.generate(ground, props, demo_map_size, demo_seed, spawn)
	camera.apply_limits(_demo_bounds())
	_feed_demo_minimap(spawn)
	_spawn_player_at(spawn)
	hud.set_loading("")
	hud.show_message(message, 3.0)


func _spawn_player_at(cell: Vector2i) -> void:
	var safe: Variant = pathfinder.nearest_walkable(cell, 16)
	player.global_position = cell_to_world(safe if safe != null else cell)
	_last_valid_position = player.global_position
	camera.snap_to_target()
	player.set_physics_process(true)


# --- Bucle --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if mode == Mode.LOADING or not player.is_physics_processing():
		return
	_limit_message_cooldown -= delta

	var cell := world_to_cell(player.global_position)
	var valid := ground.get_cell_source_id(cell) != -1  # no caminar hacia zonas sin cargar

	if mode == Mode.REAL:
		var global_cell := chunks.local_to_global(cell)
		chunks.update_center(global_cell)
		if Vector2(global_cell - anchor_cell).length() > play_radius_cells:
			valid = false
			_show_limit_message()

	if valid:
		_last_valid_position = player.global_position
	else:
		player.global_position = _last_valid_position
		player.stop()


func _process(_delta: float) -> void:
	player_cell = world_to_cell(player.global_position)
	if mode != Mode.LOADING:
		var grid_position := _player_grid_position()
		hud.minimap.set_player(grid_position - Vector2(_minimap_center_local), player.facing)
		map_labels.set_focus(grid_position)
		if player_cell != _location_cell:
			_location_cell = player_cell
			hud.set_location(map_labels.location_name(grid_position))
	# TODO(multijugador): enviar posición/celda global al servidor.
	var parts: Array[String] = []
	if mode == Mode.REAL:
		parts.append(_place_label if not _place_label.is_empty() else "Ubicando…")
		if GameSettings.debug_info_visible:
			var chunk := chunks.chunk_of_global(chunks.local_to_global(player_cell))
			parts.append("chunk %d,%d" % [chunk.x, chunk.y])
	else:
		parts.append("Mapa de demostración")
		if GameSettings.debug_info_visible:
			parts.append("celda %d,%d" % [player_cell.x, player_cell.y])
	if GameSettings.debug_info_visible:
		parts.append("%d FPS" % Engine.get_frames_per_second())
	hud.set_info(" · ".join(parts))


func _show_limit_message() -> void:
	if _limit_message_cooldown > 0.0:
		return
	_limit_message_cooldown = 3.0
	hud.show_message("Límite de tu zona (%d m). Camina en la vida real para explorar más." % int(map_config.playRadiusMeters))


# --- Chunks -------------------------------------------------------------------

func _on_chunk_loaded(chunk: Vector2i, data: Dictionary) -> void:
	_add_pois(chunk, data.get("pois", []))
	var base := chunks.global_to_local(Geo.chunk_origin(chunk, chunks.chunk_size))
	map_labels.add_chunk(chunk, base, data.get("labels", []), data.get("pois", []))
	_location_cell = Vector2i(-99999, -99999)  # recalcular el nombre del lugar
	if not player.is_physics_processing() and chunk == chunks.chunk_of_global(anchor_cell):
		_spawn_player_at(chunks.global_to_local(anchor_cell))
		hud.set_loading("")
		hud.show_message(_welcome_message(), 5.0)


func _on_chunk_unloaded(chunk: Vector2i) -> void:
	map_labels.remove_chunk(chunk)
	for marker: PoiMarker in _poi_markers.get(chunk, []):
		_pois.erase(world_to_cell(marker.global_position))
		marker.queue_free()
	_poi_markers.erase(chunk)


func _on_chunk_pending(chunk: Vector2i) -> void:
	if not player.is_physics_processing() and chunk == chunks.chunk_of_global(anchor_cell):
		hud.set_loading("Generando el mapa de esta zona por primera vez...\nPuede tardar hasta un minuto.")


func _on_chunk_failed(chunk: Vector2i, reason: String) -> void:
	push_warning("Chunk %s: %s" % [chunk, reason])
	if not player.is_physics_processing() and chunk == chunks.chunk_of_global(anchor_cell):
		hud.set_loading("No se pudo cargar el mapa (%s).\nReintentando..." % reason)


func _add_pois(chunk: Vector2i, pois: Array) -> void:
	var base := chunks.global_to_local(Geo.chunk_origin(chunk, chunks.chunk_size))
	var markers: Array[PoiMarker] = []
	for poi: Dictionary in pois:
		var local_cell: Vector2i = base + Vector2i(int(poi.cell[0]), int(poi.cell[1]))
		var marker := PoiMarker.new()
		marker.setup(poi)
		marker.position = entities.to_local(cell_to_world(local_cell))
		entities.add_child(marker)
		markers.append(marker)
		_pois[local_cell] = marker
	_poi_markers[chunk] = markers


## Ciudad y país de la zona de juego. Mientras tanto usa lo que dio la fuente
## de ubicación (la IP ya trae ciudad); reintenta si el servicio no responde.
func _fetch_place() -> void:
	_place_label = LocationService.hint_label
	for attempt in 3:
		var path := "/api/v1/geo/place?lat=%.5f&lon=%.5f" % [LocationService.latitude, LocationService.longitude]
		var res := await Api.request_json(HTTPClient.METHOD_GET, path)
		if res.ok and typeof(res.data) == TYPE_DICTIONARY:
			_place_label = str(res.data.get("label", _place_label))
			return
		if res.status == 404 or res.status == 422:
			return  # zona sin ciudad conocida (mar abierto, etc.)
		await get_tree().create_timer(15.0 * (attempt + 1)).timeout


func _welcome_message() -> String:
	var radius := int(map_config.playRadiusMeters)
	var where := _place_label if not _place_label.is_empty() else "%.4f, %.4f" % [LocationService.latitude, LocationService.longitude]
	match LocationService.source:
		"ip":
			return "Tu zona: %s (aproximada por IP) · %d m para explorar" % [where, radius]
		"last":
			return "Tu zona: %s (última ubicación conocida) · %d m para explorar" % [where, radius]
		"default":
			return "No se pudo obtener tu ubicación: usando %s" % where
		_:
			return "Tu zona: %s · %d m para explorar" % [where, radius]


func _check_catalog(config: Dictionary) -> void:
	var server_ground: Array = config.get("catalog", {}).get("ground", [])
	var server_props: Array = config.get("catalog", {}).get("props", [])
	if server_ground != WorldTiles.Ground.keys() or server_props != WorldTiles.Prop.keys():
		push_error("El catálogo de tiles del servidor no coincide con WorldTiles: %s / %s" % [server_ground, server_props])
		hud.show_message("Versión del juego desactualizada: actualiza el cliente.", 6.0)


# --- Input --------------------------------------------------------------------

func cell_to_world(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(world_position))


func _on_tapped(world_position: Vector2) -> void:
	if not player.is_physics_processing():
		return
	var target := world_to_cell(world_position)
	if mode == Mode.REAL and Vector2(chunks.local_to_global(target) - anchor_cell).length() > play_radius_cells:
		_limit_message_cooldown = 0.0
		_show_limit_message()
		return

	var path := pathfinder.find_path(world_to_cell(player.global_position), target)
	if path.size() < 2:
		if not pathfinder.is_walkable(target):
			hud.show_message("No puedes ir ahí")
		return

	var points: Array[Vector2] = []
	for i in range(1, path.size()):
		points.append(cell_to_world(path[i]))
	player.set_path(points)
	cursor.set_target(path[path.size() - 1])


func _on_hovered(world_position: Vector2) -> void:
	var cell := world_to_cell(world_position)
	cursor.set_hover(cell if ground.get_cell_source_id(cell) != -1 else null)


func _on_player_interacted(facing: Vector2) -> void:
	var here := world_to_cell(player.global_position)
	var cell := world_to_cell(player.global_position + facing * 24.0)
	if cell == here:
		cell = world_to_cell(player.global_position + facing * 40.0)

	for c in [here, cell]:
		if _pois.has(c):
			var marker: PoiMarker = _pois[c]
			hud.show_message("%s  (%s)" % [marker.poi_name, marker.poi_kind.replace(":", " · ")], 3.0)
			return

	if props.get_cell_source_id(cell) != -1:
		hud.show_message(PROP_DESCRIPTIONS.get(props.get_cell_atlas_coords(cell).x, "Algo interesante."))
		return
	var ground_kind := ground.get_cell_atlas_coords(cell).x
	hud.show_message(GROUND_DESCRIPTIONS.get(ground_kind, "No hay nada aquí."))


## Posición del jugador en celdas locales con decimales (centro de celda = n + 0.5).
func _player_grid_position() -> Vector2:
	var half := Vector2(ground.tile_set.tile_size) / 2.0
	var rel := ground.to_local(player.global_position) - ground.map_to_local(Vector2i.ZERO)
	var cx := (rel.x / half.x + rel.y / half.y) / 2.0
	var cy := (rel.y / half.y - rel.x / half.x) / 2.0
	return Vector2(cx, cy) + Vector2(0.5, 0.5)


func _feed_demo_minimap(center: Vector2i) -> void:
	var used := ground.get_used_rect()
	var side := maxi(used.size.x, used.size.y)
	var bytes := PackedByteArray()
	bytes.resize(side * side)
	bytes.fill(255)
	for y in used.size.y:
		for x in used.size.x:
			bytes[y * side + x] = ground.get_cell_atlas_coords(used.position + Vector2i(x, y)).x
	_minimap_center_local = center
	hud.minimap.set_view(center, 0.0, side / 2.0)
	hud.minimap.add_chunk(used.position, side, bytes)


func _demo_bounds() -> Rect2:
	var used := ground.get_used_rect()
	var corners := [
		used.position,
		Vector2i(used.end.x - 1, used.position.y),
		Vector2i(used.position.x, used.end.y - 1),
		used.end - Vector2i.ONE,
	]
	var bounds := Rect2(cell_to_world(corners[0]), Vector2.ZERO)
	for c in corners:
		bounds = bounds.expand(cell_to_world(c))
	return bounds.grow_individual(32, 16, 32, 16)
