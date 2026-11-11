extends Node2D
## Mundo isométrico: prepara el mapa, conecta el input del puntero con el
## jugador (tap/clic para moverse) y mantiene el HUD actualizado.

## Tamaño del mapa procedural (en celdas).
@export var map_size := Vector2i(64, 64)
@export var world_seed := 1337
## Si la capa Ground está vacía (no se pintó en el editor) se genera un mapa.
@export var generate_if_empty := true

const PROP_DESCRIPTIONS := {
	WorldTiles.Prop.TREE: "Un árbol frondoso.",
	WorldTiles.Prop.PINE: "Un pino alto. Huele a resina.",
	WorldTiles.Prop.ROCK: "Una roca. Quizá algo se esconde debajo...",
	WorldTiles.Prop.BUSH: "Un arbusto. Algo se mueve entre las hojas.",
}

@onready var ground: TileMapLayer = $Ground
@onready var props: TileMapLayer = $Entities/Props
@onready var player: Player = $Entities/Player
@onready var camera: GameCamera = $Camera
@onready var cursor: TileCursor = $TileCursor
@onready var hud: Hud = $HUD

var pathfinder := IsoPathfinder.new()
var player_cell := Vector2i(-1, -1)


func _ready() -> void:
	var spawn := map_size / 2
	if generate_if_empty and ground.get_used_cells().is_empty():
		WorldGenerator.generate(ground, props, map_size, world_seed, spawn)
	pathfinder.build(ground, props)

	cursor.ground = ground
	player.global_position = cell_to_world(spawn)
	player.interacted.connect(_on_player_interacted)
	player.path_ended.connect(cursor.clear_target)

	camera.target = player
	camera.apply_limits(_world_bounds())
	camera.snap_to_target()
	camera.tapped.connect(_on_tapped)
	camera.hovered.connect(_on_hovered)

	hud.show_message("Toca el mapa o usa el joystick para moverte" if GameSettings.touch_controls_enabled
		else "Clic para moverte · WASD/flechas · Shift corre · E interactúa", 4.0)
	_check_backend()


func _process(_delta: float) -> void:
	var cell := world_to_cell(player.global_position)
	if cell != player_cell:
		player_cell = cell
		# TODO(multijugador): enviar la celda/posición al servidor.
	hud.set_info("Celda %s · %d FPS" % [player_cell, Engine.get_frames_per_second()])


func cell_to_world(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(world_position))


func _on_tapped(world_position: Vector2) -> void:
	var target := world_to_cell(world_position)
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
	cursor.set_hover(cell if pathfinder.is_in_bounds(cell) else null)


func _on_player_interacted(facing: Vector2) -> void:
	var here := world_to_cell(player.global_position)
	var cell := world_to_cell(player.global_position + facing * 24.0)
	if cell == here:
		cell = world_to_cell(player.global_position + facing * 40.0)

	if props.get_cell_source_id(cell) != -1:
		var prop := props.get_cell_atlas_coords(cell).x
		hud.show_message(PROP_DESCRIPTIONS.get(prop, "Algo interesante."))
	elif ground.get_cell_atlas_coords(cell).x == WorldTiles.Ground.WATER:
		hud.show_message("Agua. Todavía no sabes nadar.")
	else:
		hud.show_message("No hay nada aquí.")


func _world_bounds() -> Rect2:
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


func _check_backend() -> void:
	var res := await Api.health()
	hud.set_online(res.ok)
