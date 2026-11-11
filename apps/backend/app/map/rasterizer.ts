import { Ground, NO_PROP, Prop, UNWALKABLE_GROUND } from '#map/catalog'
import type { Feature, FeatureSet, Tags } from '#map/features'
import { latToWorld, lonToWorld, metersPerUnit, worldToLat } from '#map/geo'
import { LabelIndex, type MapLabel } from '#map/labels'

/**
 * Rasterizador: convierte features OSM (lon/lat) en la grilla de tiles de un
 * chunk. Es 100% determinista: mismos datos + misma versión = mismo chunk, lo
 * que permite regenerar sin miedo y comparar resultados.
 *
 * Coordenadas: todo se proyecta a "unidades de celda" globales (Web Mercator a
 * cellZoom). El centro de la celda (cx, cy) está en (cx + 0.5, cy + 0.5).
 */

export interface Poi {
  id: string
  kind: string
  name: string
  /** Celda local dentro del chunk. */
  cell: [number, number]
}

export interface ChunkGrid {
  z: number
  x: number
  y: number
  size: number
  /** size*size ids de Ground, fila por fila (índice = y * size + x). */
  ground: Uint8Array
  /** size*size ids de Prop o NO_PROP. */
  props: Uint8Array
  pois: Poi[]
  /** Nombres de calles, áreas y números de portal (ver labels.ts). */
  labels: MapLabel[]
}

// --- Reglas de estilo ---------------------------------------------------------

/** Decoración procedural que deja un área (árboles en bosques, etc.). */
export const Decor = { NONE: 0, FOREST: 1, PARK: 2, WILD: 3 } as const
type DecorId = (typeof Decor)[keyof typeof Decor]

export interface Paint {
  /** Orden de pintado: mayor prioridad se pinta encima. */
  priority: number
  ground: number
  decor?: DecorId
  /** Solo líneas: ancho real aproximado en metros. */
  widthMeters?: number
  /** Áreas pequeñas (edificios) que no cubren ningún centro de celda igual marcan 1 celda. */
  keepSmall?: boolean
}

const ROAD_WIDTHS: Record<string, number> = {
  motorway: 18,
  trunk: 15,
  primary: 13,
  secondary: 11,
  tertiary: 9,
  unclassified: 7,
  residential: 7,
  busway: 7,
  road: 6,
  living_street: 6,
  service: 4.5,
  motorway_link: 7,
  trunk_link: 7,
  primary_link: 7,
  secondary_link: 6,
  tertiary_link: 6,
}

const PATH_WIDTHS: Record<string, number> = {
  footway: 2.5,
  cycleway: 2.5,
  path: 2,
  steps: 2.5,
  bridleway: 2.5,
  track: 3,
}

const WATERWAY_WIDTHS: Record<string, number> = {
  river: 14,
  canal: 8,
  stream: 3,
  ditch: 1.5,
  drain: 1.5,
}

const SKIPPED_HIGHWAYS = new Set([
  'proposed',
  'abandoned',
  'platform',
  'elevator',
  'corridor',
  'bus_stop',
  'raceway',
  'razed',
])

const UNPAVED = new Set([
  'unpaved',
  'dirt',
  'ground',
  'earth',
  'gravel',
  'fine_gravel',
  'grass',
  'mud',
  'sand',
  'compacted',
  'woodchips',
])

const POI_KEYS = ['amenity', 'shop', 'tourism', 'leisure', 'historic'] as const
const MAX_POIS_PER_CHUNK = 64

function isHidden(tags: Tags): boolean {
  if (tags.tunnel && tags.tunnel !== 'no') return true
  if (tags.location === 'underground') return true
  const layer = Number(tags.layer)
  return Number.isFinite(layer) && layer < 0 && tags.bridge !== 'yes'
}

export function classifyArea(tags: Tags): Paint | null {
  if (isHidden(tags)) return null

  if (tags.building && tags.building !== 'no' && tags.building !== 'roof') {
    return { priority: 70, ground: Ground.BUILDING, keepSmall: true }
  }
  if (
    tags.natural === 'water' ||
    tags.waterway === 'riverbank' ||
    tags.landuse === 'reservoir' ||
    tags.landuse === 'basin'
  ) {
    return { priority: 40, ground: Ground.WATER }
  }
  if (tags.amenity === 'parking' && tags.parking !== 'underground') {
    return { priority: 50, ground: Ground.PAVEMENT }
  }
  if (
    tags.place === 'square' ||
    tags.highway === 'pedestrian' ||
    tags.highway === 'footway' ||
    tags['area:highway'] === 'pedestrian' ||
    tags['area:highway'] === 'footway'
  ) {
    return { priority: 50, ground: Ground.STONE }
  }
  if (tags['area:highway']) return { priority: 50, ground: Ground.ASPHALT }
  if (tags.natural === 'wood' || tags.landuse === 'forest') {
    return { priority: 25, ground: Ground.GRASS_DARK, decor: Decor.FOREST }
  }
  if (tags.natural === 'beach' || tags.natural === 'sand') {
    return { priority: 25, ground: Ground.SAND }
  }
  if (tags.natural === 'wetland') {
    return { priority: 25, ground: Ground.GRASS_DARK, decor: Decor.WILD }
  }
  if (tags.natural === 'bare_rock') return { priority: 25, ground: Ground.STONE }
  if (['scrub', 'heath', 'grassland'].includes(tags.natural) || tags.landuse === 'meadow') {
    return { priority: 20, ground: Ground.GRASS, decor: Decor.WILD }
  }
  if (
    ['park', 'garden', 'nature_reserve', 'dog_park'].includes(tags.leisure) ||
    ['grass', 'village_green', 'recreation_ground', 'cemetery', 'orchard'].includes(tags.landuse)
  ) {
    return { priority: 20, ground: Ground.GRASS, decor: Decor.PARK }
  }
  if (tags.leisure === 'pitch' || tags.leisure === 'golf_course') {
    return { priority: 22, ground: Ground.GRASS }
  }
  if (tags.leisure === 'playground') return { priority: 22, ground: Ground.SAND }
  if (tags.leisure === 'track') return { priority: 22, ground: Ground.DIRT }
  if (['farmland', 'allotments', 'vineyard', 'brownfield', 'construction'].includes(tags.landuse)) {
    return { priority: 15, ground: Ground.DIRT }
  }
  if (['commercial', 'retail', 'industrial', 'railway', 'garages'].includes(tags.landuse)) {
    return { priority: 10, ground: Ground.PAVEMENT }
  }
  return null
}

export function classifyLine(tags: Tags): Paint | null {
  if (isHidden(tags)) return null

  const highway = tags.highway
  if (highway) {
    if (SKIPPED_HIGHWAYS.has(highway)) return null
    if (ROAD_WIDTHS[highway]) {
      return { priority: 60, ground: Ground.ASPHALT, widthMeters: ROAD_WIDTHS[highway] }
    }
    if (highway === 'pedestrian') return { priority: 58, ground: Ground.STONE, widthMeters: 6 }
    if (PATH_WIDTHS[highway]) {
      const unpaved =
        highway === 'track' || (tags.surface ? UNPAVED.has(tags.surface) : highway === 'path')
      return {
        priority: unpaved ? 56 : 57,
        ground: unpaved ? Ground.DIRT : Ground.PAVEMENT,
        widthMeters: PATH_WIDTHS[highway],
      }
    }
    return null
  }

  if (tags.waterway && WATERWAY_WIDTHS[tags.waterway]) {
    return { priority: 45, ground: Ground.WATER, widthMeters: WATERWAY_WIDTHS[tags.waterway] }
  }
  return null
}

// --- Geometría proyectada ------------------------------------------------------

interface PaintOp {
  id: string
  paint: Paint
  /** Segmentos [x1, y1, x2, y2, ...] en unidades de celda globales. */
  segments: Float64Array
  /** Áreas: true (relleno par-impar). Líneas: false (buffer por ancho). */
  fill: boolean
  /** Semiancho en celdas (solo líneas). */
  halfWidth: number
  minX: number
  minY: number
  maxX: number
  maxY: number
}

interface ProjectedPoint {
  id: string
  tags: Tags
  x: number
  y: number
}

export interface RasterizerOptions {
  cellZoom: number
  chunkZoom: number
}

/**
 * Proyecta un FeatureSet una sola vez y luego rasteriza todos los chunks que se
 * quieran a partir de él (normalmente los 64 chunks de un source tile).
 */
export class SourceRasterizer {
  readonly chunkSize: number
  readonly #ops: PaintOp[] = []
  readonly #points: ProjectedPoint[] = []
  readonly #cellZoom: number
  readonly #labels: LabelIndex

  constructor(set: FeatureSet, options: RasterizerOptions, referenceLatitude?: number) {
    this.#cellZoom = options.cellZoom
    this.#labels = new LabelIndex(set.features, options.cellZoom)
    this.chunkSize = 2 ** (options.cellZoom - options.chunkZoom)

    const lat = referenceLatitude ?? this.#guessLatitude(set.features)
    const metersPerCell = metersPerUnit(lat, options.cellZoom)

    for (const feature of set.features) this.#project(feature, metersPerCell)

    // Orden estable: prioridad, luego ancho (lo angosto debajo), luego id.
    this.#ops.sort(
      (a, b) =>
        a.paint.priority - b.paint.priority ||
        (a.paint.widthMeters ?? 0) - (b.paint.widthMeters ?? 0) ||
        (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
    )
    this.#points.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  }

  rasterizeChunk(z: number, x: number, y: number): ChunkGrid {
    const size = this.chunkSize
    const ox = x * size
    const oy = y * size
    const ground = new Uint8Array(size * size).fill(Ground.GRASS)
    const decor = new Uint8Array(size * size).fill(Decor.NONE)
    const props = new Uint8Array(size * size).fill(NO_PROP)

    for (const op of this.#ops) {
      if (op.maxX < ox || op.minX > ox + size || op.maxY < oy || op.minY > oy + size) continue
      if (op.fill) this.#fillArea(op, ox, oy, size, ground, decor)
      else this.#strokeLine(op, ox, oy, size, ground, decor)
    }

    // Árboles mapeados en OSM (solo sobre suelo natural).
    for (const p of this.#points) {
      if (p.tags.natural !== 'tree') continue
      const i = this.#localIndex(p.x, p.y, ox, oy, size)
      if (i < 0 || !isNaturalGround(ground[i])) continue
      props[i] = p.tags.leaf_type === 'needleleaved' ? Prop.PINE : Prop.TREE
    }

    // Decoración procedural determinista.
    for (let ly = 0; ly < size; ly++) {
      for (let lx = 0; lx < size; lx++) {
        const i = ly * size + lx
        if (props[i] !== NO_PROP || UNWALKABLE_GROUND.has(ground[i])) continue
        const prop = decorProp(decor[i] as DecorId, ground[i], ox + lx, oy + ly)
        if (prop !== NO_PROP) props[i] = prop
      }
    }

    const pois = this.#collectPois(ox, oy, size)
    const labels = this.#labels.forChunk(ox, oy, size, new Set(pois.map((p) => p.name)))
    return { z, x, y, size, ground, props, pois, labels }
  }

  // --- proyección ---

  #guessLatitude(features: Feature[]): number {
    for (const f of features) {
      if (f.kind === 'point') return f.coord[1]
      if (f.kind === 'line' && f.coords.length) return f.coords[0][1]
      if (f.kind === 'area' && f.rings[0]?.length) return f.rings[0][0][1]
    }
    return 0
  }

  #project(feature: Feature, metersPerCell: number) {
    const z = this.#cellZoom
    if (feature.kind === 'point') {
      this.#points.push({
        id: feature.id,
        tags: feature.tags,
        x: lonToWorld(feature.coord[0], z),
        y: latToWorld(feature.coord[1], z),
      })
      return
    }

    const paint = feature.kind === 'area' ? classifyArea(feature.tags) : classifyLine(feature.tags)
    if (!paint) return

    const polylines = feature.kind === 'area' ? feature.rings : [feature.coords]
    const values: number[] = []
    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity

    for (const line of polylines) {
      let px = Number.NaN
      let py = Number.NaN
      for (const [lon, lat] of line) {
        const cx = lonToWorld(lon, z)
        const cy = latToWorld(lat, z)
        if (!Number.isNaN(px)) values.push(px, py, cx, cy)
        px = cx
        py = cy
        if (cx < minX) minX = cx
        if (cx > maxX) maxX = cx
        if (cy < minY) minY = cy
        if (cy > maxY) maxY = cy
      }
    }
    if (values.length === 0) return

    // Semiancho mínimo 0.75 celdas: garantiza caminos 4-conexos (el pathfinding
    // no corta esquinas en diagonal) incluso para senderos angostos.
    const halfWidth =
      feature.kind === 'line' ? Math.max((paint.widthMeters ?? 0) / 2 / metersPerCell, 0.75) : 0

    this.#ops.push({
      id: feature.id,
      paint,
      segments: Float64Array.from(values),
      fill: feature.kind === 'area',
      halfWidth,
      minX: minX - halfWidth,
      minY: minY - halfWidth,
      maxX: maxX + halfWidth,
      maxY: maxY + halfWidth,
    })
  }

  // --- pintado ---

  /** Relleno scanline con regla par-impar sobre todos los segmentos del área. */
  #fillArea(
    op: PaintOp,
    ox: number,
    oy: number,
    size: number,
    ground: Uint8Array,
    decor: Uint8Array
  ) {
    const seg = op.segments
    const rowStart = Math.max(0, Math.floor(op.minY - oy))
    const rowEnd = Math.min(size - 1, Math.ceil(op.maxY - oy))
    const xs: number[] = []
    let painted = 0

    for (let row = rowStart; row <= rowEnd; row++) {
      const cy = oy + row + 0.5
      xs.length = 0
      for (let i = 0; i < seg.length; i += 4) {
        const y1 = seg[i + 1]
        const y2 = seg[i + 3]
        if (y1 <= cy !== y2 <= cy) {
          const x1 = seg[i]
          xs.push(x1 + ((cy - y1) * (seg[i + 2] - x1)) / (y2 - y1))
        }
      }
      if (xs.length < 2) continue
      xs.sort((a, b) => a - b)
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const start = Math.max(0, Math.ceil(xs[k] - ox - 0.5))
        const end = Math.min(size - 1, Math.ceil(xs[k + 1] - ox - 0.5) - 1)
        for (let col = start; col <= end; col++) {
          const i = row * size + col
          ground[i] = op.paint.ground
          decor[i] = op.paint.decor ?? Decor.NONE
          painted++
        }
      }
    }

    // Edificios más chicos que una celda: marcar la celda de su centro.
    if (painted === 0 && op.paint.keepSmall) {
      const i = this.#localIndex((op.minX + op.maxX) / 2, (op.minY + op.maxY) / 2, ox, oy, size)
      if (i >= 0) {
        ground[i] = op.paint.ground
        decor[i] = Decor.NONE
      }
    }
  }

  /** Pinta las celdas cuyo centro está a <= halfWidth de algún segmento. */
  #strokeLine(
    op: PaintOp,
    ox: number,
    oy: number,
    size: number,
    ground: Uint8Array,
    decor: Uint8Array
  ) {
    const seg = op.segments
    const hw = op.halfWidth
    const hw2 = hw * hw

    for (let i = 0; i < seg.length; i += 4) {
      const x1 = seg[i] - ox
      const y1 = seg[i + 1] - oy
      const x2 = seg[i + 2] - ox
      const y2 = seg[i + 3] - oy

      const c0 = Math.max(0, Math.floor(Math.min(x1, x2) - hw))
      const c1 = Math.min(size - 1, Math.ceil(Math.max(x1, x2) + hw))
      const r0 = Math.max(0, Math.floor(Math.min(y1, y2) - hw))
      const r1 = Math.min(size - 1, Math.ceil(Math.max(y1, y2) + hw))
      if (c0 > c1 || r0 > r1) continue

      const dx = x2 - x1
      const dy = y2 - y1
      const len2 = dx * dx + dy * dy

      for (let row = r0; row <= r1; row++) {
        for (let col = c0; col <= c1; col++) {
          const px = col + 0.5
          const py = row + 0.5
          let t = len2 > 0 ? ((px - x1) * dx + (py - y1) * dy) / len2 : 0
          t = t < 0 ? 0 : t > 1 ? 1 : t
          const ex = x1 + t * dx - px
          const ey = y1 + t * dy - py
          if (ex * ex + ey * ey <= hw2) {
            const idx = row * size + col
            ground[idx] = op.paint.ground
            decor[idx] = Decor.NONE
          }
        }
      }
    }
  }

  #localIndex(gx: number, gy: number, ox: number, oy: number, size: number): number {
    const lx = Math.floor(gx - ox)
    const ly = Math.floor(gy - oy)
    if (lx < 0 || ly < 0 || lx >= size || ly >= size) return -1
    return ly * size + lx
  }

  #collectPois(ox: number, oy: number, size: number): Poi[] {
    const pois: Poi[] = []
    for (const p of this.#points) {
      if (!p.tags.name) continue
      const key = POI_KEYS.find((k) => p.tags[k])
      if (!key) continue
      const i = this.#localIndex(p.x, p.y, ox, oy, size)
      if (i < 0) continue
      pois.push({
        id: p.id,
        kind: `${key}:${p.tags[key]}`,
        name: p.tags.name,
        cell: [i % size, Math.floor(i / size)],
      })
      if (pois.length >= MAX_POIS_PER_CHUNK) break
    }
    return pois
  }
}

function isNaturalGround(ground: number): boolean {
  return (
    ground === Ground.GRASS ||
    ground === Ground.GRASS_DARK ||
    ground === Ground.DIRT ||
    ground === Ground.SAND
  )
}

function decorProp(decor: DecorId, ground: number, gx: number, gy: number): number {
  const h = hash01(gx, gy, 1)
  switch (decor) {
    case Decor.FOREST:
      if (h < 0.22) return hash01(gx, gy, 2) < 0.35 ? Prop.PINE : Prop.TREE
      if (h < 0.26) return Prop.BUSH
      return NO_PROP
    case Decor.PARK:
      if (h < 0.035) return Prop.TREE
      if (h < 0.05) return Prop.BUSH
      return NO_PROP
    case Decor.WILD:
      if (h < 0.05) return Prop.BUSH
      if (h < 0.06) return Prop.ROCK
      return NO_PROP
    default:
      // Suelo por defecto sin datos (patios, terrenos): muy poca decoración.
      if (ground === Ground.GRASS && h < 0.004) return Prop.BUSH
      return NO_PROP
  }
}

/** Hash entero -> [0, 1). Determinista y estable entre versiones de Node. */
export function hash01(x: number, y: number, salt: number): number {
  let h = Math.imul(x ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(y ^ 0xc2b2ae35, 0x27d4eb2f)
  h ^= Math.imul(salt, 0x165667b1)
  h ^= h >>> 15
  h = Math.imul(h, 0x2c1b3c6d)
  h ^= h >>> 12
  h = Math.imul(h, 0x297a2d39)
  h ^= h >>> 15
  return (h >>> 0) / 4294967296
}

/** Latitud del centro de un tile (para calcular metros por celda). */
export function tileCenterLatitude(z: number, y: number): number {
  return worldToLat(y + 0.5, z)
}
