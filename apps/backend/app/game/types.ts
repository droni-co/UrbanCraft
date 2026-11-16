import type { TransactionClientContract } from '@adonisjs/lucid/types/database'
export type Trx = TransactionClientContract

/** Error de una acción del juego, con un mensaje listo para mostrar al jugador. */
export class GameError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 422
  ) {
    super(message)
  }
}

/**
 * Cosas que le pasaron al jugador por una acción. El cliente las muestra en
 * orden: avisos, recompensas, logros, diálogos de la historia…
 */
export type GameEvent =
  | { type: 'toast'; text: string }
  | { type: 'reward'; reason?: string; money?: number; xp?: number; items?: Record<string, number> }
  | { type: 'discover'; name: string; cat: string }
  | { type: 'achievement'; key: string; name: string; desc: string; tier: number; emblem: string }
  | { type: 'dialog'; npc: string; lines: string[] }
  | { type: 'story'; kind: 'step' | 'chapter'; title: string; text: string }
  | {
      type: 'sector'
      kind: 'rank' | 'owned' | 'lost'
      name: string
      rank?: number
      rankName?: string
    }

/** Estado del jugador que no es inventario ni contadores (una fila JSON). */
export interface PlayerState {
  story: {
    chapter: number
    step: number
    /** Valor de los contadores al empezar el paso (metas de tipo counter). */
    base: Record<string, number>
    /** Índices de las metas "talk" ya cumplidas en el paso. */
    talked: number[]
    /** El primer paso ya se preparó (jugador nuevo). */
    started?: boolean
    /** El diálogo de entrada del paso ya se mostró. */
    introSeen: boolean
  }
  daily: { day: string; streak: number }
  /** Enfriamientos: clave → momento (ms) en que se puede volver a hacer. */
  cooldowns: Record<string, number>
  /** Última vez que cobró la renta de sus sectores (ms). */
  rentAt: number
  /** Última vez que pidió encargos nuevos (ms). */
  jobsAt: number
}

export function newPlayerState(now: number): PlayerState {
  return {
    story: { chapter: 0, step: 0, base: {}, talked: [], introSeen: false },
    daily: { day: '', streak: 0 },
    cooldowns: {},
    rentAt: now,
    jobsAt: 0,
  }
}

/** Contexto de una acción: una transacción, el jugador y lo que va pasando. */
export interface Ctx {
  trx: Trx
  userId: number
  now: Date
  state: PlayerState
  events: GameEvent[]
  /** Contadores que cambiaron (para revisar logros e historia al final). */
  touched: Set<string>
  /** Avisos para otros jugadores (se mandan después del commit). */
  notices: { userId: number; events: GameEvent[] }[]
  /** Objetos del mapa que cambiaron (se difunden después del commit). */
  objectChanges: { op: 'put' | 'del'; id: number; x: number; y: number }[]
}

/** Hash FNV-1a de 32 bits: estable entre reinicios (precios, nombres, surtido). */
export function hash(text: string) {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

/** Número estable en [0, 1) a partir de un texto. */
export function hash01(text: string) {
  return hash(text) / 0x100000000
}

export function randomInt(min: number, max: number) {
  return min + Math.floor(Math.random() * (max - min + 1))
}

export function pick<T>(list: readonly T[]): T {
  return list[Math.floor(Math.random() * list.length)]
}
