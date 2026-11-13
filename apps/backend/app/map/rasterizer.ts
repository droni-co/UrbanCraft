import { BUILDING_GROUNDS, Ground, NO_PROP, Prop, UNWALKABLE_GROUND } from '#map/catalog'
import type { Feature, FeatureSet, Tags } from '#map/features'
import { latToWorld, lonToWorld, metersPerUnit, worldToLat } from '#map/geo'
import { interiorPoint, LabelIndex, type MapLabel } from '#map/labels'
import { poiCategory, type PoiCategory } from '#map/poi_category'

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
  /** Etiqueta OSM principal: "amenity:restaurant", "shop:bakery"… */
  kind: string
  /** Categoría para el icono: food, shop, health… (ver poi_category.ts). */
  cat: PoiCategory
  name: string
  /** Detalle opcional (tipo de cocina…). */
  detail?: string
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
  /** size*size pisos del edificio de cada celda (0 = no es edificio). */
  levels: Uint8Array
  /** size*size techos: qué parte del tejado de su edificio cae en cada celda (ver roofByte). */
  roofs: Uint8Array
  pois: Poi[]
  /** Nombres de calles, áreas y números de portal (ver labels.ts). */
  labels: MapLabel[]
  /** Barrio en el que cae el chunk (punto de barrio más cercano), o null. */
  district: string | null
}

// --- Techos -------------------------------------------------------------------

/**
 * Byte de techo de una celda de edificio:
 *   bits 0-1: parte del tejado (RoofPart): plano, faldón bajo, faldón alto o cumbrera;
 *   bit 3:    la cumbrera corre a lo largo del eje y de la grilla (si no, del eje x);
 *   bits 4-5: tono del tejado (0-3), igual para todo el edificio.
 * Los tejados a dos aguas son de casas y edificios de ladrillo no muy anchos: la
 * cumbrera va por el lado largo del edificio y cada columna (o fila) se parte por
 * la mitad de su ancho real, así que las casas pegadas tienen cada una su tejado.
 */
export const RoofPart = { FLAT: 0, SLOPE_LOW: 1, SLOPE_HIGH: 2, RIDGE: 3 } as const
export const ROOF_AXIS_Y = 8
export const ROOF_TINT_SHIFT = 4
const PITCHED_GROUNDS: ReadonlySet<number> = new Set([Ground.BUILDING, Ground.ROOF_BRICK])
/** Más ancho que esto (en celdas, ~25 m) el tejado es plano. */
const MAX_PITCHED_SPAN = 12

export function roofByte(part: number, axisY: boolean, tint: number): number {
  return (part & 3) | (axisY ? ROOF_AXIS_Y : 0) | ((tint & 3) << ROOF_TINT_SHIFT)
}

/** Parte del tejado según la posición de la celda en el ancho [lo, hi] del edificio. */
export function roofPart(center: number, lo: number, hi: number): number {
  if (hi - lo > MAX_PITCHED_SPAN) return RoofPart.FLAT
  const d = center - (lo + hi) / 2
  if (Math.abs(d) < 0.5) return RoofPart.RIDGE
  return d < 0 ? RoofPart.SLOPE_LOW : RoofPart.SLOPE_HIGH
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
  /** Solo pinta sobre estos suelos (pasos de cebra: solo sobre el asfalto). */
  onlyOver?: readonly number[]
  /** Solo edificios: pisos (para dibujarlos en 3D isométrico). */
  levels?: number
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

const POI_KEYS = ['amenity', 'shop', 'tourism', 'leisure', 'historic', 'office', 'craft'] as const
const MAX_POIS_PER_CHUNK = 64
/** En áreas, solo locales y lugares (los parques ya tienen su etiqueta de área). */
const AREA_POI_KEYS = ['amenity', 'shop', 'tourism', 'historic', 'office', 'craft'] as const

/** Vías que en ciudad llevan andén a los lados (si no se mapeó aparte). */
const SIDEWALK_ROADS = new Set([
  'trunk',
  'primary',
  'secondary',
  'tertiary',
  'unclassified',
  'residential',
  'primary_link',
  'secondary_link',
  'tertiary_link',
])
const SIDEWALK_METERS = 2.5
/** Hasta dónde se busca el punto de barrio más cercano (ver LabelIndex.districtAt). */
const DISTRICT_REACH_METERS = 1500

const RAILWAY_WIDTHS: Record<string, number> = {
  rail: 3.5,
  light_rail: 3,
  tram: 2.5,
  narrow_gauge: 3,
  monorail: 2.5,
}

/** Separación de los árboles de una hilera (natural=tree_row), en metros. */
const TREE_ROW_SPACING = 7

// --- Edificios por tipo ------------------------------------------------------------

const CIVIC_BUILDINGS = new Set([
  'church',
  'cathedral',
  'chapel',
  'mosque',
  'temple',
  'synagogue',
  'shrine',
  'religious',
  'school',
  'university',
  'college',
  'kindergarten',
  'hospital',
  'public',
  'government',
  'civic',
  'museum',
  'train_station',
  'transportation',
  'fire_station',
  'townhall',
  'stadium',
])
const CIVIC_AMENITIES = new Set([
  'place_of_worship',
  'school',
  'university',
  'college',
  'hospital',
  'townhall',
  'library',
  'theatre',
  'courthouse',
  'police',
  'fire_station',
])
const INDUSTRIAL_BUILDINGS = new Set([
  'industrial',
  'warehouse',
  'factory',
  'manufacture',
  'hangar',
  'storage_tank',
  'garage',
  'garages',
  'service',
  'parking',
  'shed',
  'barn',
  'greenhouse',
])
const COMMERCIAL_BUILDINGS = new Set([
  'commercial',
  'retail',
  'office',
  'supermarket',
  'mall',
  'hotel',
  'kiosk',
])
const HOUSE_BUILDINGS = new Set([
  'house',
  'detached',
  'semidetached_house',
  'terrace',
  'bungalow',
  'farm',
  'cabin',
  'hut',
])

/**
 * Techo según el tipo de edificio, su altura y algo de azar estable (por id)
 * para que edificios vecinos no se fundan en un bloque del mismo color.
 */
export function classifyBuilding(tags: Tags, id: string): number {
  const type = tags.building
  const levels = mappedLevels(tags)
  const tall = levels !== null && levels >= 5
  const h = stringHash01(id)

  if (CIVIC_BUILDINGS.has(type) || CIVIC_AMENITIES.has(tags.amenity)) return Ground.ROOF_CIVIC
  if (INDUSTRIAL_BUILDINGS.has(type)) return Ground.ROOF_INDUSTRIAL
  if (COMMERCIAL_BUILDINGS.has(type) || tags.shop || tags.office) {
    return tall || h < 0.4 ? Ground.ROOF_DARK : Ground.ROOF_CONCRETE
  }
  if (type === 'apartments' || type === 'residential' || type === 'dormitory') {
    if (tall) return h < 0.6 ? Ground.ROOF_CONCRETE : Ground.ROOF_DARK
    return h < 0.7 ? Ground.ROOF_BRICK : Ground.ROOF_CONCRETE
  }
  if (HOUSE_BUILDINGS.has(type)) return h < 0.55 ? Ground.BUILDING : Ground.ROOF_BRICK
  // building=yes (lo más común): mezcla según la altura.
  if (tall) return h < 0.5 ? Ground.ROOF_CONCRETE : h < 0.8 ? Ground.ROOF_DARK : Ground.ROOF_BRICK
  if (h < 0.42) return Ground.BUILDING
  if (h < 0.8) return Ground.ROOF_BRICK
  return Ground.ROOF_CONCRETE
}

/** Pisos según OSM (`building:levels`, o `height` / 3 m), o null si no lo dice. */
export function mappedLevels(tags: Tags): number | null {
  const levels = Number.parseFloat(tags['building:levels'] ?? '')
  if (Number.isFinite(levels) && levels > 0) return Math.max(1, Math.round(levels))
  const height = Number.parseFloat(tags.height ?? '')
  if (Number.isFinite(height) && height > 0)
    return Math.max(1, Math.round(height / METERS_PER_LEVEL))
  return null
}

/**
 * Pisos de un edificio: los de OSM o, si no los tiene, unos típicos para su
 * tipo de techo (con algo de variación estable por edificio).
 */
export function buildingLevels(tags: Tags, ground: number, id: string): number {
  const mapped = mappedLevels(tags)
  if (mapped !== null) return Math.min(mapped, MAX_LEVELS)
  const h = stringHash01(id + ':levels')
  switch (ground) {
    case Ground.ROOF_INDUSTRIAL:
      return 1
    case Ground.ROOF_CIVIC:
      return 2
    case Ground.ROOF_CONCRETE:
      return h < 0.5 ? 3 : 4
    case Ground.ROOF_DARK:
      return h < 0.5 ? 5 : 6
    case Ground.ROOF_BRICK:
      return h < 0.6 ? 2 : 3
    default:
      return h < 0.35 ? 1 : 2
  }
}

const METERS_PER_LEVEL = 3
/** Tope (los pisos se guardan en un byte; el cliente además limita la altura dibujada). */
const MAX_LEVELS = 200

/** Andén a cada lado de una vía urbana (debajo del asfalto, encima del pasto). */
export function classifySidewalk(tags: Tags): Paint | null {
  const width = ROAD_WIDTHS[tags.highway]
  if (!width || !SIDEWALK_ROADS.has(tags.highway) || isHidden(tags)) return null
  // "separate": el andén está mapeado como su propia vía (ya se pinta).
  if (['no', 'none', 'separate'].includes(tags.sidewalk)) return null
  return {
    priority: 59,
    ground: Ground.PAVEMENT,
    widthMeters: width + SIDEWALK_METERS * 2,
    // No sobre el agua (puentes) ni sobre otras vías.
    onlyOver: [
      Ground.GRASS,
      Ground.GRASS_DARK,
      Ground.DIRT,
      Ground.SAND,
      Ground.STONE,
      Ground.PAVEMENT,
    ],
  }
}

function isHidden(tags: Tags): boolean {
  if (tags.tunnel && tags.tunnel !== 'no') return true
  if (tags.location === 'underground') return true
  const layer = Number(tags.layer)
  return Number.isFinite(layer) && layer < 0 && tags.bridge !== 'yes'
}

export function classifyArea(tags: Tags, id = ''): Paint | null {
  if (isHidden(tags)) return null

  if (tags.building && tags.building !== 'no' && tags.building !== 'roof') {
    const ground = classifyBuilding(tags, id)
    return { priority: 70, ground, keepSmall: true, levels: buildingLevels(tags, ground, id) }
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

  if (tags.railway && RAILWAY_WIDTHS[tags.railway]) {
    // Encima del asfalto: pasos a nivel y tranvías por la calle.
    return { priority: 62, ground: Ground.RAIL, widthMeters: RAILWAY_WIDTHS[tags.railway] }
  }

  const highway = tags.highway
  if (highway) {
    if (SKIPPED_HIGHWAYS.has(highway)) return null
    if (highway === 'footway' && tags.footway === 'crossing') {
      if (['unmarked', 'no'].includes(tags.crossing)) return null
      return { priority: 61, ground: Ground.CROSSWALK, widthMeters: 3, onlyOver: [Ground.ASPHALT] }
    }
    if (highway === 'cycleway') return { priority: 57, ground: Ground.CYCLEWAY, widthMeters: 2.5 }
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
  readonly #districtReach: number

  constructor(set: FeatureSet, options: RasterizerOptions, referenceLatitude?: number) {
    this.#cellZoom = options.cellZoom
    this.#labels = new LabelIndex(set.features, options.cellZoom)
    this.chunkSize = 2 ** (options.cellZoom - options.chunkZoom)

    const lat = referenceLatitude ?? this.#guessLatitude(set.features)
    const metersPerCell = metersPerUnit(lat, options.cellZoom)
    this.#districtReach = DISTRICT_REACH_METERS / metersPerCell

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
    const levels = new Uint8Array(size * size)
    const roofs = new Uint8Array(size * size)

    for (const op of this.#ops) {
      if (op.maxX < ox || op.minX > ox + size || op.maxY < oy || op.minY > oy + size) continue
      if (op.fill) this.#fillArea(op, ox, oy, size, ground, decor, levels, roofs)
      else this.#strokeLine(op, ox, oy, size, ground, decor)
    }
    // Lo que se pintó encima de un edificio (una vía, un puente) ya no es edificio.
    for (let i = 0; i < levels.length; i++) {
      if (!BUILDING_GROUNDS.has(ground[i])) {
        levels[i] = 0
        roofs[i] = 0
      }
    }

    // Pasos de cebra mapeados como nodo (lo más común): una mancha sobre el asfalto.
    for (const p of this.#points) {
      if (p.tags.highway !== 'crossing' || ['unmarked', 'no'].includes(p.tags.crossing)) continue
      this.#paintDisk(
        p.x,
        p.y,
        CROSSING_RADIUS,
        ox,
        oy,
        size,
        ground,
        Ground.CROSSWALK,
        Ground.ASPHALT
      )
    }

    // Árboles mapeados en OSM (solo sobre suelo natural o andén).
    for (const p of this.#points) {
      if (p.tags.natural !== 'tree') continue
      const i = this.#localIndex(p.x, p.y, ox, oy, size)
      if (i < 0 || !(isNaturalGround(ground[i]) || ground[i] === Ground.PAVEMENT)) continue
      props[i] = p.tags.leaf_type === 'needleleaved' ? Prop.PINE : Prop.TREE
    }

    // Mobiliario urbano: en su celda o en la libre más cercana fuera de la calzada
    // (los semáforos y paradas suelen estar mapeados sobre la vía).
    for (const p of this.#points) {
      const prop = furnitureProp(p.tags)
      if (prop === NO_PROP) continue
      const i = this.#nearestFree(
        p.x,
        p.y,
        ox,
        oy,
        size,
        ground,
        props,
        FURNITURE_SEARCH[prop] ?? 1
      )
      if (i >= 0) props[i] = prop
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

    const pois = this.#collectPois(ox, oy, size, ground, props)
    const labels = this.#labels.forChunk(ox, oy, size, new Set(pois.map((p) => p.name)))
    const half = size / 2
    const district = this.#labels.districtAt(ox + half, oy + half, this.#districtReach)
    return { z, x, y, size, ground, props, levels, roofs, pois, labels, district }
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

    const polylines = (feature.kind === 'area' ? feature.rings : [feature.coords]).map((line) => {
      const out = new Float64Array(line.length * 2)
      line.forEach(([lon, lat], i) => {
        out[i * 2] = lonToWorld(lon, z)
        out[i * 2 + 1] = latToWorld(lat, z)
      })
      return out
    })

    if (feature.kind === 'area') {
      this.#pushOp(
        feature.id,
        classifyArea(feature.tags, feature.id),
        polylines,
        true,
        metersPerCell
      )
      // Comercios y lugares mapeados como área (el local es el edificio): un POI
      // en un punto interior.
      if (feature.tags.name && AREA_POI_KEYS.some((k) => feature.tags[k])) {
        const rings = polylines.filter((r) => r.length >= 6)
        if (rings.length > 0) {
          const { x, y } = interiorPoint(rings)
          this.#points.push({ id: feature.id, tags: feature.tags, x, y })
        }
      }
      return
    }

    this.#pushOp(feature.id, classifyLine(feature.tags), polylines, false, metersPerCell)
    this.#pushOp(
      `${feature.id}:sidewalk`,
      classifySidewalk(feature.tags),
      polylines,
      false,
      metersPerCell
    )
    if (feature.tags.natural === 'tree_row') this.#treeRow(feature.id, polylines[0], metersPerCell)
  }

  #pushOp(
    id: string,
    paint: Paint | null,
    polylines: Float64Array[],
    fill: boolean,
    metersPerCell: number
  ) {
    if (!paint) return
    const values: number[] = []
    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity
    for (const line of polylines) {
      for (let i = 0; i < line.length; i += 2) {
        const cx = line[i]
        const cy = line[i + 1]
        if (i > 0) values.push(line[i - 2], line[i - 1], cx, cy)
        if (cx < minX) minX = cx
        if (cx > maxX) maxX = cx
        if (cy < minY) minY = cy
        if (cy > maxY) maxY = cy
      }
    }
    if (values.length === 0) return

    // Semiancho mínimo 0.75 celdas: garantiza caminos 4-conexos (el pathfinding
    // no corta esquinas en diagonal) incluso para senderos angostos.
    const halfWidth = fill ? 0 : Math.max((paint.widthMeters ?? 0) / 2 / metersPerCell, 0.75)

    this.#ops.push({
      id,
      paint,
      segments: Float64Array.from(values),
      fill,
      halfWidth,
      minX: minX - halfWidth,
      minY: minY - halfWidth,
      maxX: maxX + halfWidth,
      maxY: maxY + halfWidth,
    })
  }

  /** Hilera de árboles: un árbol cada TREE_ROW_SPACING metros a lo largo de la línea. */
  #treeRow(id: string, line: Float64Array, metersPerCell: number) {
    const step = TREE_ROW_SPACING / metersPerCell
    let carry = 0
    let n = 0
    for (let i = 2; i < line.length; i += 2) {
      const x1 = line[i - 2]
      const y1 = line[i - 1]
      const len = Math.hypot(line[i] - x1, line[i + 1] - y1)
      for (let d = carry; d <= len; d += step) {
        const t = len > 0 ? d / len : 0
        this.#points.push({
          id: `${id}:${n++}`,
          tags: { natural: 'tree' },
          x: x1 + (line[i] - x1) * t,
          y: y1 + (line[i + 1] - y1) * t,
        })
      }
      // Distancia al próximo árbol desde el inicio del siguiente tramo.
      carry = carry > len ? carry - len : step - ((len - carry) % step)
    }
  }

  // --- pintado ---

  /** Relleno scanline con regla par-impar sobre todos los segmentos del área. */
  #fillArea(
    op: PaintOp,
    ox: number,
    oy: number,
    size: number,
    ground: Uint8Array,
    decor: Uint8Array,
    levels: Uint8Array,
    roofs: Uint8Array
  ) {
    const seg = op.segments
    const level = op.paint.levels ?? 0
    const isBuilding = op.paint.levels !== undefined
    const pitched = isBuilding && PITCHED_GROUNDS.has(op.paint.ground)
    const tint = Math.floor(stringHash01(op.id + ':roof') * 4)
    // La cumbrera va por el lado largo; el ancho se mide en la otra dirección.
    const axisY = op.maxY - op.minY > op.maxX - op.minX
    const columnSpans = new Map<number, number[]>()
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
          if (op.paint.onlyOver && !op.paint.onlyOver.includes(ground[i])) continue
          ground[i] = op.paint.ground
          decor[i] = op.paint.decor ?? Decor.NONE
          levels[i] = level
          if (isBuilding) {
            let part: number = RoofPart.FLAT
            if (pitched && axisY) {
              part = roofPart(ox + col + 0.5, xs[k], xs[k + 1])
            } else if (pitched) {
              const gx = ox + col + 0.5
              let ys = columnSpans.get(col)
              if (!ys) {
                ys = crossings(seg, gx, true)
                columnSpans.set(col, ys)
              }
              const span = spanAround(ys, cy)
              if (span) part = roofPart(cy, span[0], span[1])
            }
            roofs[i] = roofByte(part, axisY, tint)
          }
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
        levels[i] = level
        roofs[i] = roofByte(pitched ? RoofPart.RIDGE : RoofPart.FLAT, axisY, tint)
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
            if (op.paint.onlyOver && !op.paint.onlyOver.includes(ground[idx])) continue
            ground[idx] = op.paint.ground
            decor[idx] = Decor.NONE
          }
        }
      }
    }
  }

  /** Pinta las celdas a <= radius del punto que tengan el suelo `over`. */
  #paintDisk(
    gx: number,
    gy: number,
    radius: number,
    ox: number,
    oy: number,
    size: number,
    ground: Uint8Array,
    paint: number,
    over: number
  ) {
    const r = Math.ceil(radius)
    const cx = Math.floor(gx - ox)
    const cy = Math.floor(gy - oy)
    for (let ly = cy - r; ly <= cy + r; ly++) {
      for (let lx = cx - r; lx <= cx + r; lx++) {
        if (lx < 0 || ly < 0 || lx >= size || ly >= size) continue
        const dx = lx + 0.5 - (gx - ox)
        const dy = ly + 0.5 - (gy - oy)
        const i = ly * size + lx
        if (dx * dx + dy * dy <= radius * radius && ground[i] === over) ground[i] = paint
      }
    }
  }

  /**
   * Celda libre más cercana (sin prop, transitable y fuera de la calzada) a
   * <= radius celdas del punto. -1 si no hay o si cae fuera del chunk: el
   * chunk vecino lo coloca (cada nodo cae en un solo chunk).
   */
  #nearestFree(
    gx: number,
    gy: number,
    ox: number,
    oy: number,
    size: number,
    ground: Uint8Array,
    props: Uint8Array,
    radius: number
  ): number {
    const home = this.#localIndex(gx, gy, ox, oy, size)
    if (home < 0) return -1
    const cx = home % size
    const cy = Math.floor(home / size)
    let best = -1
    let bestD = Infinity
    for (let ly = cy - radius; ly <= cy + radius; ly++) {
      for (let lx = cx - radius; lx <= cx + radius; lx++) {
        if (lx < 0 || ly < 0 || lx >= size || ly >= size) continue
        const i = ly * size + lx
        if (props[i] !== NO_PROP || !isSideGround(ground[i])) continue
        const d = (lx - cx) ** 2 + (ly - cy) ** 2
        if (d < bestD) {
          bestD = d
          best = i
        }
      }
    }
    return best
  }

  #localIndex(gx: number, gy: number, ox: number, oy: number, size: number): number {
    const lx = Math.floor(gx - ox)
    const ly = Math.floor(gy - oy)
    if (lx < 0 || ly < 0 || lx >= size || ly >= size) return -1
    return ly * size + lx
  }

  #collectPois(ox: number, oy: number, size: number, ground: Uint8Array, props: Uint8Array): Poi[] {
    const pois: Poi[] = []
    const taken = new Set<number>()
    for (const p of this.#points) {
      if (!p.tags.name) continue
      const key = POI_KEYS.find((k) => p.tags[k])
      if (!key) continue
      let i = this.#localIndex(p.x, p.y, ox, oy, size)
      if (i < 0) continue
      // Un local dentro de un edificio (ahora con paredes) se marca en la
      // puerta: la celda transitable más cercana, mejor al frente que detrás.
      if (UNWALKABLE_GROUND.has(ground[i]) || props[i] !== NO_PROP || taken.has(i)) {
        i = entranceCell(i, size, ground, props, taken)
      }
      taken.add(i)
      const poi: Poi = {
        id: p.id,
        kind: `${key}:${p.tags[key]}`,
        cat: poiCategory(p.tags),
        name: p.tags.name,
        cell: [i % size, Math.floor(i / size)],
      }
      if (p.tags.cuisine) poi.detail = p.tags.cuisine.split(';')[0].replaceAll('_', ' ')
      pois.push(poi)
    }
    // Si hay demasiados, primero los más llamativos (comida, cultura…).
    pois.sort((a, b) => POI_PRIORITY[b.cat] - POI_PRIORITY[a.cat] || (a.id < b.id ? -1 : 1))
    return pois.slice(0, MAX_POIS_PER_CHUNK)
  }
}

const CROSSING_RADIUS = 1.6
/** Hasta dónde (celdas) se busca la entrada de un local que cae dentro de un edificio. */
const ENTRANCE_SEARCH = 12

/**
 * Celda libre (transitable y sin prop) más cercana a `home`, prefiriendo las de
 * delante (abajo en pantalla), que no quedan tapadas por el edificio. Si no
 * hay ninguna cerca, `home`.
 */
function entranceCell(
  home: number,
  size: number,
  ground: Uint8Array,
  props: Uint8Array,
  taken: Set<number>
): number {
  const cx = home % size
  const cy = Math.floor(home / size)
  let best = home
  let bestCost = Infinity
  for (let ly = cy - ENTRANCE_SEARCH; ly <= cy + ENTRANCE_SEARCH; ly++) {
    for (let lx = cx - ENTRANCE_SEARCH; lx <= cx + ENTRANCE_SEARCH; lx++) {
      if (lx < 0 || ly < 0 || lx >= size || ly >= size) continue
      const i = ly * size + lx
      if (UNWALKABLE_GROUND.has(ground[i]) || props[i] !== NO_PROP || taken.has(i)) continue
      const dx = lx - cx
      const dy = ly - cy
      const cost = dx * dx + dy * dy + (dx + dy < 0 ? 4 : 0)
      if (cost < bestCost) {
        bestCost = cost
        best = i
      }
    }
  }
  return best
}

/** Cuánto (celdas) se puede alejar cada mueble de su nodo para no quedar en la calzada. */
const FURNITURE_SEARCH: Partial<Record<number, number>> = {
  [Prop.TRAFFIC_LIGHT]: 5,
  [Prop.BUS_STOP]: 4,
  [Prop.STREET_LAMP]: 3,
}

const POI_PRIORITY: Record<PoiCategory, number> = {
  culture: 9,
  food: 8,
  worship: 7,
  lodging: 6,
  shop: 6,
  health: 5,
  education: 5,
  money: 4,
  sport: 4,
  transport: 4,
  service: 3,
  other: 1,
}

/**
 * Cortes de un polígono (segmentos [x1, y1, x2, y2, ...]) con la recta vertical
 * x = at (`vertical`) u horizontal y = at, ordenados.
 */
export function crossings(seg: Float64Array, at: number, vertical: boolean): number[] {
  const out: number[] = []
  const a = vertical ? 0 : 1
  const b = vertical ? 1 : 0
  for (let i = 0; i < seg.length; i += 4) {
    const p1 = seg[i + a]
    const p2 = seg[i + 2 + a]
    if (p1 <= at !== p2 <= at) {
      const q1 = seg[i + b]
      out.push(q1 + ((at - p1) * (seg[i + 2 + b] - q1)) / (p2 - p1))
    }
  }
  return out.sort((x, y) => x - y)
}

/** El tramo [lo, hi] de los cortes (par-impar) que contiene a `pos`, o null. */
export function spanAround(cuts: number[], pos: number): [number, number] | null {
  for (let k = 0; k + 1 < cuts.length; k += 2) {
    if (cuts[k] <= pos && pos <= cuts[k + 1]) return [cuts[k], cuts[k + 1]]
  }
  return null
}

export function furnitureProp(tags: Tags): number {
  if (tags.amenity === 'bench') return Prop.BENCH
  if (tags.highway === 'street_lamp') return Prop.STREET_LAMP
  if (tags.highway === 'traffic_signals') return Prop.TRAFFIC_LIGHT
  if (tags.highway === 'bus_stop') return Prop.BUS_STOP
  if (tags.amenity === 'fountain') return Prop.FOUNTAIN
  if (['memorial', 'monument', 'statue'].includes(tags.historic) || tags.tourism === 'artwork') {
    return Prop.STATUE
  }
  return NO_PROP
}

/** Suelo donde puede ir un mueble: transitable y que no sea calzada ni vía. */
function isSideGround(ground: number): boolean {
  return (
    !UNWALKABLE_GROUND.has(ground) &&
    ground !== Ground.ASPHALT &&
    ground !== Ground.CROSSWALK &&
    ground !== Ground.RAIL &&
    ground !== Ground.CYCLEWAY
  )
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

/** Hash de un texto (id OSM) -> [0, 1). FNV-1a, determinista. */
export function stringHash01(text: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return hash01(h, text.length, 7)
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
