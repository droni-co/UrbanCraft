/**
 * Multijugador en tiempo real (WebSocket en /ws). Ver docs/multijugador.md.
 *
 * Las posiciones viajan en celdas GLOBALES (zoom cellZoom de config/map.ts,
 * ~1,5–2,4 m por celda) con decimales. El servidor reparte a cada jugador:
 * - "snap" (10 por segundo): los jugadores cercanos, que se ven en pantalla.
 * - "radar" (1 por segundo): los de su radio de alcance, para el minimapa, con
 *   la posición redondeada (privacidad).
 */
const realtimeConfig = {
  path: '/ws',

  /** Intervalo de envío de snapshots (ms). */
  tickMs: 100,
  /** Cada cuántos ticks se envía el radar. */
  radarEveryTicks: 10,

  /** Radio (en celdas) de los jugadores que se ven en pantalla. */
  nearbyRadiusCells: 40,
  /** Radio de alcance del minimapa (metros). */
  radarRadiusMeters: 1000,
  /** Redondeo de las posiciones del radar (metros): no revela la posición exacta. */
  radarPrecisionMeters: 25,

  /** Tamaño de las celdas del índice espacial (en celdas del mapa). */
  bucketCells: 128,

  /** Sin "auth" válido en este tiempo se cierra la conexión. */
  authTimeoutMs: 5000,
  /** Sin mensajes en este tiempo se considera desconectado (el cliente manda latidos). */
  idleTimeoutMs: 30_000,

  /** Anti-trampas básico: velocidad máxima (celdas/s) con algo de margen. */
  maxSpeedCellsPerSecond: 9,
  /** Saltos mayores (aparecer, teletransporte) se marcan con spawn y se limitan. */
  minSpawnIntervalMs: 3000,

  /** Límites por conexión. */
  maxMessageBytes: 2048,
  maxMessagesPerSecond: 40,
}

export type RealtimeConfig = typeof realtimeConfig
export default realtimeConfig
