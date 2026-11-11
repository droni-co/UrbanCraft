import type { Feature, FeatureSet } from '#map/features'
import { worldToLat, worldToLon, type BBox, type LonLat } from '#map/geo'
import { OsmProvider, type OsmProviderError } from '#map/providers/osm_provider'

export const CELL_ZOOM = 24
export const CHUNK_ZOOM = 18
export const CHUNK_SIZE = 64

/** Chunk de prueba en Madrid (Puerta de Alcalá). */
export const TEST_CHUNK = { z: 18, x: 128385, y: 98843 }

/** Lon/lat de una posición local (en celdas, admite decimales) dentro de un chunk. */
export function localToLonLat(chunk: { x: number; y: number }, lx: number, ly: number): LonLat {
  const gx = chunk.x * CHUNK_SIZE + lx
  const gy = chunk.y * CHUNK_SIZE + ly
  return [worldToLon(gx, CELL_ZOOM), worldToLat(gy, CELL_ZOOM)]
}

export function line(chunk: { x: number; y: number }, points: Array<[number, number]>): LonLat[] {
  return points.map(([lx, ly]) => localToLonLat(chunk, lx, ly))
}

export function rect(
  chunk: { x: number; y: number },
  x0: number,
  y0: number,
  x1: number,
  y1: number
): LonLat[] {
  return line(chunk, [
    [x0, y0],
    [x1, y0],
    [x1, y1],
    [x0, y1],
    [x0, y0],
  ])
}

export function featureSet(features: Feature[]): FeatureSet {
  return { features, osmTimestamp: '2026-01-01T00:00:00Z' }
}

export class FakeOsmProvider extends OsmProvider {
  readonly name = 'fake'
  calls: BBox[] = []

  constructor(
    private set: FeatureSet,
    private error: OsmProviderError | null = null
  ) {
    super()
  }

  async fetchFeatures(bbox: BBox): Promise<FeatureSet> {
    this.calls.push(bbox)
    if (this.error) throw this.error
    return this.set
  }
}
