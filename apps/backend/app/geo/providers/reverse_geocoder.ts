import type { Place } from '#geo/types'

/**
 * Geocodificación inversa: coordenada -> ciudad/país. Intercambiable (Nominatim
 * público hoy; una instancia propia o un servicio comercial en producción).
 */
export abstract class ReverseGeocoder {
  abstract readonly name: string
  /** null si el punto no pertenece a ninguna ciudad/país (mar abierto). */
  abstract reverse(latitude: number, longitude: number, language: string): Promise<Place | null>
}
