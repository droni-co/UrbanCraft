import { createHash } from 'node:crypto'
import { gzipSync, gunzipSync } from 'node:zlib'
import type { MapLabel } from '#map/labels'
import type { ChunkGrid, Poi } from '#map/rasterizer'

/**
 * Formato de transporte/almacenamiento de un chunk (JSON comprimido con gzip).
 * Se guarda ya comprimido: el servidor lo envía tal cual con
 * Content-Encoding: gzip, sin recomprimir en cada petición.
 */
export interface ChunkPayload {
  format: 1
  z: number
  x: number
  y: number
  size: number
  cellZoom: number
  generatorVersion: number
  /** base64 de size*size bytes (ids de Ground). */
  ground: string
  /** base64 de size*size bytes (ids de Prop, 255 = vacío). */
  props: string
  /** base64 de size*size bytes: pisos del edificio de cada celda (0 = no es edificio). */
  levels: string
  pois: Poi[]
  labels: MapLabel[]
  /** Barrio en el que cae el chunk, o null (ver LabelIndex.districtAt). */
  district: string | null
  osmTimestamp: string | null
  attribution: string
}

export interface EncodedChunk {
  data: Buffer
  etag: string
}

export function encodeChunk(
  grid: ChunkGrid,
  meta: {
    cellZoom: number
    generatorVersion: number
    osmTimestamp: string | null
    attribution: string
  }
): EncodedChunk {
  const payload: ChunkPayload = {
    format: 1,
    z: grid.z,
    x: grid.x,
    y: grid.y,
    size: grid.size,
    cellZoom: meta.cellZoom,
    generatorVersion: meta.generatorVersion,
    ground: Buffer.from(grid.ground).toString('base64'),
    props: Buffer.from(grid.props).toString('base64'),
    levels: Buffer.from(grid.levels).toString('base64'),
    pois: grid.pois,
    labels: grid.labels,
    district: grid.district,
    osmTimestamp: meta.osmTimestamp,
    attribution: meta.attribution,
  }
  const data = gzipSync(JSON.stringify(payload), { level: 9 })
  const etag = `"v${meta.generatorVersion}-${createHash('sha1').update(data).digest('hex').slice(0, 16)}"`
  return { data, etag }
}

export function decodeChunk(data: Buffer): ChunkPayload {
  return JSON.parse(gunzipSync(data).toString('utf8')) as ChunkPayload
}
