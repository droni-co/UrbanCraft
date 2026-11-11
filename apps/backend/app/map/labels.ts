import type { Feature, Tags } from '#map/features'
import { latToWorld, lonToWorld, type LonLat } from '#map/geo'

/**
 * Etiquetas del mapa (nombres de calles, parques, edificios, números de portal).
 *
 * Se calculan en el servidor, una vez por chunk, para que el cliente solo tenga
 * que dibujarlas:
 *   - Calles y ríos: el tramo recto más largo dentro del chunk (ancla + ángulo
 *     en la grilla) y los trozos de su trazado recortados al chunk, para que el
 *     cliente sepa en qué calle está el jugador.
 *   - Áreas (parques, agua, plazas, edificios con nombre): un punto interior.
 *     Solo la emite el chunk que contiene ese punto (una vez por área).
 *   - Números de portal (addr:housenumber) en nodos y edificios.
 *
 * Coordenadas: celdas locales del chunk con decimales (0..size).
 */

export type LabelKind =
  'street' | 'path' | 'waterway' | 'park' | 'water' | 'square' | 'building' | 'place' | 'number'

export interface MapLabel {
  /** Id OSM estable (para calles: el menor id de las vías con ese nombre). */
  id: string
  kind: LabelKind
  name: string
  /** Importancia 1..9 (más alto = se muestra antes y de más lejos). */
  rank: number
  /** Ancla del texto en celdas locales del chunk. */
  at: [number, number]
  /** Solo líneas: dirección del texto en la grilla (radianes, x este / y sur). */
  angle?: number
  /** Solo líneas: largo del tramo recto donde va el texto (celdas). */
  len?: number
  /** Solo líneas: trazado recortado al chunk, [x0, y0, x1, y1, ...] por trozo. */
  paths?: number[][]
}

const STREET_RANKS: Record<string, number> = {
  motorway: 9,
  trunk: 9,
  primary: 8,
  secondary: 7,
  tertiary: 6,
  motorway_link: 5,
  trunk_link: 5,
  primary_link: 5,
  secondary_link: 5,
  tertiary_link: 5,
  unclassified: 5,
  residential: 5,
  living_street: 5,
  busway: 5,
  road: 5,
  pedestrian: 4,
  service: 3,
}
const PATH_HIGHWAYS = new Set(['footway', 'cycleway', 'path', 'steps', 'bridleway', 'track'])
const WATERWAYS = new Set(['river', 'canal', 'stream'])

const MAX_LINE_LABELS = 24
const MAX_AREA_LABELS = 32
const MAX_NUMBERS = 160
/** Desvío máximo para considerar que un tramo sigue "recto" (para poner texto). */
const STRAIGHT_TOLERANCE = (15 * Math.PI) / 180
/** Áreas más grandes que esto (celdas²) suben de importancia. */
const LARGE_AREA = 2500

interface LineSource {
  id: string
  kind: LabelKind
  name: string
  rank: number
  /** Polilíneas en celdas globales. */
  lines: Float64Array[]
  minX: number
  minY: number
  maxX: number
  maxY: number
}

interface PointSource {
  id: string
  kind: LabelKind
  name: string
  rank: number
  x: number
  y: number
}

export function classifyLineLabel(tags: Tags): { kind: LabelKind; rank: number } | null {
  if (!tags.name) return null
  if (tags.tunnel && tags.tunnel !== 'no') return null
  const highway = tags.highway
  if (highway) {
    if (STREET_RANKS[highway]) return { kind: 'street', rank: STREET_RANKS[highway] }
    if (PATH_HIGHWAYS.has(highway)) return { kind: 'path', rank: 2 }
    return null
  }
  if (tags.waterway && WATERWAYS.has(tags.waterway)) {
    return { kind: 'waterway', rank: tags.waterway === 'stream' ? 3 : 6 }
  }
  return null
}

export function classifyAreaLabel(tags: Tags): { kind: LabelKind; rank: number } | null {
  if (!tags.name) return null
  if (tags.building && tags.building !== 'no') {
    const notable = tags.amenity || tags.tourism || tags.historic || tags.leisure
    return notable ? { kind: 'place', rank: 4 } : { kind: 'building', rank: 3 }
  }
  if (
    tags.natural === 'water' ||
    tags.waterway === 'riverbank' ||
    tags.landuse === 'reservoir' ||
    tags.landuse === 'basin'
  ) {
    return { kind: 'water', rank: 5 }
  }
  if (
    tags.place === 'square' ||
    tags.highway === 'pedestrian' ||
    tags['area:highway'] === 'pedestrian'
  ) {
    return { kind: 'square', rank: 5 }
  }
  if (
    ['park', 'garden', 'nature_reserve', 'dog_park'].includes(tags.leisure) ||
    tags.natural === 'wood' ||
    tags.landuse === 'forest' ||
    tags.landuse === 'cemetery'
  ) {
    return { kind: 'park', rank: 4 }
  }
  if (tags.leisure || tags.amenity || tags.tourism || tags.historic) {
    return { kind: 'place', rank: 3 }
  }
  return null
}

const round1 = (n: number) => Math.round(n * 10) / 10
const round3 = (n: number) => Math.round(n * 1000) / 1000
const byId = (a: { id: string }, b: { id: string }) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)

export class LabelIndex {
  readonly #lines: LineSource[] = []
  readonly #areas: PointSource[] = []
  readonly #numbers: PointSource[] = []

  constructor(
    features: Feature[],
    private cellZoom: number
  ) {
    for (const feature of features) this.#add(feature)
    this.#lines.sort(byId)
    this.#areas.sort(byId)
    this.#numbers.sort(byId)
  }

  /** Etiquetas de un chunk (ox, oy = celda global de su esquina). */
  forChunk(ox: number, oy: number, size: number, poiNames: Set<string>): MapLabel[] {
    return [
      ...this.#lineLabels(ox, oy, size),
      ...this.#pointLabels(this.#areas, ox, oy, size, MAX_AREA_LABELS, poiNames),
      ...this.#numberLabels(ox, oy, size),
    ]
  }

  // --- construcción ---

  #project(coords: LonLat[]): Float64Array {
    const out = new Float64Array(coords.length * 2)
    coords.forEach(([lon, lat], i) => {
      out[i * 2] = lonToWorld(lon, this.cellZoom)
      out[i * 2 + 1] = latToWorld(lat, this.cellZoom)
    })
    return out
  }

  #add(feature: Feature) {
    const housenumber = feature.tags['addr:housenumber']

    if (feature.kind === 'point') {
      // Un nodo con nombre y categoría ya es un POI (tiene su propio marcador).
      if (!housenumber || feature.tags.name) return
      this.#numbers.push({
        id: feature.id,
        kind: 'number',
        name: housenumber,
        rank: 1,
        x: lonToWorld(feature.coord[0], this.cellZoom),
        y: latToWorld(feature.coord[1], this.cellZoom),
      })
      return
    }

    if (feature.kind === 'line') {
      const cls = classifyLineLabel(feature.tags)
      if (!cls || feature.coords.length < 2) return
      const line = this.#project(feature.coords)
      const [minX, minY, maxX, maxY] = bounds([line])
      this.#lines.push({
        id: feature.id,
        ...cls,
        name: feature.tags.name,
        lines: [line],
        minX,
        minY,
        maxX,
        maxY,
      })
      return
    }

    const cls = classifyAreaLabel(feature.tags)
    if (!cls && !housenumber) return
    const rings = feature.rings.filter((r) => r.length >= 3).map((r) => this.#project(r))
    if (rings.length === 0) return
    const { x, y, area } = interiorPoint(rings)

    if (cls) {
      const rank = cls.rank + (area > LARGE_AREA ? 2 : 0)
      this.#areas.push({ id: feature.id, ...cls, rank, name: feature.tags.name, x, y })
    }
    if (housenumber && feature.tags.building) {
      this.#numbers.push({ id: feature.id, kind: 'number', name: housenumber, rank: 1, x, y })
    }
  }

  // --- por chunk ---

  #lineLabels(ox: number, oy: number, size: number): MapLabel[] {
    const x1 = ox + size
    const y1 = oy + size
    // Agrupa por nombre: una calle suele estar partida en varias vías OSM.
    const groups = new Map<string, { source: LineSource; pieces: Float64Array[] }>()

    for (const src of this.#lines) {
      if (src.maxX < ox || src.minX > x1 || src.maxY < oy || src.minY > y1) continue
      const pieces = src.lines.flatMap((l) => clipPolyline(l, ox, oy, x1, y1))
      if (pieces.length === 0) continue
      const key = `${src.kind}|${src.name}`
      const group = groups.get(key)
      if (group) {
        group.pieces.push(...pieces)
        if (src.rank > group.source.rank) group.source = { ...src, id: group.source.id }
      } else {
        groups.set(key, { source: src, pieces })
      }
    }

    const labels: MapLabel[] = []
    for (const { source, pieces } of groups.values()) {
      let best: StraightRun | null = null
      for (const piece of pieces) {
        const run = longestStraightRun(piece)
        if (run && (!best || run.length > best.length)) best = run
      }
      if (!best) continue
      labels.push({
        id: source.id,
        kind: source.kind,
        name: source.name,
        rank: source.rank,
        at: [round1(best.x - ox), round1(best.y - oy)],
        angle: round3(best.angle),
        len: round1(best.length),
        paths: pieces.map((p) => Array.from(p, (v, i) => round1(v - (i % 2 === 0 ? ox : oy)))),
      })
    }
    labels.sort((a, b) => b.rank - a.rank || (b.len ?? 0) - (a.len ?? 0) || byId(a, b))
    return labels.slice(0, MAX_LINE_LABELS)
  }

  #pointLabels(
    sources: PointSource[],
    ox: number,
    oy: number,
    size: number,
    max: number,
    skipNames: Set<string>
  ): MapLabel[] {
    const labels: MapLabel[] = []
    for (const s of sources) {
      if (s.x < ox || s.y < oy || s.x >= ox + size || s.y >= oy + size) continue
      // Si un POI del chunk ya tiene ese nombre (p. ej. el museo y su edificio), no repetir.
      if (skipNames.has(s.name)) continue
      labels.push({
        id: s.id,
        kind: s.kind,
        name: s.name,
        rank: s.rank,
        at: [round1(s.x - ox), round1(s.y - oy)],
      })
    }
    labels.sort((a, b) => b.rank - a.rank || byId(a, b))
    return labels.slice(0, max)
  }

  #numberLabels(ox: number, oy: number, size: number): MapLabel[] {
    const labels = this.#pointLabels(this.#numbers, ox, oy, size, Infinity, new Set())
    // El mismo número mapeado en el edificio y en su portal: quedarse con uno.
    const kept: MapLabel[] = []
    for (const label of labels) {
      const duplicate = kept.some(
        (k) =>
          k.name === label.name &&
          Math.abs(k.at[0] - label.at[0]) < 4 &&
          Math.abs(k.at[1] - label.at[1]) < 4
      )
      if (!duplicate) kept.push(label)
      if (kept.length >= MAX_NUMBERS) break
    }
    return kept
  }
}

// --- Geometría -------------------------------------------------------------------

function bounds(lines: Float64Array[]): [number, number, number, number] {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const l of lines) {
    for (let i = 0; i < l.length; i += 2) {
      minX = Math.min(minX, l[i])
      maxX = Math.max(maxX, l[i])
      minY = Math.min(minY, l[i + 1])
      maxY = Math.max(maxY, l[i + 1])
    }
  }
  return [minX, minY, maxX, maxY]
}

/** Recorta un segmento a un rectángulo (Liang-Barsky). Devuelve [t0, t1] o null. */
function clipSegment(
  ax: number,
  ay: number,
  bx: number,
  by: number,
  x0: number,
  y0: number,
  x1: number,
  y1: number
): [number, number] | null {
  const dx = bx - ax
  const dy = by - ay
  let t0 = 0
  let t1 = 1
  const edges: Array<[number, number]> = [
    [-dx, ax - x0],
    [dx, x1 - ax],
    [-dy, ay - y0],
    [dy, y1 - ay],
  ]
  for (const [p, q] of edges) {
    if (p === 0) {
      if (q < 0) return null
      continue
    }
    const t = q / p
    if (p < 0) {
      if (t > t1) return null
      if (t > t0) t0 = t
    } else {
      if (t < t0) return null
      if (t < t1) t1 = t
    }
  }
  return t1 - t0 > 1e-9 ? [t0, t1] : null
}

/** Recorta una polilínea a un rectángulo; devuelve los trozos continuos. */
export function clipPolyline(
  line: Float64Array,
  x0: number,
  y0: number,
  x1: number,
  y1: number
): Float64Array[] {
  const pieces: Float64Array[] = []
  let current: number[] = []
  for (let i = 0; i + 3 < line.length; i += 2) {
    const ax = line[i]
    const ay = line[i + 1]
    const bx = line[i + 2]
    const by = line[i + 3]
    const clip = clipSegment(ax, ay, bx, by, x0, y0, x1, y1)
    if (!clip) {
      if (current.length >= 4) pieces.push(Float64Array.from(current))
      current = []
      continue
    }
    const [t0, t1] = clip
    if (t0 > 0 && current.length > 0) {
      pieces.push(Float64Array.from(current))
      current = []
    }
    if (current.length === 0) current.push(ax + (bx - ax) * t0, ay + (by - ay) * t0)
    current.push(ax + (bx - ax) * t1, ay + (by - ay) * t1)
    if (t1 < 1) {
      pieces.push(Float64Array.from(current))
      current = []
    }
  }
  if (current.length >= 4) pieces.push(Float64Array.from(current))
  return pieces
}

interface StraightRun {
  /** Punto medio (a lo largo del tramo). */
  x: number
  y: number
  angle: number
  length: number
}

/** Tramo casi recto más largo de una polilínea: donde cabe mejor un texto. */
export function longestStraightRun(line: Float64Array): StraightRun | null {
  const n = line.length / 2
  let best: StraightRun | null = null
  let start = 0
  while (start < n - 1) {
    const baseAngle = Math.atan2(
      line[start * 2 + 3] - line[start * 2 + 1],
      line[start * 2 + 2] - line[start * 2]
    )
    let end = start + 1
    let length = Math.hypot(
      line[end * 2] - line[start * 2],
      line[end * 2 + 1] - line[start * 2 + 1]
    )
    while (end < n - 1) {
      const a = Math.atan2(line[end * 2 + 3] - line[end * 2 + 1], line[end * 2 + 2] - line[end * 2])
      if (Math.abs(angleDiff(a, baseAngle)) > STRAIGHT_TOLERANCE) break
      length += Math.hypot(line[end * 2 + 2] - line[end * 2], line[end * 2 + 3] - line[end * 2 + 1])
      end++
    }
    if (length > 0 && (!best || length > best.length)) {
      const mid = pointAlong(line, start, end, length / 2)
      const angle = Math.atan2(
        line[end * 2 + 1] - line[start * 2 + 1],
        line[end * 2] - line[start * 2]
      )
      best = { x: mid[0], y: mid[1], angle, length }
    }
    start = end
  }
  return best
}

function angleDiff(a: number, b: number): number {
  let d = a - b
  while (d > Math.PI) d -= 2 * Math.PI
  while (d < -Math.PI) d += 2 * Math.PI
  return d
}

function pointAlong(
  line: Float64Array,
  from: number,
  to: number,
  distance: number
): [number, number] {
  let left = distance
  for (let i = from; i < to; i++) {
    const ax = line[i * 2]
    const ay = line[i * 2 + 1]
    const bx = line[i * 2 + 2]
    const by = line[i * 2 + 3]
    const seg = Math.hypot(bx - ax, by - ay)
    if (seg >= left && seg > 0)
      return [ax + ((bx - ax) * left) / seg, ay + ((by - ay) * left) / seg]
    left -= seg
  }
  return [line[to * 2], line[to * 2 + 1]]
}

function ringArea(ring: Float64Array): { area: number; cx: number; cy: number } {
  let a = 0
  let cx = 0
  let cy = 0
  const n = ring.length / 2
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n
    const x0 = ring[i * 2]
    const y0 = ring[i * 2 + 1]
    const x1 = ring[j * 2]
    const y1 = ring[j * 2 + 1]
    const cross = x0 * y1 - x1 * y0
    a += cross
    cx += (x0 + x1) * cross
    cy += (y0 + y1) * cross
  }
  a /= 2
  if (Math.abs(a) < 1e-9) {
    let sx = 0
    let sy = 0
    for (let i = 0; i < n; i++) {
      sx += ring[i * 2]
      sy += ring[i * 2 + 1]
    }
    return { area: 0, cx: sx / n, cy: sy / n }
  }
  return { area: Math.abs(a), cx: cx / (6 * a), cy: cy / (6 * a) }
}

function insideEvenOdd(rings: Float64Array[], x: number, y: number): boolean {
  let inside = false
  for (const r of rings) {
    const n = r.length / 2
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const xi = r[i * 2]
      const yi = r[i * 2 + 1]
      const xj = r[j * 2]
      const yj = r[j * 2 + 1]
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside
    }
  }
  return inside
}

/**
 * Punto dentro de un área (para el texto): centroide del anillo más grande o,
 * si cae fuera (formas en L o con patio), el centro del tramo interior más
 * ancho en la horizontal del centroide.
 */
export function interiorPoint(rings: Float64Array[]): { x: number; y: number; area: number } {
  let biggest = ringArea(rings[0])
  for (const r of rings.slice(1)) {
    const candidate = ringArea(r)
    if (candidate.area > biggest.area) biggest = candidate
  }
  const { cx, cy, area } = biggest
  if (area === 0 || insideEvenOdd(rings, cx, cy)) return { x: cx, y: cy, area }

  const xs: number[] = []
  for (const r of rings) {
    const n = r.length / 2
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const yi = r[i * 2 + 1]
      const yj = r[j * 2 + 1]
      if (yi > cy !== yj > cy) {
        xs.push(r[i * 2] + ((cy - yi) * (r[j * 2] - r[i * 2])) / (yj - yi))
      }
    }
  }
  xs.sort((a, b) => a - b)
  let bestX = cx
  let bestWidth = -1
  for (let k = 0; k + 1 < xs.length; k += 2) {
    if (xs[k + 1] - xs[k] > bestWidth) {
      bestWidth = xs[k + 1] - xs[k]
      bestX = (xs[k] + xs[k + 1]) / 2
    }
  }
  return { x: bestX, y: cy, area }
}
