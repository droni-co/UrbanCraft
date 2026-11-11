import type { ApplicationService } from '@adonisjs/core/types'
import type { MapConfig } from '#config/map'
import { OsmProvider } from '#map/providers/osm_provider'
import { OverpassProvider } from '#map/providers/overpass_provider'
import { MapChunkService } from '#services/map_chunk_service'
import { MapWorker } from '#services/map_worker'

/**
 * Registra los servicios del mapa en el contenedor IoC y arranca el worker
 * de generación solo en el proceso web (no en comandos ace ni en tests).
 */
export default class MapProvider {
  constructor(protected app: ApplicationService) {}

  register() {
    const config = () => this.app.config.get<MapConfig>('map')

    this.app.container.singleton(OsmProvider, () => new OverpassProvider(config().overpass))
    this.app.container.singleton(MapChunkService, () => new MapChunkService(config()))
    this.app.container.singleton(MapWorker, async (resolver) => {
      const { worker } = config()
      return new MapWorker(await resolver.make(MapChunkService), worker)
    })
  }

  async ready() {
    if (
      this.app.getEnvironment() === 'web' &&
      this.app.config.get<MapConfig>('map').worker.enabled
    ) {
      const worker = await this.app.container.make(MapWorker)
      worker.start()
    }
  }

  async shutdown() {
    if (this.app.container.hasBinding(MapWorker)) {
      const worker = await this.app.container.make(MapWorker)
      worker.stop()
    }
  }
}
