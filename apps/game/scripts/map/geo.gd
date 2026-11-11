class_name Geo
extends RefCounted
## Conversión lat/lon <-> celdas del juego (Web Mercator / slippy tiles).
## Mismo esquema que apps/backend/app/map/geo.ts.
##
## Las celdas globales caben en int32 (2^24 a cellZoom 24), pero NO se usan
## directamente como posición en pantalla: el mundo se dibuja relativo a un
## origen local (ver ChunkManager.origin_cell) para evitar errores de precisión
## de float32 en coordenadas enormes.

const MAX_LATITUDE := 85.05112878
const EARTH_CIRCUMFERENCE_M := 40075016.686


## Coordenada continua (float64) en la grilla de tiles de `zoom`.
static func lon_to_world(lon: float, zoom: int) -> float:
	return (lon + 180.0) / 360.0 * pow(2.0, zoom)


static func lat_to_world(lat: float, zoom: int) -> float:
	var clamped := clampf(lat, -MAX_LATITUDE, MAX_LATITUDE)
	var rad := deg_to_rad(clamped)
	var t := tan(rad)
	return (1.0 - log(t + sqrt(t * t + 1.0)) / PI) / 2.0 * pow(2.0, zoom)


static func world_to_lon(x: float, zoom: int) -> float:
	return x / pow(2.0, zoom) * 360.0 - 180.0


static func world_to_lat(y: float, zoom: int) -> float:
	var n := PI * (1.0 - 2.0 * y / pow(2.0, zoom))
	return rad_to_deg(atan(sinh(n)))


## Celda global que contiene la coordenada.
static func lat_lon_to_cell(lat: float, lon: float, cell_zoom: int) -> Vector2i:
	return Vector2i(floori(lon_to_world(lon, cell_zoom)), floori(lat_to_world(lat, cell_zoom)))


## Lat/lon del centro de una celda global: Vector2(lat, lon) en float64 vía PackedFloat64Array.
static func cell_to_lat_lon(cell: Vector2i, cell_zoom: int) -> PackedFloat64Array:
	return PackedFloat64Array([
		world_to_lat(cell.y + 0.5, cell_zoom),
		world_to_lon(cell.x + 0.5, cell_zoom),
	])


static func meters_per_cell(lat: float, cell_zoom: int) -> float:
	return EARTH_CIRCUMFERENCE_M * cos(deg_to_rad(lat)) / pow(2.0, cell_zoom)


## Chunk que contiene una celda global (las celdas globales son siempre >= 0).
static func cell_to_chunk(cell: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(floori(float(cell.x) / chunk_size), floori(float(cell.y) / chunk_size))


static func chunk_origin(chunk: Vector2i, chunk_size: int) -> Vector2i:
	return chunk * chunk_size
