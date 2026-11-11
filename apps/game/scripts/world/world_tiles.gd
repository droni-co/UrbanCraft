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


static func ground_coords(kind: int) -> Vector2i:
	return Vector2i(kind, 0)


static func prop_coords(kind: int) -> Vector2i:
	return Vector2i(kind, 0)
