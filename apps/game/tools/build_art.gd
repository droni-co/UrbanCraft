extends SceneTree
## Empaqueta el arte editable de assets/art/ en los atlas que usa el TileSet:
##
##   assets/art/tiles/ground/<tipo>_<n>[@peso].png  (64x32) -> assets/tiles/ground.png
##   assets/art/props/<tipo>_<n>[@peso].png         (64x64) -> assets/tiles/props.png
##   + assets/tiles/atlas.json (variantes y pesos; lo lee generate_tileset.gd)
##
## Atlas: columna = tipo (orden de WorldTiles.Ground / WorldTiles.Prop),
## fila = variante. <tipo> es el nombre del enum en minúsculas (grass_dark).
## Las variantes se numeran por orden (no hace falta que sean consecutivas).
## Sin "@peso" una variante pesa 1.
##
## No edites assets/tiles/*.png: se regeneran. Uso: pnpm game:assets

const ART := "res://assets/art"
const OUT := "res://assets/tiles"
const PROP_SIZE := Vector2i(64, 64)

var _errors: PackedStringArray = []


func _initialize() -> void:
	var manifest := {
		"ground": _pack("tiles/ground", WorldTiles.Ground.keys(), WorldTiles.TILE_SIZE, "ground.png"),
		"props": _pack("props", WorldTiles.Prop.keys(), PROP_SIZE, "props.png"),
	}
	_check_player()

	if not _errors.is_empty():
		for e in _errors:
			push_error(e)
		print("Arte con errores: corrige los archivos indicados.")
		quit(1)
		return

	var file := FileAccess.open(ProjectSettings.globalize_path(OUT + "/atlas.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	print("Atlas generados: suelo %s · props %s" % [_summary(manifest.ground), _summary(manifest.props)])
	quit()


## Devuelve, por tipo (en orden del enum), los pesos de sus variantes.
func _pack(folder: String, kinds: Array, size: Vector2i, out_name: String) -> Array:
	var dir := ProjectSettings.globalize_path(ART + "/" + folder)
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	var pattern := RegEx.create_from_string("^([a-z_]+?)_(\\d+)(?:@(\\d+(?:\\.\\d+)?))?\\.png$")
	var by_kind := {}  # nombre -> Array[{n, weight, image}]
	for f in files:
		if f.get_extension() != "png":
			continue
		var m := pattern.search(f)
		if m == null:
			_errors.append("%s/%s: nombre inválido (usa <tipo>_<n>[@peso].png)" % [folder, f])
			continue
		var kind := m.get_string(1)
		if kind.to_upper() not in kinds:
			_errors.append("%s/%s: tipo desconocido '%s' (tipos: %s)" % [folder, f, kind, ", ".join(kinds.map(func(k: String) -> String: return k.to_lower()))])
			continue
		var img := Image.load_from_file(dir.path_join(f))
		if img == null or img.is_empty():
			_errors.append("%s/%s: no se pudo leer" % [folder, f])
			continue
		if img.get_size() != size:
			_errors.append("%s/%s: mide %s y debe medir %dx%d" % [folder, f, img.get_size(), size.x, size.y])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var weight := float(m.get_string(3)) if m.get_string(3) != "" else 1.0
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append({"n": int(m.get_string(2)), "weight": weight, "image": img})

	var rows := 1
	for kind_name: String in kinds:
		var list: Array = by_kind.get(kind_name.to_lower(), [])
		if list.is_empty():
			_errors.append("%s: falta al menos una imagen para '%s' (p. ej. %s_0.png)" % [folder, kind_name.to_lower(), kind_name.to_lower()])
		rows = maxi(rows, list.size())

	var atlas := Image.create_empty(size.x * kinds.size(), size.y * rows, false, Image.FORMAT_RGBA8)
	var weights := []
	for col in kinds.size():
		var list: Array = by_kind.get(str(kinds[col]).to_lower(), [])
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.n < b.n)
		var kind_weights := []
		for row in list.size():
			atlas.blit_rect(list[row].image, Rect2i(Vector2i.ZERO, size), Vector2i(col * size.x, row * size.y))
			kind_weights.append(list[row].weight)
		weights.append(kind_weights)

	if _errors.is_empty():
		atlas.save_png(ProjectSettings.globalize_path(OUT + "/" + out_name))
	return weights


## Personajes (skins): cada PNG de characters/ es uno; todos con el mismo formato.
func _check_player() -> void:
	var dir := ProjectSettings.globalize_path(ART + "/characters")
	var sheets := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension() == "png")
	if sheets.is_empty():
		_errors.append("characters/: falta al menos una hoja de personaje (player01.png)")
		return
	var expected := Vector2i(32 * 5, 48 * 8)
	for file: String in sheets:
		var img := Image.load_from_file(dir.path_join(file))
		if img.get_size() != expected:
			_errors.append("characters/%s: mide %s y debe medir %dx%d (5 columnas x 8 filas de 32x48)" % [file, img.get_size(), expected.x, expected.y])


func _summary(table: Array) -> String:
	var total := 0
	for w: Array in table:
		total += w.size()
	return "%d tipos, %d variantes" % [table.size(), total]
