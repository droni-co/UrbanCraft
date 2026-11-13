extends SceneTree
## Empaqueta el arte editable de assets/art/ en los atlas que usa el TileSet.
## El arte va a WorldTiles.ART_SCALE (x4) del tamaño lógico del mundo:
##
##   assets/art/tiles/ground/<tipo>_<n>[@peso].png  (256x128) -> assets/tiles/ground.png
##   assets/art/props/<tipo>_<n>[@peso].png         (256x256) -> assets/tiles/props.png
##   assets/art/buildings/<estilo>_<ground|upper>_<n>[@peso].png (256x168) + techos
##                                         -> assets/tiles/buildings_<pisos>.png (1 a 6)
##   + assets/tiles/atlas.json (variantes y pesos; lo lee generate_tileset.gd)
##
## Atlas de props: columna = tipo (orden de WorldTiles.Prop), fila = variante.
## Atlas de suelo: fila = tipo (orden de WorldTiles.Ground), columna = variante.
## Atlas de edificios (uno por altura): columna = estilo, fila = variante.
## <tipo> es el nombre del enum en minúsculas (grass_dark). Las variantes se
## numeran por orden (no hace falta que sean consecutivas). Sin "@peso" una
## variante pesa 1.
##
## Entre región y región quedan WorldTiles.ATLAS_SEPARATION px lógicos con el
## borde de cada imagen repetido: con filtro lineal un tile no toma color de su
## vecino en el atlas.
##
## No edites assets/tiles/*.png: se regeneran. Uso: pnpm game:assets

const ART := "res://assets/art"
const OUT := "res://assets/tiles"
const S := WorldTiles.ART_SCALE
## Combinaciones (fachadas + techo) por estilo y altura: la celda elige una con un hash.
const BUILDING_VARIANTS := 4
## Importación de los atlas: WebP con pérdida (descarga liviana, sobre todo en
## la versión web) y mipmaps (se ven bien con el zoom alejado).
const IMPORT_PARAMS := {
	"compress/mode": "1",
	"compress/lossy_quality": "0.9",
	"mipmaps/generate": "true",
	"process/fix_alpha_border": "true",
	"detect_3d/compress_to": "0",
}

var _errors: PackedStringArray = []
## Imágenes leídas por _pack: carpeta -> tipo -> Array[{n, weight, image}]
var _images := {}


func _initialize() -> void:
	var manifest := {
		"scale": S,
		"ground": _pack("tiles/ground", WorldTiles.Ground.keys(), WorldTiles.TILE_SIZE, "ground.png", true),
		"props": _pack("props", WorldTiles.Prop.keys(), WorldTiles.PROP_REGION, "props.png", false),
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
	# Atlas viejo (un solo archivo para todas las alturas, antes del arte x4).
	for old in ["buildings.png", "buildings.png.import"]:
		var path := ProjectSettings.globalize_path(OUT.path_join(old))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Atlas generados (x%d): suelo %s · props %s · edificios %d estilos x %d alturas x %d variantes" % [
		S, _summary(manifest.ground), _summary(manifest.props),
		WorldTiles.BUILDING_STYLES.size(), WorldTiles.BUILDING_MAX_FLOORS, BUILDING_VARIANTS])
	quit()


## Devuelve, por tipo (en orden del enum), los pesos de sus variantes.
## `size` en px lógicos; las imágenes deben medir size * S.
## `by_row`: cada tipo en una fila (si no, en una columna).
func _pack(folder: String, kinds: Array, size: Vector2i, out_name: String, by_row: bool) -> Array:
	var real := size * S
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
		if img.get_size() != real:
			_errors.append("%s/%s: mide %s y debe medir %dx%d (%dx%d px del mundo x%d)" % [folder, f, img.get_size(), real.x, real.y, size.x, size.y, S])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var weight := float(m.get_string(3)) if m.get_string(3) != "" else 1.0
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append({"n": int(m.get_string(2)), "weight": weight, "image": img})

	_images[folder] = by_kind
	var variants := 1
	for kind_name: String in kinds:
		var list: Array = by_kind.get(kind_name.to_lower(), [])
		if list.is_empty():
			_errors.append("%s: falta al menos una imagen para '%s' (p. ej. %s_0.png)" % [folder, kind_name.to_lower(), kind_name.to_lower()])
		variants = maxi(variants, list.size())

	var grid := Vector2i(variants, kinds.size()) if by_row else Vector2i(kinds.size(), variants)
	var atlas := _new_atlas(size, grid)
	var weights := []
	for k in kinds.size():
		var list: Array = by_kind.get(str(kinds[k]).to_lower(), [])
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.n < b.n)
		var kind_weights := []
		for v in list.size():
			_put(atlas, list[v].image, size, Vector2i(v, k) if by_row else Vector2i(k, v))
			kind_weights.append(list[v].weight)
		weights.append(kind_weights)

	if _errors.is_empty():
		_save(atlas, out_name)
	return weights


## Atlas vacío para una grilla de regiones de `size` px lógicos.
func _new_atlas(size: Vector2i, grid: Vector2i) -> Image:
	var cell := (size + WorldTiles.ATLAS_SEPARATION) * S
	return Image.create_empty(cell.x * grid.x, cell.y * grid.y, false, Image.FORMAT_RGBA8)


## Copia `img` en la celda `coords` y repite su borde derecho e inferior en la separación.
func _put(atlas: Image, img: Image, size: Vector2i, coords: Vector2i) -> void:
	var real := size * S
	var pad := WorldTiles.ATLAS_SEPARATION * S
	var at := coords * (real + pad)
	atlas.blit_rect(img, Rect2i(Vector2i.ZERO, real), at)
	for i in pad.x:
		atlas.blit_rect(img, Rect2i(real.x - 1, 0, 1, real.y), at + Vector2i(real.x + i, 0))
	var last_row := atlas.get_region(Rect2i(at.x, at.y + real.y - 1, real.x + pad.x, 1))
	for i in pad.y:
		atlas.blit_rect(last_row, Rect2i(0, 0, real.x + pad.x, 1), at + Vector2i(0, real.y + i))


func _save(atlas: Image, out_name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT.path_join(out_name))
	atlas.save_png(path)
	_write_import(path + ".import")


## Deja los parámetros de importación del atlas (conserva su uid si ya existe).
func _write_import(path: String) -> void:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else \
		"[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
	for key: String in IMPORT_PARAMS:
		var line := "%s=%s" % [key, IMPORT_PARAMS[key]]
		var re := RegEx.create_from_string("(?m)^" + key.replace("/", "\\/") + "=.*$")
		if re.search(text):
			text = re.sub(text, line)
		else:
			text = text.rstrip("\n") + "\n" + line + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- Edificios -----------------------------------------------------------------

## Arma un bloque isométrico por estilo, cantidad de pisos y variante: planta
## baja + pisos altos (fachadas de assets/art/buildings) y el techo encima (el
## mismo tile de suelo del estilo). Un atlas por altura. Devuelve las variantes.
func _pack_buildings() -> int:
	var facades := _read_facades()
	var roofs: Dictionary = _images.get("tiles/ground", {})
	var styles := WorldTiles.BUILDING_STYLES
	if not _errors.is_empty():
		return BUILDING_VARIANTS
	for floors in range(1, WorldTiles.BUILDING_MAX_FLOORS + 1):
		var region := WorldTiles.building_region(floors)
		var atlas := _new_atlas(region, Vector2i(styles.size(), BUILDING_VARIANTS))
		for col in styles.size():
			var style := str(WorldTiles.Ground.keys()[styles[col]]).to_lower()
			var roof_list: Array = roofs.get(style, [])
			roof_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.n < b.n)
			for k in BUILDING_VARIANTS:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(style) + floors * 131 + k * 7919
				var roof: Image = _quantile(roof_list, (k + 0.5) / BUILDING_VARIANTS).image
				_put(atlas, _compose_building(facades[style], roof, floors, rng), region, Vector2i(col, k))
		_save(atlas, "buildings_%d.png" % floors)
	return BUILDING_VARIANTS


func _compose_building(facade: Dictionary, roof: Image, floors: int, rng: RandomNumberGenerator) -> Image:
	var region := WorldTiles.building_region(floors) * S
	var floor_px := WorldTiles.BUILDING_FLOOR_PX * S
	var half_tile := WorldTiles.TILE_SIZE.y * S / 2
	var img := Image.create_empty(region.x, region.y, false, Image.FORMAT_RGBA8)
	# La base del bloque es el rombo de la celda: su vértice izquierdo en y = base.
	var base := region.y - half_tile
	for j in floors:
		var module: Image = _weighted(facade.ground if j == 0 else facade.upper, rng).image
		img.blend_rect(module, Rect2i(Vector2i.ZERO, module.get_size()), Vector2i(0, base - (j + 1) * floor_px + S))
	var top := base - floors * floor_px + S
	# Cornisa: la franja de arriba de las paredes, un poco más clara.
	for x in region.x:
		var y0 := top + (x / 2 if x < region.x / 2 else (region.x - 1 - x) / 2)
		for i in S:
			var c := img.get_pixel(x, y0 + i)
			if c.a > 0.0:
				img.set_pixel(x, y0 + i, c.lightened(0.16 * (1.0 - float(i) / S)))
	img.blend_rect(roof, Rect2i(Vector2i.ZERO, roof.get_size()), Vector2i(0, top - half_tile))
	return img


## estilo -> {ground: Array[{n, weight, image}], upper: [...]}
func _read_facades() -> Dictionary:
	var folder := "buildings"
	var size := WorldTiles.BUILDING_FACADE_SIZE * S
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
		if img == null or img.get_size() != size:
			_errors.append("%s/%s: debe medir %dx%d" % [folder, f, size.x, size.y])
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


## Personajes (skins): cada PNG de characters/ es uno. Hoja de 5 x 8 frames de
## 32x48 px del mundo, dibujada a x1 (pixel art) o a una escala entera (x2, x4…).
func _check_player() -> void:
	var dir := ProjectSettings.globalize_path(ART + "/characters")
	var sheets := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension() == "png")
	if sheets.is_empty():
		_errors.append("characters/: falta al menos una hoja de personaje (player01.png)")
		return
	var logical := Vector2i(32 * 5, 48 * 8)
	for file: String in sheets:
		var img := Image.load_from_file(dir.path_join(file))
		var k := img.get_width() / logical.x
		if k < 1 or img.get_size() != logical * k:
			_errors.append("characters/%s: mide %s y debe medir %dx%d (5 columnas x 8 filas de 32x48) o un múltiplo exacto (x2, x4…)" % [file, img.get_size(), logical.x, logical.y])


func _summary(table: Array) -> String:
	var total := 0
	for w: Array in table:
		total += w.size()
	return "%d tipos, %d variantes" % [table.size(), total]
