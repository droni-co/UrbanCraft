class_name CharacterSkins
extends RefCounted
## Catálogo de personajes (skins): cada PNG de assets/art/characters/ es un
## personaje elegible, con id = nombre del archivo sin extensión ("mateo").
## Para agregar uno basta con poner su hoja ahí (formato en assets/art/README.md).
##
## Dos formatos de hoja, con filas por dirección (e, se, s, sw, w, nw, n, ne) y
## frames de 32x48 px del mundo; se distinguen por la forma:
##
## - Animada (cuadrada, 768x768 lógicos = 24 columnas x 16 filas): dos bandas
##   de 8 filas con las animaciones de ANIMATED. Pies en (16, 40). La bici usa
##   cuadros dobles (64x48, pies en (32, 40)). La arma tools/characters/ desde
##   modelos 3D (ver assets/art/README.md).
## - Simple (160 px lógicos de ancho, 5 columnas): quieto + 4 pasos, pies en
##   (16, 44). Si las filas están un poco corridas se alinean al cargar: cada
##   fila se mueve en bloque para que su píxel más bajo quede en la línea de
##   los pies. El PNG no se modifica.
##
## La hoja puede venir a una escala entera (x2, x3…): se detecta por su ancho,
## se muestra al mismo tamaño en el mundo y con filtro lineal en lugar de
## "nearest" (que es para el pixel art a x1).

const DIR := "res://assets/art/characters/"
const DEFAULT := "mateo"
const DIRECTIONS: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const FRAME_SIZE := Vector2i(32, 48)
## Pies de la hoja simple (y referencia para colgar el apodo y las burbujas).
const FEET := Vector2i(16, 44)
const WALK_FRAMES := 4
const WALK_FPS := 8.0
## Hoja animada: 24 columnas x 16 filas (dos bandas de 8 direcciones).
const ANIMATED_COLUMNS := 24
const ANIMATED_ROWS := 16
## Pies en la hoja animada, dentro del cuadro ancho (64x48) que usan todas sus
## animaciones (las de 32 px se centran con margen).
const ANIMATED_FEET := Vector2i(32, 40)
## Columna, banda (0 = filas 0-7, 1 = filas 8-15), cuadros, ancho en columnas,
## velocidad y si se repite. Las acciones (bike, craft…) las elige quien juega
## con animation_for(…, action).
const ANIMATED := {
	"idle": {"col": 0, "band": 0, "count": 4, "fps": 3.0, "loop": true},
	"walk": {"col": 4, "band": 0, "count": 8, "fps": 11.0, "loop": true},
	"wave": {"col": 12, "band": 0, "count": 4, "fps": 6.0, "loop": true},
	"bike": {"col": 16, "band": 0, "count": 4, "span": 2, "fps": 8.0, "loop": true},
	"craft": {"col": 0, "band": 1, "count": 4, "fps": 6.0, "loop": true},
	"interact": {"col": 4, "band": 1, "count": 4, "fps": 6.0, "loop": true},
	"attack": {"col": 8, "band": 1, "count": 4, "fps": 10.0, "loop": false},
	"defend": {"col": 12, "band": 1, "count": 4, "fps": 6.0, "loop": true},
}
## Acciones (además de idle/walk/wave) que trae la hoja animada.
const ACTIONS: PackedStringArray = ["bike", "craft", "interact", "attack", "defend"]
## Nombres para mostrar con tildes (si no, se capitaliza el id).
const NAMES := {
	"andres": "Andrés", "sofia": "Sofía", "julian": "Julián",
	"don_jorge": "Don Jorge", "dona_rosa": "Doña Rosa",
}
## Opacidad mínima para contar un píxel como dibujo (ignora restos casi transparentes).
const ALPHA_THRESHOLD := 0.16

static var _sheets := {}  # id -> Texture2D alineada
static var _frames := {}  # id -> SpriteFrames
static var _scales := {}  # id -> escala de la hoja (1 = pixel art)
static var _animated := {}  # id -> true si es una hoja animada


## Ids de los personajes disponibles, ordenados alfabéticamente.
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


## Nombre para mostrar: "dona_rosa" -> "Doña Rosa", "player03" -> "Personaje 3",
## "ninja_rojo" -> "Ninja Rojo".
static func display_name(id: String) -> String:
	if NAMES.has(id):
		return NAMES[id]
	var re := RegEx.create_from_string("^player0*(\\d+)$")
	var m := re.search(id)
	if m:
		return "Personaje %s" % m.get_string(1)
	return id.capitalize()


## Animaciones <anim>_<dir> del personaje (idle y walk siempre; en las hojas
## animadas también wave y las acciones), compartidas y cacheadas.
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
			if _animated.get(skin, false):
				for anim: String in ANIMATED:
					var spec: Dictionary = ANIMATED[anim]
					var anim_name: String = anim + "_" + dir
					sprite_frames.add_animation(anim_name)
					sprite_frames.set_animation_speed(anim_name, spec.fps)
					sprite_frames.set_animation_loop(anim_name, spec.loop)
					for i in int(spec.count):
						sprite_frames.add_frame(anim_name, _animated_frame(sheet, anim, i, row))
				continue
			sprite_frames.add_animation("idle_" + dir)
			sprite_frames.add_frame("idle_" + dir, frame(sheet, 0, row))
			sprite_frames.add_animation("walk_" + dir)
			sprite_frames.set_animation_speed("walk_" + dir, WALK_FPS)
			for col in range(1, WALK_FRAMES + 1):
				sprite_frames.add_frame("walk_" + dir, frame(sheet, col, row))
		_frames[skin] = sprite_frames
	return _frames[skin]


## Región (px del mundo) del cuadro `index` de `anim` en la dirección `row`
## de una hoja animada.
static func animated_region(anim: String, index: int, row: int) -> Rect2:
	var spec: Dictionary = ANIMATED[anim]
	var span := int(spec.get("span", 1))
	var col := int(spec.col) + index * span
	var y := int(spec.band) * DIRECTIONS.size() + row
	return Rect2(Vector2(col * FRAME_SIZE.x, y * FRAME_SIZE.y), Vector2(FRAME_SIZE.x * span, FRAME_SIZE.y))


## Cuadro de una hoja animada, siempre de 64x48 con los pies en ANIMATED_FEET:
## los de 32 px llevan margen a los lados para que todos compartan el ancla.
static func _animated_frame(sheet: Texture2D, anim: String, index: int, row: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = animated_region(anim, index, row)
	var pad := (ANIMATED_FEET.x * 2 - tex.region.size.x) / 2.0
	if pad > 0.0:
		tex.margin = Rect2(pad, 0, pad * 2.0, 0)
	return tex


## Cuánto dura un saludo (wave_<dir>) antes de volver a quieto.
const WAVE_SECONDS := 1.6


## Nombre de la animación a mostrar. `action` (una de ACTIONS: "bike",
## "craft"…) manda si la hoja la tiene; si no, saludo (quieto) o caminar/quieto.
static func animation_for(sprite: AnimatedSprite2D, moving: bool, waving: bool, dir: String, action := "") -> String:
	if not action.is_empty() and sprite and sprite.sprite_frames.has_animation(action + "_" + dir):
		return action + "_" + dir
	if waving and not moving and sprite and sprite.sprite_frames.has_animation("wave_" + dir):
		return "wave_" + dir
	return ("walk_" if moving else "idle_") + dir


## Si el personaje tiene la acción (las hojas simples no traen ninguna).
static func has_action(id: Variant, action: String) -> bool:
	var sprite_frames := frames(id)
	return sprite_frames != null and sprite_frames.has_animation(action + "_s")


## Respiración procedural para las hojas simples (su "quieto" es un solo
## cuadro): estira el sprite apenas desde los pies. Las animadas ya respiran.
static func breathe(sprite: AnimatedSprite2D, moving: bool, time: float) -> void:
	if sprite == null:
		return
	var still := not moving and sprite.sprite_frames.get_frame_count(sprite.animation) <= 1
	sprite.scale = Vector2(1.0, 1.0 + 0.018 * sin(time * 2.4)) if still else Vector2.ONE


## Sprite animado con los pies en el origen. null si no hay hojas.
static func make_sprite(id: Variant) -> AnimatedSprite2D:
	var sprite_frames := frames(id)
	if sprite_frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = sprite_frames
	sprite.centered = false
	sprite.offset = -Vector2(feet(id))
	sprite.texture_filter = filter_for(resolve(id))
	return sprite


## Punto de los pies dentro de los cuadros de sus animaciones.
static func feet(id: Variant) -> Vector2i:
	var skin := resolve(id)
	if not skin.is_empty():
		sheet_texture(skin)
	return ANIMATED_FEET if _animated.get(skin, false) else FEET


## Filtro para dibujar un personaje: nítido para pixel art, suave para hojas HD.
static func filter_for(id: String) -> CanvasItem.TextureFilter:
	if not id.is_empty():
		sheet_texture(id)
	return CanvasItem.TEXTURE_FILTER_LINEAR if int(_scales.get(id, 1)) > 1 else CanvasItem.TEXTURE_FILTER_NEAREST


## Un frame de la hoja (para vistas previas): columna 0 = quieto, fila 2 = de frente.
## (En ambos formatos la columna 0 es el primer cuadro de quieto.)
static func frame(sheet: Texture2D, col: int, row: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = Rect2(Vector2(col, row) * Vector2(FRAME_SIZE), FRAME_SIZE)
	return tex


## Región del cuadro de caminata que toca a los `time` segundos (vistas previas).
static func walk_region(id: String, row: int, time: float) -> Rect2:
	sheet_texture(id)
	if _animated.get(id, false):
		var spec: Dictionary = ANIMATED.walk
		return animated_region("walk", int(time * float(spec.fps)) % int(spec.count), row)
	var col := 1 + int(time * WALK_FPS) % WALK_FRAMES
	return Rect2(Vector2(col, row) * Vector2(FRAME_SIZE), FRAME_SIZE)


## La hoja del personaje ya alineada.
static func sheet_texture(id: String) -> Texture2D:
	if not _sheets.has(id):
		var source: Texture2D = load(DIR + id + ".png")
		var image := source.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var animated := image.get_width() % (FRAME_SIZE.x * ANIMATED_COLUMNS) == 0 \
			and image.get_width() * FRAME_SIZE.y * ANIMATED_ROWS == image.get_height() * FRAME_SIZE.x * ANIMATED_COLUMNS
		var columns := ANIMATED_COLUMNS if animated else WALK_FRAMES + 1
		var k := maxi(1, image.get_width() / (FRAME_SIZE.x * columns))
		# La hoja animada ya viene alineada cuadro por cuadro.
		var aligned := image if animated else align_rows(image, k)
		if k > 1:
			aligned.generate_mipmaps()
		var texture := ImageTexture.create_from_image(aligned)
		if k > 1:
			# Se usa con regiones en px del mundo (32x48 por frame).
			texture.set_size_override(image.get_size() / k)
		_scales[id] = k
		_animated[id] = animated
		_sheets[id] = texture
	return _sheets[id]


## Mueve cada fila de frames en bloque para que su píxel más bajo quede en la
## línea de los pies (y = fila * 48 + 44). Detecta las franjas de dibujo
## separadas por líneas transparentes y asigna cada una a la fila de su centro.
static func align_rows(image: Image, k := 1) -> Image:
	var frame_h := FRAME_SIZE.y * k
	var rows := image.get_height() / frame_h
	var spans := _opaque_spans(image)
	var per_row := []  # por fila: [top, bottom] o []
	per_row.resize(rows)
	per_row.fill([])
	for span: Vector2i in spans:
		var row := clampi(((span.x + span.y) / 2) / frame_h, 0, rows - 1)
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
		var shift := row * frame_h + FEET.y * k + (k - 1) - bottom
		# Sin salirse de su celda (un dibujo más alto que el frame se deja como está).
		if top + shift < row * frame_h:
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
