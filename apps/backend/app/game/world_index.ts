import { decodeChunk } from '#map/chunk_codec'
import { NO_PROP, PROP_NAMES, UNWALKABLE_GROUND, Ground } from '#map/catalog'
import { MapRepository } from '#map/map_repository'
import type { PoiCategory } from '#map/poi_category'

/** Un lugar del mapa (punto de interés de OSM) con su celda global. */
export interface WorldPoi {
  id: string
  kind: string
  cat: PoiCategory
  name: string
  /** Celda global. */
  x: number
  y: number
  /** Chunk al que pertenece. */
  cx: number
  cy: number
}

/** Cómo identifica el cliente un lugar: su id de OSM y el chunk donde está. */
export interface PoiRef {
  id: string
  cx: number
  cy: number
}

interface ChunkInfo {
  size: number
  ground: Buffer
  props: Buffer
  pois: WorldPoi[]
}

/** Suelo donde no se dejan objetos: por ahí pasa la gente (y los carros). */
const NO_BUILD_GROUND: ReadonlySet<number> = new Set([
  Ground.ASPHALT,
  Ground.CROSSWALK,
  Ground.RAIL,
  Ground.CYCLEWAY,
])

const MISSING_TTL_MS = 30_000

/**
 * Lo que el servidor sabe del mapa ya generado: qué lugares hay, qué suelo y
 * qué prop tiene cada celda. Sirve para validar las acciones del juego (¿hay
 * de verdad una panadería ahí?, ¿eso es un árbol?) sin fiarse del cliente.
 *
 * Lee los chunks guardados (map_chunks) y los mantiene decodificados en
 * memoria (LRU). Un chunk que aún no existe se vuelve a consultar al rato.
 */
export class WorldIndex {
  #cache = new Map<string, { info: ChunkInfo | null; at: number }>()

  constructor(
    private config: { chunkZoom: number; cellZoom: number; generatorVersion: number },
    private repository = new MapRepository(),
    private maxChunks = 400
  ) {}

  /** Lado de un chunk, en celdas. */
  get chunkCells() {
    return 2 ** (this.config.cellZoom - this.config.chunkZoom)
  }

  get cellZoom() {
    return this.config.cellZoom
  }

  chunkOf(x: number, y: number): [number, number] {
    return [Math.floor(x / this.chunkCells), Math.floor(y / this.chunkCells)]
  }

  async poi(ref: PoiRef): Promise<WorldPoi | null> {
    const chunk = await this.#chunk(ref.cx, ref.cy)
    return chunk?.pois.find((p) => p.id === ref.id) ?? null
  }

  /** Lugares de los chunks ya generados a `radiusChunks` del chunk de (x, y). */
  async poisAround(x: number, y: number, radiusChunks: number): Promise<WorldPoi[]> {
    const [cx, cy] = this.chunkOf(x, y)
    const jobs: Promise<ChunkInfo | null>[] = []
    for (let dy = -radiusChunks; dy <= radiusChunks; dy++) {
      for (let dx = -radiusChunks; dx <= radiusChunks; dx++)
        jobs.push(this.#chunk(cx + dx, cy + dy))
    }
    const chunks = await Promise.all(jobs)
    return chunks.flatMap((chunk) => chunk?.pois ?? [])
  }

  /** Suelo y prop de una celda global, o null si esa zona no está generada. */
  async cell(x: number, y: number) {
    const [cx, cy] = this.chunkOf(x, y)
    const chunk = await this.#chunk(cx, cy)
    if (!chunk) return null
    const index = (y - cy * chunk.size) * chunk.size + (x - cx * chunk.size)
    const prop = chunk.props[index]
    const ground = chunk.ground[index]
    return {
      ground,
      prop: prop === NO_PROP ? null : (PROP_NAMES[prop] ?? null),
      walkable: !UNWALKABLE_GROUND.has(ground),
      buildable: !UNWALKABLE_GROUND.has(ground) && !NO_BUILD_GROUND.has(ground) && prop === NO_PROP,
    }
  }

  /** Olvida lo que hay en memoria (pruebas, o tras regenerar el mapa). */
  clear() {
    this.#cache.clear()
  }

  async #chunk(cx: number, cy: number): Promise<ChunkInfo | null> {
    const key = `${cx},${cy}`
    const cached = this.#cache.get(key)
    if (cached && (cached.info || Date.now() - cached.at < MISSING_TTL_MS)) {
      // LRU: lo usado pasa al final.
      this.#cache.delete(key)
      this.#cache.set(key, cached)
      return cached.info
    }
    const row = await this.repository.findChunk(
      this.config.chunkZoom,
      cx,
      cy,
      this.config.generatorVersion
    )
    let info: ChunkInfo | null = null
    if (row) {
      const payload = decodeChunk(row.data)
      info = {
        size: payload.size,
        ground: Buffer.from(payload.ground, 'base64'),
        props: Buffer.from(payload.props, 'base64'),
        pois: payload.pois.map((p) => ({
          id: p.id,
          kind: p.kind,
          cat: p.cat,
          name: p.name,
          x: cx * payload.size + p.cell[0],
          y: cy * payload.size + p.cell[1],
          cx,
          cy,
        })),
      }
    }
    this.#cache.set(key, { info, at: Date.now() })
    if (this.#cache.size > this.maxChunks) {
      this.#cache.delete(this.#cache.keys().next().value!)
    }
    return info
  }
}
