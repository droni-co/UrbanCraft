class_name WorldTiles
extends RefCounted
## Catálogo de tiles del mundo. Única fuente de verdad para los ids de atlas
## que usan el generador de arte, el TileSet, el generador de mapas y el juego.
##
## IMPORTANTE: los ids deben coincidir con apps/backend/app/map/catalog.ts
## (el servidor genera los chunks con esos ids). Agrega valores solo al final.
## Al cargar el mapa se validan los nombres contra GET /api/v1/map/config.

const TILE_SIZE := Vector2i(64, 32)

const SOURCE_GROUND := 0
const SOURCE_PROPS := 1

## Tamaño de cada región del atlas de props (más altos que un tile).
const PROP_REGION := Vector2i(64, 64)
## Desplaza la textura del prop hacia arriba para que su base quede sobre el rombo.
const PROP_TEXTURE_ORIGIN := Vector2i(0, 16)

## Nombre del custom data layer booleano del TileSet que indica si se puede caminar.
const WALKABLE := "walkable"

enum Ground { GRASS, GRASS_DARK, DIRT, SAND, WATER, STONE, ASPHALT, PAVEMENT, BUILDING }
enum Prop { TREE, PINE, ROCK, BUSH }

## Valor de "sin prop" en los chunks del servidor.
const NO_PROP := 255

const UNWALKABLE_GROUND: Array[int] = [Ground.WATER, Ground.BUILDING]


## Metadatos del TileSet con los pesos de las variantes de cada tipo
## (los escribe tools/generate_tileset.gd a partir de assets/art).
const META_GROUND_WEIGHTS := "ground_variant_weights"
const META_PROP_WEIGHTS := "prop_variant_weights"

## Atlas: columna = tipo, fila = variante.
static var _ground_weights: Array = []
static var _prop_weights: Array = []


static func ground_coords(kind: int, variant := 0) -> Vector2i:
	return Vector2i(kind, variant)


static func prop_coords(kind: int, variant := 0) -> Vector2i:
	return Vector2i(kind, variant)


## Carga los pesos de las variantes desde el TileSet (una vez basta).
static func load_variants(tile_set: TileSet) -> void:
	if tile_set == null:
		return
	_ground_weights = tile_set.get_meta(META_GROUND_WEIGHTS, [])
	_prop_weights = tile_set.get_meta(META_PROP_WEIGHTS, [])


## Coordenadas de atlas para un suelo en una celda GLOBAL. La variante sale de
## un hash de la celda: estable entre sesiones, chunks y jugadores.
static func pick_ground(kind: int, gx: int, gy: int) -> Vector2i:
	return Vector2i(kind, _pick(_ground_weights, kind, cell_hash(gx, gy, 0x51ed)))


static func pick_prop(kind: int, gx: int, gy: int) -> Vector2i:
	return Vector2i(kind, _pick(_prop_weights, kind, cell_hash(gx, gy, 0x2b7f)))


static func _pick(table: Array, kind: int, h: int) -> int:
	if kind >= table.size():
		return 0
	var weights: Array = table[kind]
	if weights.size() <= 1:
		return 0
	var total := 0.0
	for w in weights:
		total += float(w)
	var t := float(h % 1000003) / 1000003.0 * total
	for i in weights.size():
		t -= float(weights[i])
		if t < 0.0:
			return i
	return weights.size() - 1


## Hash entero de una celda (no negativo, determinista en todas las plataformas).
static func cell_hash(x: int, y: int, salt: int) -> int:
	var h := (x * 0x27d4eb2d) ^ (y * 0x165667b1) ^ (salt * 0x9e3779b1)
	h = (h ^ (h >> 15)) * 0x2c1b3c6d
	h = (h ^ (h >> 12)) * 0x297a2d39
	h ^= h >> 15
	return h & 0x7fffffff
