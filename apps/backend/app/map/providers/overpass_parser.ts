import type { AreaFeature, Feature, FeatureSet, Tags } from '#map/features'
import { pickTags, roundCoord } from '#map/features'
import type { LonLat } from '#map/geo'

/**
 * Convierte la respuesta JSON de Overpass (`out geom;`) al formato normalizado.
 */

interface OverpassGeomPoint {
  lat: number
  lon: number
}

interface OverpassElement {
  type: 'node' | 'way' | 'relation'
  id: number
  lat?: number
  lon?: number
  tags?: Record<string, string>
  geometry?: Array<OverpassGeomPoint | null>
  members?: Array<{ type: string; role: string; geometry?: Array<OverpassGeomPoint | null> }>
}

export interface OverpassResponse {
  elements?: OverpassElement[]
  remark?: string
  osm3s?: { timestamp_osm_base?: string }
}

const AREA_NATURAL = new Set([
  'water',
  'wood',
  'beach',
  'sand',
  'scrub',
  'heath',
  'grassland',
  'wetland',
  'bare_rock',
])

/** ¿Una vía cerrada con estas etiquetas representa un área? */
export function isAreaTags(tags: Tags): boolean {
  if (tags.area === 'yes') return true
  if (tags.area === 'no') return false
  if (tags.building || tags.landuse || tags.leisure || tags['area:highway']) return true
  if (tags.natural) return AREA_NATURAL.has(tags.natural)
  if (tags.waterway === 'riverbank') return true
  if (tags.amenity === 'parking' || tags.place === 'square') return true
  return false
}

function toCoords(geometry: Array<OverpassGeomPoint | null> | undefined): LonLat[] {
  if (!geometry) return []
  const coords: LonLat[] = []
  for (const p of geometry) {
    if (p && Number.isFinite(p.lat) && Number.isFinite(p.lon)) coords.push(roundCoord(p.lon, p.lat))
  }
  return coords
}

function isClosed(coords: LonLat[]): boolean {
  if (coords.length < 4) return false
  const [a, b] = [coords[0], coords[coords.length - 1]]
  return a[0] === b[0] && a[1] === b[1]
}

export function parseOverpass(json: OverpassResponse): FeatureSet {
  const features: Feature[] = []

  for (const el of json.elements ?? []) {
    const tags = pickTags(el.tags)

    if (el.type === 'node') {
      if (el.lat === undefined || el.lon === undefined || Object.keys(tags).length === 0) continue
      features.push({ kind: 'point', id: `n${el.id}`, tags, coord: roundCoord(el.lon, el.lat) })
      continue
    }

    if (el.type === 'way') {
      const coords = toCoords(el.geometry)
      if (coords.length < 2) continue
      if (isClosed(coords) && isAreaTags(tags)) {
        features.push({ kind: 'area', id: `w${el.id}`, tags, rings: [coords] })
      } else {
        features.push({ kind: 'line', id: `w${el.id}`, tags, coords })
      }
      continue
    }

    if (el.type === 'relation' && el.tags?.type === 'multipolygon') {
      const rings = (el.members ?? [])
        .filter((m) => m.type === 'way')
        .map((m) => toCoords(m.geometry))
        .filter((r) => r.length >= 2)
      if (rings.length > 0) {
        const area: AreaFeature = { kind: 'area', id: `r${el.id}`, tags, rings }
        features.push(area)
      }
    }
  }

  return { features, osmTimestamp: json.osm3s?.timestamp_osm_base ?? null }
}
