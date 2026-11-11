import { BaseCommand, flags } from '@adonisjs/core/ace'
import type { CommandOptions } from '@adonisjs/core/types/ace'
import { MapChunkService } from '#services/map_chunk_service'
import { MapWorker } from '#services/map_worker'

/**
 * Pregenera el mapa de una zona (p. ej. antes de lanzar el juego en una ciudad)
 * para que los primeros jugadores no esperen a Overpass.
 *
 *   node ace map:pregenerate --lat=40.42 --lon=-3.6887 --radius=1500 --wait
 *
 * --refetch vuelve a consultar al proveedor OSM (p. ej. tras agregar tags a
 * KEPT_TAGS, como addr:housenumber para los números de portal).
 */
export default class MapPregenerate extends BaseCommand {
  static commandName = 'map:pregenerate'
  static description =
    'Encola (y opcionalmente procesa) la generación del mapa alrededor de una coordenada'
  static options: CommandOptions = { startApp: true }

  @flags.number({ description: 'Latitud del centro', required: true })
  declare lat: number

  @flags.number({ description: 'Longitud del centro', required: true })
  declare lon: number

  @flags.number({ description: 'Radio en metros', default: 1000 })
  declare radius: number

  @flags.boolean({ description: 'Procesar la cola en este proceso hasta vaciarla' })
  declare wait: boolean

  @flags.boolean({
    description: 'Volver a pedir los datos OSM aunque ya estén guardados (tags nuevos)',
  })
  declare refetch: boolean

  async run() {
    if (
      Math.abs(this.lat) > 85 ||
      Math.abs(this.lon) > 180 ||
      this.radius <= 0 ||
      this.radius > 20_000
    ) {
      this.logger.error('Coordenadas o radio fuera de rango (radio máximo 20 km)')
      this.exitCode = 1
      return
    }

    const service = await this.app.container.make(MapChunkService)
    const { total, created } = await service.enqueueArea(this.lon, this.lat, this.radius, {
      refetch: this.refetch,
    })
    this.logger.info(`${total} source tiles cubren la zona; ${created} encolados`)

    if (!this.wait) {
      this.logger.info(
        'El worker del servidor web los procesará. Usa --wait para procesarlos aquí.'
      )
      return
    }

    const worker = await this.app.container.make(MapWorker)
    let processed = 0
    while (await worker.processNext()) {
      processed++
      this.logger.info(`Procesados ${processed} source tiles...`)
    }
    this.logger.success(`Cola vacía. ${processed} source tiles procesados.`)
  }
}
