import env from '#start/env'

/**
 * Ciudad y país de la zona de juego (geocodificación inversa) con Nominatim
 * (datos OSM). Se consulta por tile (placeZoom), no por la posición exacta del
 * jugador: más privado y cacheable para todos los que estén en la misma zona.
 *
 * La ubicación del jugador la da solo el GPS de su dispositivo (o del
 * navegador); el servidor no la estima por IP.
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
}

export type GeoConfig = typeof geoConfig
export default geoConfig
