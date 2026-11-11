class_name WorldTiles
extends RefCounted
## Catálogo de tiles del mundo. Única fuente de verdad para los ids de atlas
## que usan el generador de arte, el TileSet, el generador de mapas y el juego.

const TILE_SIZE := Vector2i(64, 32)

const SOURCE_GROUND := 0
const SOURCE_PROPS := 1

## Tamaño de cada región del atlas de props (más altos que un tile).
const PROP_REGION := Vector2i(64, 64)
## Desplaza la textura del prop hacia arriba para que su base quede sobre el rombo.
const PROP_TEXTURE_ORIGIN := Vector2i(0, 16)

## Nombre del custom data layer booleano del TileSet que indica si se puede caminar.
const WALKABLE := "walkable"

enum Ground { GRASS, GRASS_DARK, DIRT, SAND, WATER, STONE }
enum Prop { TREE, PINE, ROCK, BUSH }

const UNWALKABLE_GROUND: Array[int] = [Ground.WATER]


static func ground_coords(kind: int) -> Vector2i:
	return Vector2i(kind, 0)


static func prop_coords(kind: int) -> Vector2i:
	return Vector2i(kind, 0)
