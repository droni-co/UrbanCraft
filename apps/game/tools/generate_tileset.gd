extends SceneTree
## Construye resources/tilesets/world_tileset.tres a partir de los PNG de
## assets/tiles (requiere que estén importados). Define:
##   - Forma isométrica 64x32, layout diamond-down
##   - Capa física 0 (layer "world"): agua y props bloquean
##   - Custom data "walkable" (bool) usado por IsoPathfinder
## Uso:  pnpm game:assets

const OUT := "res://resources/tilesets/world_tileset.tres"


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = WorldTiles.TILE_SIZE

	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, WorldTiles.WALKABLE)
	ts.set_custom_data_layer_type(0, TYPE_BOOL)

	var half := Vector2(WorldTiles.TILE_SIZE) / 2.0

	# Suelo
	var ground := TileSetAtlasSource.new()
	ground.texture = load("res://assets/tiles/ground.png")
	ground.texture_region_size = WorldTiles.TILE_SIZE
	ts.add_source(ground, WorldTiles.SOURCE_GROUND)
	for kind in WorldTiles.Ground.size():
		var coords := WorldTiles.ground_coords(kind)
		ground.create_tile(coords)
		var data := ground.get_tile_data(coords, 0)
		var walkable := kind not in WorldTiles.UNWALKABLE_GROUND
		data.set_custom_data(WorldTiles.WALKABLE, walkable)
		if not walkable:
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, _diamond(half.x, half.y))

	# Props (árboles, rocas...): más altos que el tile, con colisión en la base
	var props := TileSetAtlasSource.new()
	props.texture = load("res://assets/tiles/props.png")
	props.texture_region_size = WorldTiles.PROP_REGION
	ts.add_source(props, WorldTiles.SOURCE_PROPS)
	for kind in WorldTiles.Prop.size():
		var coords := WorldTiles.prop_coords(kind)
		props.create_tile(coords)
		var data := props.get_tile_data(coords, 0)
		data.texture_origin = WorldTiles.PROP_TEXTURE_ORIGIN
		data.set_custom_data(WorldTiles.WALKABLE, false)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, _diamond(14, 7))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(ts, OUT)
	print("%s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _diamond(hx: float, hy: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -hy), Vector2(hx, 0), Vector2(0, hy), Vector2(-hx, 0)])
