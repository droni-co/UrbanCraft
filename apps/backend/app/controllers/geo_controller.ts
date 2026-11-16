import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'
import { GeoService } from '#services/geo_service'

function parseCoordinate(value: unknown, max: number): number | null {
  if (typeof value !== 'string' || !/^-?\d{1,3}(\.\d{1,10})?$/.test(value)) return null
  const n = Number(value)
  return Math.abs(n) <= max ? n : null
}

@inject()
export default class GeoController {
  constructor(private geo: GeoService) {}

  /**
   * GET /api/v1/geo/place?lat=&lon=
   * Ciudad y país de la zona (resuelto por tile, cacheado para todos).
   * 200 { city, region, country, countryCode, label } · 404 sin ciudad · 503 proveedor caído
   */
  async place({ request, response }: HttpContext) {
    const lat = parseCoordinate(request.input('lat'), 85)
    const lon = parseCoordinate(request.input('lon'), 180)
    if (lat === null || lon === null) {
      return response.unprocessableEntity({ error: 'lat/lon inválidos' })
    }
    const result = await this.geo.place(lat, lon)
    if (result.state === 'unavailable') {
      response.header('Retry-After', '30')
      return response.serviceUnavailable({ error: 'Servicio de geocodificación no disponible' })
    }
    response.header('Cache-Control', 'public, max-age=86400')
    if (!result.place) return response.notFound({ error: 'Zona sin ciudad conocida' })
    return result.place
  }
}
