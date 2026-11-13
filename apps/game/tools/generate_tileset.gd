extends SceneTree
## Construye resources/tilesets/world_tileset.tres a partir de los atlas de
## assets/tiles (los arma tools/build_art.gd desde assets/art). Define:
##   - Un tile por tipo y variante (ver WorldTiles.ground_coords / prop_coords)
##   - Forma isométrica 64x32, layout diamond-down
##   - Texturas HDTexture: el atlas es x4 (WorldTiles.ART_SCALE) pero se usa
##     en px del mundo
##   - Capa física 0 (layer "world"): agua y props bloquean
##   - Custom data "walkable" (bool) usado por IsoPathfinder
##   - Edificios en 3D: bloques altos sin colisión propia (la pone su suelo),
##     un atlas por altura (WorldTiles.building_source)
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
	var manifest := _manifest()
	ts.set_meta(WorldTiles.META_GROUND_WEIGHTS, manifest.ground)
	ts.set_meta(WorldTiles.META_PROP_WEIGHTS, manifest.props)
	var building_variants := int(manifest.get("buildings", 1))
	ts.set_meta(WorldTiles.META_BUILDING_VARIANTS, building_variants)

	# Suelo
	var ground := _atlas("ground.png", WorldTiles.TILE_SIZE)
	ts.add_source(ground, WorldTiles.SOURCE_GROUND)
	for kind in WorldTiles.Ground.size():
		for variant in _variant_count(manifest.ground, kind):
			var coords := WorldTiles.ground_coords(kind, variant)
			ground.create_tile(coords)
			var data := ground.get_tile_data(coords, 0)
			var walkable := kind not in WorldTiles.UNWALKABLE_GROUND
			data.set_custom_data(WorldTiles.WALKABLE, walkable)
			if not walkable:
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, _diamond(half.x, half.y))

	# Props (árboles, rocas...): más altos que el tile, con colisión en la base
	var props := _atlas("props.png", WorldTiles.PROP_REGION)
	ts.add_source(props, WorldTiles.SOURCE_PROPS)
	for kind in WorldTiles.Prop.size():
		for variant in _variant_count(manifest.props, kind):
			var coords := WorldTiles.prop_coords(kind, variant)
			props.create_tile(coords)
			var data := props.get_tile_data(coords, 0)
			data.texture_origin = WorldTiles.PROP_TEXTURE_ORIGIN
			data.set_custom_data(WorldTiles.WALKABLE, false)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, _diamond(14, 7))

	# Edificios: un atlas por altura; columna = estilo, fila = variante.
	for floors in range(1, WorldTiles.BUILDING_MAX_FLOORS + 1):
		var file := "buildings_%d.png" % floors
		if not ResourceLoader.exists("res://assets/tiles/" + file):
			push_warning("Sin assets/tiles/%s: faltan edificios (ejecuta tools/build_art.gd)" % file)
			continue
		var buildings := _atlas(file, WorldTiles.building_region(floors))
		ts.add_source(buildings, WorldTiles.building_source(floors))
		for style in WorldTiles.BUILDING_STYLES.size():
			for variant in building_variants:
				var coords := Vector2i(style, variant)
				buildings.create_tile(coords)
				var data := buildings.get_tile_data(coords, 0)
				data.texture_origin = WorldTiles.building_texture_origin(floors)
				data.set_custom_data(WorldTiles.WALKABLE, false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(ts, OUT)
	print("%s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


## Fuente de atlas con una textura x4 de assets/tiles, en px del mundo.
## Sin el relleno automático de Godot (no sirve con HDTexture): build_art.gd
## ya deja una separación con el borde repetido.
func _atlas(file: String, region: Vector2i) -> TileSetAtlasSource:
	var atlas := TileSetAtlasSource.new()
	var art_scale := int(_manifest().get("scale", 1))
	atlas.texture = HDTexture.wrap(load("res://assets/tiles/" + file), art_scale)
	atlas.texture_region_size = region
	atlas.separation = WorldTiles.ATLAS_SEPARATION if art_scale > 1 else Vector2i.ZERO
	atlas.use_texture_padding = false
	return atlas


## Variantes y pesos de assets/tiles/atlas.json (sin él: 1 variante por tipo).
func _manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://assets/tiles/atlas.json")
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Sin assets/tiles/atlas.json: se asume 1 variante por tipo (ejecuta tools/build_art.gd)")
		return {"ground": [], "props": []}
	return data


func _variant_count(table: Array, kind: int) -> int:
	return maxi(1, (table[kind] as Array).size()) if kind < table.size() else 1


func _diamond(hx: float, hy: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -hy), Vector2(hx, 0), Vector2(0, hy), Vector2(-hx, 0)])
