import { isIP } from 'node:net'
import db from '@adonisjs/lucid/services/db'
import type { GeoConfig } from '#config/geo'
import { lonLatToTile, worldToLat, worldToLon } from '#map/geo'
import type { IpLocator } from '#geo/providers/ip_locator'
import type { ReverseGeocoder } from '#geo/providers/reverse_geocoder'
import type { IpLocation, Place } from '#geo/types'

export type PlaceResult = { state: 'ok'; place: Place | null } | { state: 'unavailable' }
export type IpResult =
  | { state: 'ok'; location: IpLocation | null }
  | { state: 'unavailable' }
  | { state: 'disabled' }
  | { state: 'throttled' }

/**
 * Ciudad/país de una zona y ubicación aproximada por IP.
 *
 * Ciudad/país: se resuelve por tile (z14 ≈ 2.4 km) consultando el CENTRO del
 * tile, nunca la posición exacta del jugador. Caché en memoria -> tabla
 * geo_places -> proveedor, con las peticiones al proveedor serializadas a
 * 1/s (política de Nominatim) y deduplicadas mientras están en vuelo.
 */
export class GeoService {
  readonly #memory = new Map<string, Place | null>()
  readonly #inFlight = new Map<string, Promise<Place | null>>()
  readonly #ipCache = new Map<string, { at: number; location: IpLocation | null }>()
  readonly #ipRequests = new Map<string, number[]>()
  #queue: Promise<unknown> = Promise.resolve()
  #lastRequestAt = 0

  constructor(
    readonly config: GeoConfig,
    private geocoder: ReverseGeocoder,
    private ipLocator: IpLocator
  ) {}

  // --- ciudad / país ---

  async place(latitude: number, longitude: number): Promise<PlaceResult> {
    const z = this.config.placeZoom
    const [x, y] = lonLatToTile(longitude, latitude, z)
    const lang = this.config.language
    const key = `${z}/${x}/${y}/${lang}`

    if (this.#memory.has(key)) return { state: 'ok', place: this.#memory.get(key)! }

    const { rows } = await db.rawQuery(
      'SELECT data FROM geo_places WHERE z = ? AND x = ? AND y = ? AND language = ?',
      [z, x, y, lang]
    )
    if (rows[0]) return { state: 'ok', place: this.#remember(key, rows[0].data) }

    let pending = this.#inFlight.get(key)
    if (!pending) {
      const lat = worldToLat(y + 0.5, z)
      const lon = worldToLon(x + 0.5, z)
      pending = this.#throttled(() => this.geocoder.reverse(lat, lon, lang)).finally(() =>
        this.#inFlight.delete(key)
      )
      this.#inFlight.set(key, pending)
    }

    let place: Place | null
    try {
      place = await pending
    } catch {
      return { state: 'unavailable' }
    }
    await db.rawQuery(
      `INSERT INTO geo_places (z, x, y, language, data, provider, fetched_at)
       VALUES (?, ?, ?, ?, ?, ?, now())
       ON CONFLICT (z, x, y, language) DO NOTHING`,
      [z, x, y, lang, place ? JSON.stringify(place) : null, this.geocoder.name]
    )
    return { state: 'ok', place: this.#remember(key, place) }
  }

  #remember(key: string, place: Place | null): Place | null {
    this.#memory.set(key, place)
    if (this.#memory.size > 10_000) this.#memory.delete(this.#memory.keys().next().value!)
    return place
  }

  /** Ejecuta las llamadas al proveedor de a una, separadas por minIntervalMs. */
  #throttled<T>(task: () => Promise<T>): Promise<T> {
    const run = this.#queue.then(async () => {
      const wait = this.#lastRequestAt + this.config.nominatim.minIntervalMs - Date.now()
      if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait))
      try {
        return await task()
      } finally {
        this.#lastRequestAt = Date.now()
      }
    })
    this.#queue = run.catch(() => {})
    return run
  }

  // --- ubicación por IP ---

  async locateIp(clientIp: string): Promise<IpResult> {
    const cfg = this.config.ip
    if (!cfg.enabled) return { state: 'disabled' }

    // IP local/privada (desarrollo): el proveedor usa la IP pública del servidor.
    const ip = isPublicIp(clientIp) ? clientIp : null
    const key = ip ?? 'self'
    const cached = this.#ipCache.get(key)
    if (cached && Date.now() - cached.at < cfg.cacheTtlMs) {
      return { state: 'ok', location: cached.location }
    }
    if (!this.#allowIpRequest(clientIp)) return { state: 'throttled' }

    try {
      const location = await this.ipLocator.locate(ip)
      this.#ipCache.set(key, { at: Date.now(), location })
      if (this.#ipCache.size > cfg.cacheEntries) {
        this.#ipCache.delete(this.#ipCache.keys().next().value!)
      }
      return { state: 'ok', location }
    } catch {
      return { state: 'unavailable' }
    }
  }

  #allowIpRequest(ip: string): boolean {
    const now = Date.now()
    const { perIp, windowMs } = this.config.ip
    const recent = (this.#ipRequests.get(ip) ?? []).filter((t) => now - t < windowMs)
    const allowed = recent.length < perIp
    if (allowed) recent.push(now)
    this.#ipRequests.set(ip, recent)
    return allowed
  }
}

/** false para loopback, redes privadas, link-local y CGNAT. */
export function isPublicIp(ip: string): boolean {
  const v = ip.startsWith('::ffff:') ? ip.slice(7) : ip
  const family = isIP(v)
  if (family === 4) {
    const [a, b] = v.split('.').map(Number)
    return !(
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168)
    )
  }
  if (family === 6) {
    const lower = v.toLowerCase()
    return !(
      lower === '::1' ||
      lower === '::' ||
      lower.startsWith('fc') ||
      lower.startsWith('fd') ||
      lower.startsWith('fe80')
    )
  }
  return false
}
