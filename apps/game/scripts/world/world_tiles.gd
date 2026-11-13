class_name WorldTiles
extends RefCounted
## Catálogo de tiles del mundo. Única fuente de verdad para los ids de atlas
## que usan el generador de arte, el TileSet, el generador de mapas y el juego.
##
## IMPORTANTE: los ids deben coincidir con apps/backend/app/map/catalog.ts
## (el servidor genera los chunks con esos ids). Agrega valores solo al final.
## Al cargar el mapa se validan los nombres contra GET /api/v1/map/config.

## Todo lo de este archivo está en píxeles LÓGICOS (los del mundo). El arte se
## dibuja ART_SCALE veces más grande (un tile de suelo mide 256x128 en su PNG)
## y se muestra con HDTexture: más detalle sin cambiar las coordenadas.
const TILE_SIZE := Vector2i(64, 32)
const ART_SCALE := 4
## Separación entre regiones de los atlas (en px lógicos): el borde de cada
## imagen se repite ahí para que el filtro lineal no mezcle tiles vecinos.
const ATLAS_SEPARATION := Vector2i(1, 1)

const SOURCE_GROUND := 0
const SOURCE_PROPS := 1
## Edificios: un atlas por cantidad de pisos (source = SOURCE_BUILDINGS + pisos - 1).
const SOURCE_BUILDINGS := 2

## Tamaño de cada región del atlas de props (más altos que un tile).
const PROP_REGION := Vector2i(64, 64)
## Desplaza la textura del prop hacia arriba para que su base quede sobre el rombo.
const PROP_TEXTURE_ORIGIN := Vector2i(0, 16)

## Edificios en 3D isométrico: un bloque por celda (paredes + techo), armado
## por tools/build_art.gd a partir de assets/art/buildings/ y los techos.
## Un atlas por altura; en cada uno: columna = estilo (BUILDING_STYLES), fila = variante.
const BUILDING_FLOOR_PX := 26
const BUILDING_MAX_FLOORS := 6
## Una imagen de fachada: las dos paredes de un piso (ver assets/art/README.md).
const BUILDING_FACADE_SIZE := Vector2i(64, BUILDING_FLOOR_PX + 16)

## Nombre del custom data layer booleano del TileSet que indica si se puede caminar.
const WALKABLE := "walkable"

enum Ground {
	GRASS, GRASS_DARK, DIRT, SAND, WATER, STONE, ASPHALT, PAVEMENT, BUILDING,
	ROOF_BRICK, ROOF_CONCRETE, ROOF_DARK, ROOF_CIVIC, ROOF_INDUSTRIAL,
	CROSSWALK, RAIL, CYCLEWAY,
}
enum Prop {
	TREE, PINE, ROCK, BUSH,
	BENCH, STREET_LAMP, TRAFFIC_LIGHT, BUS_STOP, FOUNTAIN, STATUE,
}

## Valor de "sin prop" en los chunks del servidor.
const NO_PROP := 255

const UNWALKABLE_GROUND: Array[int] = [
	Ground.WATER, Ground.BUILDING,
	Ground.ROOF_BRICK, Ground.ROOF_CONCRETE, Ground.ROOF_DARK, Ground.ROOF_CIVIC, Ground.ROOF_INDUSTRIAL,
]


## Suelos que se dibujan como edificio, en el orden de las columnas del atlas.
const BUILDING_STYLES: Array[int] = [
	Ground.BUILDING, Ground.ROOF_BRICK, Ground.ROOF_CONCRETE,
	Ground.ROOF_DARK, Ground.ROOF_CIVIC, Ground.ROOF_INDUSTRIAL,
]
## Pisos si el chunk no los trae (chunks viejos o mapa de demostración).
const DEFAULT_FLOORS := {
	Ground.BUILDING: 2, Ground.ROOF_BRICK: 2, Ground.ROOF_CONCRETE: 3,
	Ground.ROOF_DARK: 5, Ground.ROOF_CIVIC: 2, Ground.ROOF_INDUSTRIAL: 1,
}


## Metadatos del TileSet con los pesos de las variantes de cada tipo
## (los escribe tools/generate_tileset.gd a partir de assets/art).
const META_GROUND_WEIGHTS := "ground_variant_weights"
const META_PROP_WEIGHTS := "prop_variant_weights"
const META_BUILDING_VARIANTS := "building_variants"

## Atlas de props: columna = tipo, fila = variante. El de suelo va al revés
## (fila = tipo) para que no pase de 4096 px de ancho a x4 (límite de algunas GPU).
static var _ground_weights: Array = []
static var _prop_weights: Array = []
static var _building_variants := 1


static func ground_coords(kind: int, variant := 0) -> Vector2i:
	return Vector2i(variant, kind)


## Tipo de suelo (WorldTiles.Ground) de unas coordenadas del atlas de suelo.
static func ground_kind(coords: Vector2i) -> int:
	return coords.y


static func prop_coords(kind: int, variant := 0) -> Vector2i:
	return Vector2i(kind, variant)


## Carga los pesos de las variantes desde el TileSet (una vez basta).
static func load_variants(tile_set: TileSet) -> void:
	if tile_set == null:
		return
	_ground_weights = tile_set.get_meta(META_GROUND_WEIGHTS, [])
	_prop_weights = tile_set.get_meta(META_PROP_WEIGHTS, [])
	_building_variants = maxi(1, int(tile_set.get_meta(META_BUILDING_VARIANTS, 1)))


## Coordenadas de atlas para un suelo en una celda GLOBAL. La variante sale de
## un hash de la celda: estable entre sesiones, chunks y jugadores.
static func pick_ground(kind: int, gx: int, gy: int) -> Vector2i:
	return ground_coords(kind, _pick(_ground_weights, kind, cell_hash(gx, gy, 0x51ed)))


static func pick_prop(kind: int, gx: int, gy: int) -> Vector2i:
	return Vector2i(kind, _pick(_prop_weights, kind, cell_hash(gx, gy, 0x2b7f)))


static func is_building(ground_kind: int) -> bool:
	return ground_kind in BUILDING_STYLES


## Pisos de un edificio: los del servidor (`levels`, 0 = no los sabe) o los
## típicos de su estilo, entre 1 y BUILDING_MAX_FLOORS.
static func building_floors(ground_kind: int, levels: int) -> int:
	return clampi(levels if levels > 0 else int(DEFAULT_FLOORS.get(ground_kind, 2)), 1, BUILDING_MAX_FLOORS)


## Atlas (source del TileSet) de los edificios de `floors` pisos.
static func building_source(floors: int) -> int:
	return SOURCE_BUILDINGS + clampi(floors, 1, BUILDING_MAX_FLOORS) - 1


static func is_building_source(source_id: int) -> bool:
	return source_id >= SOURCE_BUILDINGS and source_id < SOURCE_BUILDINGS + BUILDING_MAX_FLOORS


## Región de un bloque de `floors` pisos: techo (un rombo) + paredes + 4 px de margen.
static func building_region(floors: int) -> Vector2i:
	return Vector2i(TILE_SIZE.x, TILE_SIZE.y + BUILDING_FLOOR_PX * floors + 4)


## La base del bloque (centro del rombo, 16 px sobre el borde de abajo) cae en el centro de la celda.
static func building_texture_origin(floors: int) -> Vector2i:
	return Vector2i(0, building_region(floors).y / 2 - TILE_SIZE.y / 2)


## Coordenadas en el atlas de su altura (building_source) del bloque de una
## celda GLOBAL, o (-1, -1) si ese suelo no es edificio.
static func pick_building(ground_kind: int, gx: int, gy: int) -> Vector2i:
	var style := BUILDING_STYLES.find(ground_kind)
	if style < 0:
		return Vector2i(-1, -1)
	return Vector2i(style, cell_hash(gx, gy, 0x6b1d) % _building_variants)


## Altura en píxeles de las paredes de un bloque (por el atlas en que está).
static func building_wall_height(source_id: int) -> int:
	return (source_id - SOURCE_BUILDINGS + 1) * BUILDING_FLOOR_PX


static func building_variants() -> int:
	return _building_variants


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
