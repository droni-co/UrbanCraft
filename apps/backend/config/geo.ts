import env from '#start/env'

/**
 * Geolocalización del jugador:
 *
 * - Ubicación aproximada por IP: respaldo cuando el dispositivo no tiene GPS
 *   (PC) o el jugador no dio permiso. Precisión de ciudad (puede fallar por
 *   varios km), así que el cliente la marca como aproximada.
 * - Ciudad y país (geocodificación inversa) con Nominatim (datos OSM). Se
 *   consulta por tile (placeZoom), no por la posición exacta del jugador: más
 *   privado y cacheable para todos los que estén en la misma zona.
 */
const geoConfig = {
  /** Zoom del tile que agrupa las consultas de ciudad/país (z14 ≈ 2.4 km). */
  placeZoom: 14,
  /** Idioma de los nombres (ciudad, país). */
  language: 'es',

  nominatim: {
    url: env.get('NOMINATIM_URL', 'https://nominatim.openstreetmap.org'),
    userAgent: 'UrbanCraft/0.1 (game map generator)',
    timeoutMs: 10_000,
    /** Política de uso del servidor público: máximo 1 petición por segundo. */
    minIntervalMs: 1100,
  },

  ip: {
    enabled: env.get('GEO_IP_ENABLED', true),
    /** Se prueban en orden hasta que uno responda. */
    providers: ['ipapi', 'ipwho'] as Array<'ipapi' | 'ipwho'>,
    timeoutMs: 6000,
    /** Resultados por IP que se guardan en memoria (y por cuánto tiempo). */
    cacheEntries: 5000,
    cacheTtlMs: 6 * 60 * 60_000,
    /** Consultas por IP por ventana (protege la cuota de los proveedores). */
    perIp: 10,
    windowMs: 10 * 60_000,
  },
}

export type GeoConfig = typeof geoConfig
export default geoConfig
