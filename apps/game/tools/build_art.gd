extends SceneTree
## Empaqueta el arte editable de assets/art/ en los atlas que usa el TileSet:
##
##   assets/art/tiles/ground/<tipo>_<n>[@peso].png  (64x32) -> assets/tiles/ground.png
##   assets/art/props/<tipo>_<n>[@peso].png         (64x64) -> assets/tiles/props.png
##   assets/art/buildings/<estilo>_<ground|upper>_<n>[@peso].png (64x42) + techos
##                                                  -> assets/tiles/buildings.png
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
## Combinaciones (fachadas + techo) por estilo y altura: la celda elige una con un hash.
const BUILDING_VARIANTS := 8

var _errors: PackedStringArray = []
## Imágenes leídas por _pack: carpeta -> tipo -> Array[{n, weight, image}]
var _images := {}


func _initialize() -> void:
	var manifest := {
		"ground": _pack("tiles/ground", WorldTiles.Ground.keys(), WorldTiles.TILE_SIZE, "ground.png"),
		"props": _pack("props", WorldTiles.Prop.keys(), PROP_SIZE, "props.png"),
	}
	manifest.buildings = _pack_buildings()
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
	print("Atlas generados: suelo %s · props %s · edificios %d estilos x %d pisos x %d variantes" % [
		_summary(manifest.ground), _summary(manifest.props),
		WorldTiles.BUILDING_STYLES.size(), WorldTiles.BUILDING_MAX_FLOORS, BUILDING_VARIANTS])
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

	_images[folder] = by_kind
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


# --- Edificios -----------------------------------------------------------------

## Arma un bloque isométrico por estilo, cantidad de pisos y variante: planta
## baja + pisos altos (fachadas de assets/art/buildings) y el techo encima (el
## mismo tile de suelo del estilo). Devuelve las variantes por altura.
func _pack_buildings() -> int:
	var facades := _read_facades()
	var roofs: Dictionary = _images.get("tiles/ground", {})
	var region := WorldTiles.BUILDING_REGION
	var styles := WorldTiles.BUILDING_STYLES
	if not _errors.is_empty():
		return BUILDING_VARIANTS
	var atlas := Image.create_empty(region.x * styles.size(),
		region.y * WorldTiles.BUILDING_MAX_FLOORS * BUILDING_VARIANTS, false, Image.FORMAT_RGBA8)
	for col in styles.size():
		var style := str(WorldTiles.Ground.keys()[styles[col]]).to_lower()
		var roof_list: Array = roofs.get(style, [])
		roof_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.n < b.n)
		for floors in range(1, WorldTiles.BUILDING_MAX_FLOORS + 1):
			for k in BUILDING_VARIANTS:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(style) + floors * 131 + k * 7919
				var roof: Image = _quantile(roof_list, (k + 0.5) / BUILDING_VARIANTS).image
				var tile := _compose_building(facades[style], roof, floors, rng)
				var row := (floors - 1) * BUILDING_VARIANTS + k
				atlas.blit_rect(tile, Rect2i(Vector2i.ZERO, region), Vector2i(col * region.x, row * region.y))
	atlas.save_png(ProjectSettings.globalize_path(OUT + "/buildings.png"))
	return BUILDING_VARIANTS


func _compose_building(facade: Dictionary, roof: Image, floors: int, rng: RandomNumberGenerator) -> Image:
	var region := WorldTiles.BUILDING_REGION
	var floor_px := WorldTiles.BUILDING_FLOOR_PX
	var img := Image.create_empty(region.x, region.y, false, Image.FORMAT_RGBA8)
	# La base del bloque es el rombo de la celda: su vértice izquierdo en y = base.
	var base := region.y - WorldTiles.TILE_SIZE.y / 2
	for j in floors:
		var module: Image = _weighted(facade.ground if j == 0 else facade.upper, rng).image
		img.blend_rect(module, Rect2i(Vector2i.ZERO, module.get_size()), Vector2i(0, base - (j + 1) * floor_px + 1))
	var top := base - floors * floor_px + 1
	# Cornisa: la primera fila de las paredes, un poco más clara.
	for x in region.x:
		var y := top + (x / 2 if x < region.x / 2 else (region.x - 1 - x) / 2)
		var c := img.get_pixel(x, y)
		if c.a > 0.0:
			img.set_pixel(x, y, c.lightened(0.2))
	img.blend_rect(roof, Rect2i(Vector2i.ZERO, roof.get_size()), Vector2i(0, top - WorldTiles.TILE_SIZE.y / 2))
	return img


## estilo -> {ground: Array[{n, weight, image}], upper: [...]}
func _read_facades() -> Dictionary:
	var folder := "buildings"
	var dir := ProjectSettings.globalize_path(ART + "/" + folder)
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	var pattern := RegEx.create_from_string("^([a-z_]+?)_(ground|upper)_(\\d+)(?:@(\\d+(?:\\.\\d+)?))?\\.png$")
	var styles: Array = WorldTiles.BUILDING_STYLES.map(func(k: int) -> String: return str(WorldTiles.Ground.keys()[k]).to_lower())
	var out := {}
	for style: String in styles:
		out[style] = {"ground": [], "upper": []}
	for f in files:
		if f.get_extension() != "png":
			continue
		var m := pattern.search(f)
		if m == null or not out.has(m.get_string(1)):
			_errors.append("%s/%s: nombre inválido (usa <estilo>_<ground|upper>_<n>[@peso].png; estilos: %s)" % [folder, f, ", ".join(styles)])
			continue
		var img := Image.load_from_file(dir.path_join(f))
		if img == null or img.get_size() != WorldTiles.BUILDING_FACADE_SIZE:
			_errors.append("%s/%s: debe medir %dx%d" % [folder, f, WorldTiles.BUILDING_FACADE_SIZE.x, WorldTiles.BUILDING_FACADE_SIZE.y])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var weight := float(m.get_string(4)) if m.get_string(4) != "" else 1.0
		out[m.get_string(1)][m.get_string(2)].append({"n": int(m.get_string(3)), "weight": weight, "image": img})
	for style: String in styles:
		for part: String in ["ground", "upper"]:
			var list: Array = out[style][part]
			if list.is_empty():
				_errors.append("%s: falta al menos una fachada '%s_%s_0.png'" % [folder, style, part])
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.n < b.n)
	return out


## Elemento de una lista con pesos al azar (rng) o en el cuantil q (0..1).
func _weighted(list: Array, rng: RandomNumberGenerator) -> Dictionary:
	return _quantile(list, rng.randf())


func _quantile(list: Array, q: float) -> Dictionary:
	var total := 0.0
	for item: Dictionary in list:
		total += float(item.weight)
	var t := q * total
	for item: Dictionary in list:
		t -= float(item.weight)
		if t < 0.0:
			return item
	return list[list.size() - 1]


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
