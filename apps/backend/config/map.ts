import env from '#start/env'

/**
 * Configuración del mapa del mundo real.
 *
 * Jerarquía de grillas (todas en Web Mercator / slippy tiles):
 *
 *   source tile (z15, ~1.2 km)  -> 1 consulta al proveedor OSM, datos crudos cacheados
 *     └─ chunk (z18, ~150 m)    -> unidad que descarga el cliente (64x64 celdas)
 *          └─ celda (z24, ~2.4 m en el ecuador) -> un tile isométrico del juego
 *
 * Cambiar cellZoom/chunkZoom invalida todos los chunks: sube generatorVersion.
 */
const mapConfig = {
  chunkZoom: 18,
  cellZoom: 24,
  sourceZoom: 15,

  /**
   * Versión del algoritmo de rasterizado. Súbela cuando cambien las reglas de
   * estilo (catalog/rasterizer): los chunks se regeneran desde los datos OSM ya
   * guardados, sin volver a consultar al proveedor.
   */
  generatorVersion: 2,

  /** Margen extra al pedir datos de un source tile (para calles que rozan el borde). */
  sourceMarginMeters: 40,

  /**
   * Radio de juego libre alrededor de la ubicación real del jugador (modo
   * híbrido). El cliente NO descarga toda la zona: carga chunks alrededor del
   * jugador y el servidor genera las zonas nuevas a medida que se acerca.
   */
  playRadiusMeters: 5000,

  attribution: '© OpenStreetMap contributors',

  overpass: {
    url: env.get('OVERPASS_URL', 'https://overpass-api.de/api/interpreter'),
    /** Timeout que se pide al servidor Overpass y timeout HTTP local. */
    timeoutSeconds: 120,
    userAgent: 'UrbanCraft/0.1 (game map generator)',
  },

  worker: {
    enabled: env.get('MAP_WORKER_ENABLED', true),
    pollIntervalMs: 2000,
    maxAttempts: 5,
    /** Un job "fetching" más viejo que esto se considera huérfano y se reintenta. */
    lockTimeoutMs: 5 * 60_000,
  },

  limits: {
    /** Máximo de source tiles en cola (protege al proveedor OSM). */
    maxQueuedSourceTiles: 200,
    /** Source tiles nuevos que una misma IP puede encolar por ventana. */
    enqueuePerIp: 20,
    enqueueWindowMs: 10 * 60_000,
    /** Chunks listos que se mantienen en memoria (LRU). */
    memoryCacheChunks: 2000,
  },
}

export type MapConfig = typeof mapConfig
export default mapConfig
