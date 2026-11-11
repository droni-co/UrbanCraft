import logger from '@adonisjs/core/services/logger'
import type { MapChunkService } from '#services/map_chunk_service'

/**
 * Worker en proceso que consume la cola osm_source_tiles.
 * - Concurrencia 1 por instancia (amable con Overpass).
 * - Varias instancias del backend pueden correrlo a la vez (SKIP LOCKED).
 * - Para escalar más: moverlo a un proceso dedicado o a una cola (BullMQ).
 */
export class MapWorker {
  #timer: NodeJS.Timeout | null = null
  #running = false
  #stopped = true

  constructor(
    private service: MapChunkService,
    private options: { pollIntervalMs: number; lockTimeoutMs: number }
  ) {
    service.onEnqueue(() => this.wake())
  }

  start() {
    if (!this.#stopped) return
    this.#stopped = false
    this.#timer = setInterval(() => this.wake(), this.options.pollIntervalMs)
    this.wake()
    logger.info('map: worker iniciado')
  }

  stop() {
    this.#stopped = true
    if (this.#timer) clearInterval(this.#timer)
    this.#timer = null
  }

  wake() {
    if (this.#stopped || this.#running) return
    this.#running = true
    this.#drain()
      .catch((error) => logger.error({ err: error }, 'map: error en el worker'))
      .finally(() => (this.#running = false))
  }

  /** Procesa un trabajo si hay. Devuelve true si procesó algo. */
  async processNext(): Promise<boolean> {
    const job = await this.service.repo.claimNextJob(this.options.lockTimeoutMs)
    if (!job) return false
    await this.service.processJob(job)
    return true
  }

  async #drain() {
    while (!this.#stopped && (await this.processNext())) {}
  }
}
