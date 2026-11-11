import type { BBox } from '#map/geo'
import type { FeatureSet } from '#map/features'

/**
 * Fuente de datos geográficos. Implementaciones:
 *  - OverpassProvider: API pública/privada de Overpass (actual)
 *  - (futuro) PostgisProvider: tablas importadas con osm2pgsql
 *
 * Se registra en el contenedor IoC (providers/map_provider.ts), así que
 * cambiar de proveedor o usar uno falso en tests no toca el resto del código.
 */
export abstract class OsmProvider {
  abstract readonly name: string
  abstract fetchFeatures(bbox: BBox): Promise<FeatureSet>
}

export class OsmProviderError extends Error {
  constructor(
    message: string,
    /** true si conviene reintentar más tarde (timeouts, 429, 5xx). */
    readonly retryable: boolean
  ) {
    super(message)
  }
}
