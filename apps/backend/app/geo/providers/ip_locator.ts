import { GeoProviderError, type IpLocation } from '#geo/types'

/**
 * Ubicación aproximada por IP. `ip = null` consulta la IP de quien llama, o
 * sea, la del propio servidor: útil en desarrollo, cuando el cliente se conecta
 * desde localhost y su IP pública es la misma que la del servidor.
 */
export abstract class IpLocator {
  abstract readonly name: string
  abstract locate(ip: string | null): Promise<IpLocation | null>
}

/** Prueba varios proveedores en orden hasta que uno responda. */
export class ChainIpLocator extends IpLocator {
  readonly name = 'chain'

  constructor(private locators: IpLocator[]) {
    super()
  }

  async locate(ip: string | null): Promise<IpLocation | null> {
    let lastError: Error | null = null
    for (const locator of this.locators) {
      try {
        const result = await locator.locate(ip)
        if (result) return result
      } catch (error) {
        lastError = error as Error
      }
    }
    if (lastError) throw new GeoProviderError(lastError.message, true)
    return null
  }
}

abstract class HttpIpLocator extends IpLocator {
  constructor(
    protected userAgent: string,
    protected timeoutMs: number
  ) {
    super()
  }

  protected async getJson(url: string): Promise<any> {
    let response: Response
    try {
      response = await fetch(url, {
        headers: { 'User-Agent': this.userAgent, 'Accept': 'application/json' },
        signal: AbortSignal.timeout(this.timeoutMs),
      })
    } catch (error) {
      throw new GeoProviderError(`${this.name} no respondió: ${(error as Error).message}`, true)
    }
    if (!response.ok) throw new GeoProviderError(`${this.name} HTTP ${response.status}`, true)
    return response.json()
  }
}

function validCoords(lat: unknown, lon: unknown): lat is number {
  return (
    typeof lat === 'number' &&
    typeof lon === 'number' &&
    Number.isFinite(lat) &&
    Number.isFinite(lon) &&
    Math.abs(lat) <= 90 &&
    Math.abs(lon) <= 180 &&
    !(lat === 0 && lon === 0)
  )
}

/** https://ipapi.co (HTTPS, sin clave; cuota gratuita diaria). */
export class IpapiLocator extends HttpIpLocator {
  readonly name = 'ipapi'

  async locate(ip: string | null): Promise<IpLocation | null> {
    const d = await this.getJson(`https://ipapi.co/${ip ? `${encodeURIComponent(ip)}/` : ''}json/`)
    if (d.error) {
      if (d.reserved) return null
      throw new GeoProviderError(`ipapi: ${d.reason ?? 'error'}`, true)
    }
    if (!validCoords(d.latitude, d.longitude)) return null
    return {
      latitude: d.latitude,
      longitude: d.longitude,
      city: d.city ?? null,
      region: d.region ?? null,
      country: d.country_name ?? null,
      countryCode: d.country_code ?? null,
      accuracyKm: 10,
      provider: this.name,
    }
  }
}

/** https://ipwho.is (HTTPS, sin clave). */
export class IpwhoLocator extends HttpIpLocator {
  readonly name = 'ipwho'

  async locate(ip: string | null): Promise<IpLocation | null> {
    const d = await this.getJson(`https://ipwho.is/${ip ? encodeURIComponent(ip) : ''}`)
    if (d.success === false) {
      if (/reserved|private|invalid/i.test(String(d.message ?? ''))) return null
      throw new GeoProviderError(`ipwho: ${d.message ?? 'error'}`, true)
    }
    if (!validCoords(d.latitude, d.longitude)) return null
    return {
      latitude: d.latitude,
      longitude: d.longitude,
      city: d.city ?? null,
      region: d.region ?? null,
      country: d.country ?? null,
      countryCode: d.country_code ?? null,
      accuracyKm: 10,
      provider: this.name,
    }
  }
}
