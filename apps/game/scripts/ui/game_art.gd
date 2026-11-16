class_name GameArt
extends RefCounted
## Arte de las mecánicas (Layer.ai, ver assets/art/README.md): iconos de
## objetos, medallas de logros, retratos de personajes y objetos del mapa.

const ITEM_DIR := "res://assets/art/items/"
const MEDAL_DIR := "res://assets/art/medals/"
const NPC_DIR := "res://assets/art/npcs/"
const OBJECT_DIR := "res://assets/art/objects/"

## Colores de las medallas: bronce, plata, oro y diamante.
const TIER_COLORS: Array[Color] = [Color("c98a55"), Color("c9d2dc"), Color("f2c14e"), Color("7fd8f0")]
const TIER_NAMES: Array[String] = ["Bronce", "Plata", "Oro", "Diamante"]

static var _cache := {}


static func item(key: String) -> Texture2D:
	return _load(ITEM_DIR + key + ".png", ITEM_DIR + "paquete.png")


static func medal(emblem: String) -> Texture2D:
	return _load(MEDAL_DIR + emblem + ".png", MEDAL_DIR + "trofeo.png")


static func portrait(key: String) -> Texture2D:
	return _load(NPC_DIR + key + ".png", NPC_DIR + "vecino.png")


## Sprite de un objeto del mapa según su tipo y estado.
static func object(kind: String, state := {}) -> Texture2D:
	var name := kind
	match kind:
		"matera":
			name = "matera_%d" % clampi(int(state.get("stage", 0)), 0, 2)
		"caja":
			name = "caja_open" if state.get("filled", false) else "caja"
		"puesto":
			name = "puesto" if state.get("open", false) else "puesto_vacio"
	return _load(OBJECT_DIR + name + ".png", OBJECT_DIR + "caja.png")


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier - 1, 0, TIER_COLORS.size() - 1)]


static func _load(path: String, fallback: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else load(fallback)
	return _cache[path]
