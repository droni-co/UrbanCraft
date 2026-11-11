import { GeoProviderError, placeLabel, type Place } from '#geo/types'
import { ReverseGeocoder } from '#geo/providers/reverse_geocoder'

export interface NominatimOptions {
  url: string
  userAgent: string
  timeoutMs: number
}

interface NominatimAddress {
  city?: string
  town?: string
  village?: string
  municipality?: string
  hamlet?: string
  county?: string
  state?: string
  region?: string
  province?: string
  country?: string
  country_code?: string
}

/**
 * Nominatim (OpenStreetMap). El servidor público exige: User-Agent propio,
 * máximo 1 petición/s y cachear resultados; GeoService se encarga de las dos
 * últimas. Para producción conviene una instancia propia (NOMINATIM_URL).
 */
export class NominatimGeocoder extends ReverseGeocoder {
  readonly name = 'nominatim'

  constructor(private options: NominatimOptions) {
    super()
  }

  async reverse(latitude: number, longitude: number, language: string): Promise<Place | null> {
    const url = new URL('/reverse', this.options.url)
    url.search = new URLSearchParams({
      'format': 'jsonv2',
      'lat': latitude.toFixed(5),
      'lon': longitude.toFixed(5),
      'zoom': '10', // nivel ciudad
      'addressdetails': '1',
      'accept-language': language,
    }).toString()

    let response: Response
    try {
      response = await fetch(url, {
        headers: { 'User-Agent': this.options.userAgent, 'Accept': 'application/json' },
        signal: AbortSignal.timeout(this.options.timeoutMs),
      })
    } catch (error) {
      throw new GeoProviderError(`Nominatim no respondió: ${(error as Error).message}`, true)
    }
    if (!response.ok) {
      throw new GeoProviderError(
        `Nominatim HTTP ${response.status}`,
        response.status === 429 || response.status >= 500
      )
    }

    const json = (await response.json()) as { address?: NominatimAddress; error?: string }
    if (json.error || !json.address) return null
    return parseNominatimAddress(json.address)
  }
}

export function parseNominatimAddress(a: NominatimAddress): Place | null {
  const city = a.city ?? a.town ?? a.village ?? a.municipality ?? a.hamlet ?? a.county ?? null
  const region = a.state ?? a.region ?? a.province ?? null
  const country = a.country ?? null
  if (!city && !region && !country) return null
  return {
    city,
    region,
    country,
    countryCode: a.country_code ? a.country_code.toUpperCase() : null,
    label: placeLabel(city, region, country),
  }
}
