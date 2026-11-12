/**
 * Multijugador en tiempo real (WebSocket en /ws). Ver docs/multijugador.md.
 *
 * Las posiciones viajan en celdas GLOBALES (zoom cellZoom de config/map.ts,
 * ~1,5–2,4 m por celda) con decimales. El servidor reparte a cada jugador:
 * - "snap" (10 por segundo): los jugadores cercanos, que se ven en pantalla.
 * - "radar" (1 por segundo): los de su radio de alcance, para el minimapa, con
 *   la posición redondeada (privacidad).
 * - "chat": los mensajes de los jugadores de su zona y de sus amigos.
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

  /**
   * Chat: un mensaje llega a los jugadores a menos de chatChunkRadius chunks
   * del que habla (1 = su chunk y los 8 vecinos, ~450 m; 0 = solo su chunk) y
   * a sus amigos, estén donde estén.
   */
  chatChunkRadius: 1,
  /** Ráfaga de mensajes permitida y cada cuánto se recupera uno (ms). */
  chatBurst: 4,
  chatRefillMs: 2000,

  /**
   * Voz con amigos (WebRTC directo entre jugadores, ver docs/voz.md): el
   * servidor solo reenvía la señalización. Servidores ICE que usan los
   * clientes; para agregar un TURN: { urls: 'turn:…', username, credential }.
   */
  voiceIceServers: [
    { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
  ] as {
    urls: string | string[]
    username?: string
    credential?: string
  }[],

  /** Límites por conexión (las ofertas WebRTC ocupan unos 3–6 KB). */
  maxMessageBytes: 16_384,
  maxMessagesPerSecond: 40,
}

export type RealtimeConfig = typeof realtimeConfig
export default realtimeConfig
