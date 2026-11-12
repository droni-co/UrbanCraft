/**
 * Protocolo del multijugador (JSON por WebSocket). Mensajes cortos: se mandan
 * hasta 10 veces por segundo a cada jugador.
 *
 * Cliente → servidor
 *   { t: 'auth', token }                     primer mensaje (token de acceso)
 *   { t: 'state', x, y, d, m, spawn? }       posición en celdas globales, dirección 0–7
 *                                            (e, se, s, sw, w, nw, n, ne), movimiento
 *                                            0 quieto · 1 camina · 2 corre
 *   { t: 'act', k }                          acción visible para los demás (ACTIONS)
 *   { t: 'vis', v }                          visible para otros jugadores (modo fantasma)
 *   { t: 'ping', c }                         latido / medir latencia
 *   { t: 'say', m }                          mensaje de chat (texto, hasta CHAT_MAX_LENGTH)
 *   { t: 'voice', on }                       entra o sale de la voz con amigos
 *   { t: 'rtc', to, k, d }                   señalización WebRTC para un amigo en la voz:
 *                                            k = 'offer' | 'answer' | 'ice', d = texto (JSON)
 *
 * Servidor → cliente
 *   { t: 'welcome', id, tickMs, nearbyRadius, radarRadiusMeters, ice }
 *                                            ice: servidores STUN/TURN para la voz
 *   { t: 'snap', p: [[id, x, y, d, m], …], info?: { id: { n, lv, s } } }
 *                                            info: apodo, nivel y personaje (skin), la
 *                                            primera vez y cuando cambian
 *   { t: 'radar', p: [[id, x, y], …] }       posiciones redondeadas
 *   { t: 'act', id, k }
 *   { t: 'friends', e, n }                   cambio en amigos: e = 'request' (solicitud
 *                                            nueva) o 'accepted', n = apodo del otro
 *   { t: 'chat', id, n, m, f }               mensaje de chat de un jugador de tu zona (tu
 *                                            chunk y los vecinos) o de un amigo (f = 1).
 *                                            Los tuyos también vuelven (id = el tuyo)
 *   { t: 'reject', r, retry }                r = 'spawn' | 'speed' (posición rechazada) o
 *                                            'chat' (demasiados mensajes, espera retry ms)
 *   { t: 'voice', id, n, on }                un amigo entró o salió de la voz (al entrar tú,
 *                                            llega uno por cada amigo que ya estaba)
 *   { t: 'rtc', from, k, d }                 señalización WebRTC de un amigo
 *   { t: 'pong', c }
 *   { t: 'error', e }                        y a veces se cierra la conexión
 */

/** Largo máximo de un mensaje de chat (caracteres). */
export const CHAT_MAX_LENGTH = 200

/** Tipos de mensaje de señalización WebRTC y largo máximo de su contenido. */
export const RTC_KINDS = ['offer', 'answer', 'ice'] as const
export type RtcKind = (typeof RTC_KINDS)[number]
export const RTC_MAX_LENGTH = 12_000

export const ACTIONS = ['interact', 'wave'] as const
export type ActionKind = (typeof ACTIONS)[number]

export type MoveState = 0 | 1 | 2

export type ClientMessage =
  | { t: 'auth'; token: string }
  | { t: 'state'; x: number; y: number; d: number; m: MoveState; spawn: boolean }
  | { t: 'act'; k: ActionKind }
  | { t: 'vis'; v: boolean }
  | { t: 'ping'; c: number }
  | { t: 'say'; m: string }
  | { t: 'voice'; on: boolean }
  | { t: 'rtc'; to: number; k: RtcKind; d: string }

/** Las celdas globales van de 0 a 2^cellZoom. */
const MAX_COORD = 2 ** 30

/** Valida y normaliza un mensaje del cliente; null si no es válido. */
export function parseClientMessage(raw: string): ClientMessage | null {
  let data: unknown
  try {
    data = JSON.parse(raw)
  } catch {
    return null
  }
  if (typeof data !== 'object' || data === null) return null
  const msg = data as Record<string, unknown>
  switch (msg.t) {
    case 'auth':
      return typeof msg.token === 'string' && msg.token.length > 0 && msg.token.length < 512
        ? { t: 'auth', token: msg.token }
        : null
    case 'state': {
      const { x, y, d, m } = msg
      if (!isCoord(x) || !isCoord(y)) return null
      if (!Number.isInteger(d) || (d as number) < 0 || (d as number) > 7) return null
      if (m !== 0 && m !== 1 && m !== 2) return null
      return { t: 'state', x, y, d: d as number, m, spawn: msg.spawn === true }
    }
    case 'act':
      return ACTIONS.includes(msg.k as ActionKind) ? { t: 'act', k: msg.k as ActionKind } : null
    case 'vis':
      return typeof msg.v === 'boolean' ? { t: 'vis', v: msg.v } : null
    case 'ping':
      return typeof msg.c === 'number' && Number.isFinite(msg.c) ? { t: 'ping', c: msg.c } : null
    case 'voice':
      return typeof msg.on === 'boolean' ? { t: 'voice', on: msg.on } : null
    case 'rtc':
      return Number.isInteger(msg.to) &&
        (msg.to as number) > 0 &&
        RTC_KINDS.includes(msg.k as RtcKind) &&
        typeof msg.d === 'string' &&
        msg.d.length > 0 &&
        msg.d.length <= RTC_MAX_LENGTH
        ? { t: 'rtc', to: msg.to as number, k: msg.k as RtcKind, d: msg.d }
        : null
    case 'say': {
      const text = cleanChatText(msg.m)
      return text ? { t: 'say', m: text } : null
    }
  }
  return null
}

/**
 * Normaliza un mensaje de chat: sin caracteres de control ni de dirección del
 * texto (que permiten "voltear" lo que se ve), espacios colapsados y recortado.
 * null si queda vacío o pasa de CHAT_MAX_LENGTH.
 */
export function cleanChatText(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const text = value
    .normalize('NFC')
    .replace(/[\p{Cc}\u202A-\u202E\u2066-\u2069]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  if (text.length === 0 || [...text].length > CHAT_MAX_LENGTH) return null
  return text
}

function isCoord(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v) && v >= 0 && v < MAX_COORD
}

/** Redondea a 2 decimales (≈ 2 cm): suficiente y más corto en JSON. */
export function round2(v: number) {
  return Math.round(v * 100) / 100
}
