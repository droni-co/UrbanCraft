class_name CharacterSkins
extends RefCounted
## Catálogo de personajes (skins): cada PNG de assets/art/characters/ es un
## personaje elegible, con id = nombre del archivo sin extensión ("player03").
## Para agregar uno basta con poner su hoja ahí (formato en assets/art/README.md).
##
## Hoja: 5 columnas (quieto + 4 pasos) x 8 filas (direcciones) de 32x48, con los
## pies en (16, 44) de cada frame. Si las filas están un poco corridas (el
## dibujo no cae justo cada 48 px), se alinean al cargar: cada fila se mueve
## en bloque para que su píxel más bajo quede en la línea de los pies. El PNG
## no se modifica.

const DIR := "res://assets/art/characters/"
const DEFAULT := "player01"
const DIRECTIONS: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const FRAME_SIZE := Vector2i(32, 48)
const FEET := Vector2i(16, 44)
const WALK_FRAMES := 4
const WALK_FPS := 8.0
## Opacidad mínima para contar un píxel como dibujo (ignora restos casi transparentes).
const ALPHA_THRESHOLD := 0.16

static var _sheets := {}  # id -> Texture2D alineada
static var _frames := {}  # id -> SpriteFrames


## Ids de los personajes disponibles, ordenados ("player01", "player02"…).
static func list() -> PackedStringArray:
	var ids := PackedStringArray()
	for file in ResourceLoader.list_directory(DIR):
		if file.get_extension() == "png":
			ids.append(file.get_basename())
	ids.sort()
	return ids


static func exists(id: String) -> bool:
	return not id.is_empty() and ResourceLoader.exists(DIR + id + ".png")


## El personaje a usar para `id`: él mismo si existe; si no, el por defecto
## (o el primero que haya). "" si no hay ninguna hoja.
static func resolve(id: Variant) -> String:
	var wanted := str(id) if id != null else ""
	if exists(wanted):
		return wanted
	if exists(DEFAULT):
		return DEFAULT
	var ids := list()
	return ids[0] if not ids.is_empty() else ""


## Nombre para mostrar: "player03" -> "Personaje 3", "ninja_rojo" -> "Ninja Rojo".
static func display_name(id: String) -> String:
	var re := RegEx.create_from_string("^player0*(\\d+)$")
	var m := re.search(id)
	if m:
		return "Personaje %s" % m.get_string(1)
	return id.capitalize()


## Animaciones idle_<dir> / walk_<dir> del personaje (compartidas y cacheadas).
static func frames(id: Variant) -> SpriteFrames:
	var skin := resolve(id)
	if skin.is_empty():
		return null
	if not _frames.has(skin):
		var sheet := sheet_texture(skin)
		var sprite_frames := SpriteFrames.new()
		sprite_frames.remove_animation("default")
		for row in DIRECTIONS.size():
			var dir := DIRECTIONS[row]
			sprite_frames.add_animation("idle_" + dir)
			sprite_frames.add_frame("idle_" + dir, frame(sheet, 0, row))
			sprite_frames.add_animation("walk_" + dir)
			sprite_frames.set_animation_speed("walk_" + dir, WALK_FPS)
			for col in range(1, WALK_FRAMES + 1):
				sprite_frames.add_frame("walk_" + dir, frame(sheet, col, row))
		_frames[skin] = sprite_frames
	return _frames[skin]


## Sprite animado con los pies en el origen. null si no hay hojas.
static func make_sprite(id: Variant) -> AnimatedSprite2D:
	var sprite_frames := frames(id)
	if sprite_frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = sprite_frames
	sprite.centered = false
	sprite.offset = -Vector2(FEET)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


## Un frame de la hoja (para vistas previas): columna 0 = quieto, fila 2 = de frente.
static func frame(sheet: Texture2D, col: int, row: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = Rect2(Vector2(col, row) * Vector2(FRAME_SIZE), FRAME_SIZE)
	return tex


## La hoja del personaje ya alineada.
static func sheet_texture(id: String) -> Texture2D:
	if not _sheets.has(id):
		var source: Texture2D = load(DIR + id + ".png")
		var image := source.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_sheets[id] = ImageTexture.create_from_image(align_rows(image))
	return _sheets[id]


## Mueve cada fila de frames en bloque para que su píxel más bajo quede en la
## línea de los pies (y = fila * 48 + 44). Detecta las franjas de dibujo
## separadas por líneas transparentes y asigna cada una a la fila de su centro.
static func align_rows(image: Image) -> Image:
	var rows := image.get_height() / FRAME_SIZE.y
	var spans := _opaque_spans(image)
	var per_row := []  # por fila: [top, bottom] o []
	per_row.resize(rows)
	per_row.fill([])
	for span: Vector2i in spans:
		var row := clampi(((span.x + span.y) / 2) / FRAME_SIZE.y, 0, rows - 1)
		var current: Array = per_row[row]
		per_row[row] = [span.x, span.y] if current.is_empty() \
			else [mini(current[0], span.x), maxi(current[1], span.y)]

	var out := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for row in rows:
		var band: Array = per_row[row]
		if band.is_empty():
			continue
		var top: int = band[0]
		var bottom: int = band[1]
		var shift := row * FRAME_SIZE.y + FEET.y - bottom
		# Sin salirse de su celda (un dibujo más alto que el frame se deja como está).
		if top + shift < row * FRAME_SIZE.y:
			shift = 0
		out.blit_rect(image, Rect2i(0, top, image.get_width(), bottom - top + 1), Vector2i(0, top + shift))
	return out


## Franjas horizontales [primera, última] de líneas con algún píxel visible.
static func _opaque_spans(image: Image) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var start := -1
	for y in image.get_height():
		var any := false
		for x in image.get_width():
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				any = true
				break
		if any and start < 0:
			start = y
		elif not any and start >= 0:
			spans.append(Vector2i(start, y - 1))
			start = -1
	if start >= 0:
		spans.append(Vector2i(start, image.get_height() - 1))
	return spans
