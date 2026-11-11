class_name WorldGenerator
extends RefCounted
## Generador procedural de mapas de prueba (determinista según la semilla).
## Más adelante se combinará con datos del servidor (zonas reales, POIs).


static func generate(ground: TileMapLayer, props: TileMapLayer, size: Vector2i, world_seed: int, spawn: Vector2i) -> void:
	ground.clear()
	props.clear()

	var elevation := FastNoiseLite.new()
	elevation.seed = world_seed
	elevation.frequency = 0.05

	var moisture := FastNoiseLite.new()
	moisture.seed = world_seed + 1
	moisture.frequency = 0.08

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var kind := _ground_at(cell, size, spawn, elevation.get_noise_2d(x, y), moisture.get_noise_2d(x, y))
			ground.set_cell(cell, WorldTiles.SOURCE_GROUND, WorldTiles.ground_coords(kind))

			var prop := _prop_at(cell, kind, spawn, rng.randf())
			if prop >= 0:
				props.set_cell(cell, WorldTiles.SOURCE_PROPS, WorldTiles.prop_coords(prop))


static func _ground_at(cell: Vector2i, size: Vector2i, spawn: Vector2i, e: float, m: float) -> int:
	# Borde del mapa: agua (límite natural del mundo)
	if cell.x == 0 or cell.y == 0 or cell.x == size.x - 1 or cell.y == size.y - 1:
		return WorldTiles.Ground.WATER
	# Plaza central de piedra
	if Vector2(spawn).distance_to(Vector2(cell)) <= 3.0:
		return WorldTiles.Ground.STONE

	var on_road := cell.x == spawn.x or cell.y == spawn.y
	if e < -0.3:
		return WorldTiles.Ground.STONE if on_road else WorldTiles.Ground.WATER  # puente
	if on_road:
		return WorldTiles.Ground.DIRT
	if e < -0.22:
		return WorldTiles.Ground.SAND
	if m > 0.15:
		return WorldTiles.Ground.GRASS_DARK
	return WorldTiles.Ground.GRASS


static func _prop_at(cell: Vector2i, kind: int, spawn: Vector2i, roll: float) -> int:
	if Vector2(spawn).distance_to(Vector2(cell)) < 5.0:
		return -1
	match kind:
		WorldTiles.Ground.GRASS_DARK:
			if roll < 0.10:
				return WorldTiles.Prop.TREE
			if roll < 0.18:
				return WorldTiles.Prop.PINE
		WorldTiles.Ground.GRASS:
			if roll < 0.025:
				return WorldTiles.Prop.BUSH
			if roll < 0.035:
				return WorldTiles.Prop.ROCK
		WorldTiles.Ground.SAND:
			if roll < 0.03:
				return WorldTiles.Prop.ROCK
	return -1
