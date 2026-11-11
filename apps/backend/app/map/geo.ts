/**
 * Utilidades geográficas en Web Mercator (EPSG:3857) con esquema slippy-map.
 *
 * "world units" a un zoom z = coordenada continua en la grilla de tiles de ese
 * zoom (0..2^z). Una celda del juego es un tile a cellZoom, un chunk es un tile
 * a chunkZoom, etc. Las conversiones entre niveles son potencias de 2 exactas.
 */

export type LonLat = [lon: number, lat: number]

export interface BBox {
  west: number
  south: number
  east: number
  north: number
}

export const MAX_LATITUDE = 85.05112878
const EARTH_CIRCUMFERENCE_M = 40_075_016.686
const METERS_PER_DEGREE_LAT = 111_320

export function lonToWorld(lon: number, zoom: number): number {
  return ((lon + 180) / 360) * 2 ** zoom
}

export function latToWorld(lat: number, zoom: number): number {
  const clamped = Math.max(Math.min(lat, MAX_LATITUDE), -MAX_LATITUDE)
  const rad = (clamped * Math.PI) / 180
  return ((1 - Math.asinh(Math.tan(rad)) / Math.PI) / 2) * 2 ** zoom
}

export function worldToLon(x: number, zoom: number): number {
  return (x / 2 ** zoom) * 360 - 180
}

export function worldToLat(y: number, zoom: number): number {
  const n = Math.PI * (1 - (2 * y) / 2 ** zoom)
  return (Math.atan(Math.sinh(n)) * 180) / Math.PI
}

/** Tile entero que contiene la coordenada. */
export function lonLatToTile(lon: number, lat: number, zoom: number): [number, number] {
  const max = 2 ** zoom - 1
  return [
    Math.min(Math.max(Math.floor(lonToWorld(lon, zoom)), 0), max),
    Math.min(Math.max(Math.floor(latToWorld(lat, zoom)), 0), max),
  ]
}

export function tileBounds(z: number, x: number, y: number): BBox {
  return {
    west: worldToLon(x, z),
    east: worldToLon(x + 1, z),
    north: worldToLat(y, z),
    south: worldToLat(y + 1, z),
  }
}

export function isValidTile(z: number, x: number, y: number): boolean {
  const n = 2 ** z
  return Number.isInteger(x) && Number.isInteger(y) && x >= 0 && y >= 0 && x < n && y < n
}

/** Tile ancestro (zoom menor) que contiene al tile dado. */
export function parentTile(z: number, x: number, y: number, parentZoom: number): [number, number] {
  const factor = 2 ** (z - parentZoom)
  return [Math.floor(x / factor), Math.floor(y / factor)]
}

/** Tiles descendientes (zoom mayor) de un tile. */
export function childTiles(
  z: number,
  x: number,
  y: number,
  childZoom: number
): Array<[number, number]> {
  const factor = 2 ** (childZoom - z)
  const tiles: Array<[number, number]> = []
  for (let dy = 0; dy < factor; dy++) {
    for (let dx = 0; dx < factor; dx++) {
      tiles.push([x * factor + dx, y * factor + dy])
    }
  }
  return tiles
}

/** Metros que mide una unidad de mundo (un tile) a esta latitud y zoom. */
export function metersPerUnit(lat: number, zoom: number): number {
  return (EARTH_CIRCUMFERENCE_M * Math.cos((lat * Math.PI) / 180)) / 2 ** zoom
}

export function expandBBox(bbox: BBox, meters: number): BBox {
  const midLat = (bbox.north + bbox.south) / 2
  const dLat = meters / METERS_PER_DEGREE_LAT
  const dLon = meters / (METERS_PER_DEGREE_LAT * Math.cos((midLat * Math.PI) / 180))
  return {
    west: bbox.west - dLon,
    east: bbox.east + dLon,
    south: Math.max(bbox.south - dLat, -MAX_LATITUDE),
    north: Math.min(bbox.north + dLat, MAX_LATITUDE),
  }
}

/** Tiles a `zoom` que cubren un círculo de `radiusMeters` alrededor de un punto. */
export function tilesAround(
  lon: number,
  lat: number,
  radiusMeters: number,
  zoom: number
): Array<[number, number]> {
  const box = expandBBox({ west: lon, east: lon, south: lat, north: lat }, radiusMeters)
  const [x0, y0] = lonLatToTile(box.west, box.north, zoom)
  const [x1, y1] = lonLatToTile(box.east, box.south, zoom)
  const tiles: Array<[number, number]> = []
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) tiles.push([x, y])
  }
  return tiles
}
