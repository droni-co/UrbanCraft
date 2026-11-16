/** Ciudad y país de una zona (geocodificación inversa). */
export interface Place {
  city: string | null
  region: string | null
  country: string | null
  /** ISO 3166-1 alfa-2 en mayúsculas (p. ej. "ES"). */
  countryCode: string | null
  /** Texto listo para mostrar: "Madrid, España". */
  label: string
}

export class GeoProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean
  ) {
    super(message)
  }
}

/** Arma el texto "Ciudad, País" sin repetir (ciudades-estado como Singapur). */
export function placeLabel(city: string | null, region: string | null, country: string | null) {
  const parts = [city ?? region, country].filter((p): p is string => Boolean(p))
  return [...new Set(parts)].join(', ')
}
