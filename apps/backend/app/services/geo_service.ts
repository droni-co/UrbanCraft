import db from '@adonisjs/lucid/services/db'
import type { GeoConfig } from '#config/geo'
import { lonLatToTile, worldToLat, worldToLon } from '#map/geo'
import type { ReverseGeocoder } from '#geo/providers/reverse_geocoder'
import type { Place } from '#geo/types'

export type PlaceResult = { state: 'ok'; place: Place | null } | { state: 'unavailable' }

/**
 * Ciudad/país de una zona: se resuelve por tile (z14 ≈ 2.4 km) consultando el CENTRO del
 * tile, nunca la posición exacta del jugador. Caché en memoria -> tabla
 * geo_places -> proveedor, con las peticiones al proveedor serializadas a
 * 1/s (política de Nominatim) y deduplicadas mientras están en vuelo.
 */
export class GeoService {
  readonly #memory = new Map<string, Place | null>()
  readonly #inFlight = new Map<string, Promise<Place | null>>()
  #queue: Promise<unknown> = Promise.resolve()
  #lastRequestAt = 0

  constructor(
    readonly config: GeoConfig,
    private geocoder: ReverseGeocoder
  ) {}

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
}
