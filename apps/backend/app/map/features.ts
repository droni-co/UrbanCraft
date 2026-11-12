import { gzipSync, gunzipSync } from 'node:zlib'
import type { LonLat } from '#map/geo'

/**
 * Formato normalizado de datos geográficos, independiente del proveedor
 * (Overpass hoy, import local de PostGIS mañana). Es lo que se guarda en
 * osm_source_tiles.data y lo que consume el rasterizador.
 */

export type Tags = Record<string, string>

export interface PointFeature {
  kind: 'point'
  id: string
  tags: Tags
  coord: LonLat
}

export interface LineFeature {
  kind: 'line'
  id: string
  tags: Tags
  coords: LonLat[]
}

/**
 * Área. `rings` es un conjunto de polilíneas cuyos bordes, juntos, forman
 * anillos cerrados (exteriores e interiores). El rasterizador usa la regla
 * par-impar, así que no hace falta ensamblar ni orientar los anillos de un
 * multipolígono: basta con tener todos sus segmentos.
 */
export interface AreaFeature {
  kind: 'area'
  id: string
  tags: Tags
  rings: LonLat[][]
}

export type Feature = PointFeature | LineFeature | AreaFeature

export interface FeatureSet {
  features: Feature[]
  /** Fecha de los datos OSM según el proveedor (ISO 8601). */
  osmTimestamp: string | null
}

/** Solo guardamos las etiquetas que usa el juego (reduce mucho el tamaño). */
export const KEPT_TAGS = new Set([
  'highway',
  'building',
  'natural',
  'landuse',
  'leisure',
  'waterway',
  'water',
  'amenity',
  'shop',
  'tourism',
  'historic',
  'name',
  'area',
  'tunnel',
  'bridge',
  'layer',
  'location',
  'surface',
  'place',
  'parking',
  'leaf_type',
  'area:highway',
  // Números de portal (etiquetas de casas).
  'addr:housenumber',
  // Detalle local (dataVersion 2): tipos y alturas de edificio, vías férreas,
  // pasos de cebra, andenes, mobiliario urbano, barrios y más comercios.
  'building:levels',
  'height',
  'railway',
  'crossing',
  'footway',
  'sidewalk',
  'service',
  'office',
  'craft',
  'cuisine',
  'public_transport',
  'bus',
])

export function pickTags(tags: Record<string, string> | undefined): Tags {
  const out: Tags = {}
  if (!tags) return out
  for (const key of Object.keys(tags)) {
    if (KEPT_TAGS.has(key)) out[key] = tags[key]
  }
  return out
}

const round7 = (n: number) => Math.round(n * 1e7) / 1e7

export function roundCoord(lon: number, lat: number): LonLat {
  return [round7(lon), round7(lat)]
}

export function encodeFeatureSet(set: FeatureSet): Buffer {
  return gzipSync(JSON.stringify({ v: 1, ...set }))
}

export function decodeFeatureSet(data: Buffer): FeatureSet {
  const parsed = JSON.parse(gunzipSync(data).toString('utf8'))
  return { features: parsed.features ?? [], osmTimestamp: parsed.osmTimestamp ?? null }
}
