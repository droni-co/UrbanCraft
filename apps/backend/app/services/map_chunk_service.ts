import app from '@adonisjs/core/services/app'
import logger from '@adonisjs/core/services/logger'
import type { MapConfig } from '#config/map'
import { encodeChunk } from '#map/chunk_codec'
import { decodeFeatureSet, encodeFeatureSet, type FeatureSet } from '#map/features'
import { childTiles, expandBBox, parentTile, tileBounds, isValidTile, tilesAround } from '#map/geo'
import { MapRepository, type ClaimedJob, type ChunkRow } from '#map/map_repository'
import { OsmProvider, OsmProviderError } from '#map/providers/osm_provider'
import { SourceRasterizer, tileCenterLatitude } from '#map/rasterizer'

export type ChunkResult =
  | { state: 'ready'; chunk: ChunkRow }
  | { state: 'pending'; retryAfterSeconds: number }
  | { state: 'failed'; error: string | null }
  | { state: 'throttled'; retryAfterSeconds: number }

/**
 * Orquesta la obtención de chunks:
 *   1. caché en memoria (LRU) -> 2. tabla map_chunks -> 3. encolar source tile
 * y el procesamiento de la cola (lo invoca MapWorker).
 */
export class MapChunkService {
  readonly config: MapConfig
  readonly repo = new MapRepository()
  readonly #memory = new Map<string, ChunkRow>()
  readonly #enqueuesByIp = new Map<string, number[]>()
  #onEnqueue: (() => void) | null = null

  constructor(config: MapConfig) {
    this.config = config
  }

  /** El worker se suscribe para despertar apenas haya trabajo nuevo. */
  onEnqueue(callback: () => void) {
    this.#onEnqueue = callback
  }

  isValidChunk(z: number, x: number, y: number): boolean {
    return z === this.config.chunkZoom && isValidTile(z, x, y)
  }

  sourceTileOf(x: number, y: number): [number, number] {
    return parentTile(this.config.chunkZoom, x, y, this.config.sourceZoom)
  }

  async getChunk(z: number, x: number, y: number, clientIp: string): Promise<ChunkResult> {
    const version = this.config.generatorVersion
    const key = `${z}/${x}/${y}/${version}`

    const cached = this.#memory.get(key)
    if (cached) {
      this.#touch(key, cached)
      return { state: 'ready', chunk: cached }
    }

    const stored = await this.repo.findChunk(z, x, y, version)
    if (stored) {
      this.#touch(key, stored)
      return { state: 'ready', chunk: stored }
    }

    const [sx, sy] = this.sourceTileOf(x, y)
    const sz = this.config.sourceZoom
    const tile = await this.repo.findSourceTile(sz, sx, sy)

    if (!tile) {
      if (!this.#allowEnqueue(clientIp)) return { state: 'throttled', retryAfterSeconds: 60 }
      if ((await this.repo.countQueued()) >= this.config.limits.maxQueuedSourceTiles) {
        return { state: 'throttled', retryAfterSeconds: 30 }
      }
      await this.repo.enqueueSourceTile(sz, sx, sy, tileBounds(sz, sx, sy))
      this.#onEnqueue?.()
      return { state: 'pending', retryAfterSeconds: 5 }
    }

    switch (tile.status) {
      case 'failed':
        return { state: 'failed', error: 'No se pudieron obtener los datos de esta zona' }
      case 'ready':
        // Listo pero sin este chunk/versión (p. ej. subió generatorVersion):
        // re-rasterizar desde los datos guardados, sin consultar al proveedor.
        await this.repo.requeue(tile.id)
        this.#onEnqueue?.()
        return { state: 'pending', retryAfterSeconds: 2 }
      default:
        return { state: 'pending', retryAfterSeconds: tile.status === 'fetching' ? 5 : 3 }
    }
  }

  /**
   * Encola todos los source tiles alrededor de un punto (pregeneración).
   * Con `refetch`, descarta los datos OSM guardados y los vuelve a pedir al
   * proveedor (necesario cuando se agregan tags nuevos a KEPT_TAGS).
   */
  async enqueueArea(
    lon: number,
    lat: number,
    radiusMeters: number,
    options: { refetch?: boolean } = {}
  ): Promise<{ total: number; created: number }> {
    const sz = this.config.sourceZoom
    const tiles = tilesAround(lon, lat, radiusMeters, sz)
    let created = 0
    for (const [x, y] of tiles) {
      const existing = await this.repo.findSourceTile(sz, x, y)
      if (!existing) {
        if (await this.repo.enqueueSourceTile(sz, x, y, tileBounds(sz, x, y))) created++
      } else if (
        options.refetch &&
        existing.status !== 'queued' &&
        existing.status !== 'fetching'
      ) {
        await this.repo.requeueForRefetch(existing.id)
        created++
      } else if (
        existing.status === 'failed' ||
        (existing.status === 'ready' && existing.rasterizedVersion < this.config.generatorVersion)
      ) {
        await this.repo.requeue(existing.id, true)
        created++
      }
    }
    if (created > 0) this.#onEnqueue?.()
    return { total: tiles.length, created }
  }

  /**
   * Procesa un source tile: obtiene datos (o reutiliza los guardados),
   * rasteriza sus chunks y los persiste. Devuelve cuántos chunks generó.
   */
  async processJob(job: ClaimedJob): Promise<number> {
    const cfg = this.config
    try {
      let features: FeatureSet
      const stored = job.hasData ? await this.repo.loadSourceData(job.id) : null

      if (stored) {
        features = decodeFeatureSet(stored)
      } else {
        const provider = await app.container.make(OsmProvider)
        const bbox = expandBBox(tileBounds(job.z, job.x, job.y), cfg.sourceMarginMeters)
        const started = Date.now()
        features = await provider.fetchFeatures(bbox)
        await this.repo.saveSourceData(job.id, encodeFeatureSet(features), {
          provider: provider.name,
          osmTimestamp: features.osmTimestamp,
          featureCount: features.features.length,
        })
        logger.info(
          {
            tile: `${job.z}/${job.x}/${job.y}`,
            features: features.features.length,
            ms: Date.now() - started,
          },
          'map: datos OSM obtenidos'
        )
      }

      const rasterizer = new SourceRasterizer(
        features,
        { cellZoom: cfg.cellZoom, chunkZoom: cfg.chunkZoom },
        tileCenterLatitude(job.z, job.y)
      )
      const chunks = childTiles(job.z, job.x, job.y, cfg.chunkZoom).map(([x, y]) => {
        const grid = rasterizer.rasterizeChunk(cfg.chunkZoom, x, y)
        const encoded = encodeChunk(grid, {
          cellZoom: cfg.cellZoom,
          generatorVersion: cfg.generatorVersion,
          osmTimestamp: features.osmTimestamp,
          attribution: cfg.attribution,
        })
        return { z: cfg.chunkZoom, x, y, ...encoded, bounds: tileBounds(cfg.chunkZoom, x, y) }
      })

      await this.repo.saveChunksAndMarkReady(job.id, cfg.generatorVersion, chunks)
      return chunks.length
    } catch (error) {
      const err = error as Error
      const retryable = !(error instanceof OsmProviderError) || error.retryable
      const attempt = job.attempts + 1
      const retryIn =
        retryable && attempt < cfg.worker.maxAttempts
          ? Math.min(30_000 * 2 ** (attempt - 1), 30 * 60_000)
          : null
      logger.warn(
        { tile: `${job.z}/${job.x}/${job.y}`, attempt, retryIn, err: err.message },
        'map: fallo generando'
      )
      await this.repo.markFailure(job.id, err.message, retryIn)
      return 0
    }
  }

  #touch(key: string, row: ChunkRow) {
    this.#memory.delete(key)
    this.#memory.set(key, row)
    if (this.#memory.size > this.config.limits.memoryCacheChunks) {
      const oldest = this.#memory.keys().next().value
      if (oldest !== undefined) this.#memory.delete(oldest)
    }
  }

  #allowEnqueue(ip: string): boolean {
    const now = Date.now()
    const { enqueuePerIp, enqueueWindowMs } = this.config.limits
    const recent = (this.#enqueuesByIp.get(ip) ?? []).filter((t) => now - t < enqueueWindowMs)
    if (recent.length >= enqueuePerIp) {
      this.#enqueuesByIp.set(ip, recent)
      return false
    }
    recent.push(now)
    this.#enqueuesByIp.set(ip, recent)
    return true
  }
}
