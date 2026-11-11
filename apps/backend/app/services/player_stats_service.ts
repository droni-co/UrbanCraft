import db from '@adonisjs/lucid/services/db'
import type { TransactionClientContract } from '@adonisjs/lucid/types/database'
import type { PlayerStatsConfig, StatDefinition } from '#config/player_stats'

const TABLE = 'player_stats'

export interface LevelInfo {
  level: number
  /** xp dentro del nivel actual. */
  current: number
  /** xp que cuesta el nivel actual completo (0 en el nivel máximo). */
  needed: number
  /** 0..1 */
  progress: number
}

/** Lo que recibe el cliente por cada stat (definición + valor actual). */
export interface StatView {
  key: string
  label: string
  kind: StatDefinition['kind']
  value: number
  min: number
  max: number | null
  hud: boolean
  order: number
  icon: string
  color: string
  level?: LevelInfo
}

interface StatRow {
  key: string
  value: number
  updated_at: Date
}

/**
 * Stats del jugador (hambre, experiencia, dinero…). El servidor es la fuente
 * de verdad; ver config/player_stats.ts para el catálogo y las reglas.
 */
export class PlayerStatsService {
  #byKey: Map<string, StatDefinition>

  constructor(private config: PlayerStatsConfig) {
    this.#byKey = new Map(config.stats.map((s) => [s.key, s]))
  }

  get heartbeatInterval() {
    return this.config.heartbeat.intervalSeconds
  }

  definition(key: string) {
    return this.#byKey.get(key)
  }

  /** Todos los stats del jugador (los que no tienen fila valen lo inicial). */
  async snapshot(userId: number, client: TransactionClientContract | typeof db = db) {
    const rows = (await client.from(TABLE).where('user_id', userId)) as StatRow[]
    const values = new Map(rows.map((r) => [r.key, Number(r.value)]))
    return this.config.stats
      .map((def) => this.#view(def, values.get(def.key) ?? def.initial))
      .sort((a, b) => a.order - b.order)
  }

  /**
   * Latido del juego (cada ~60 s mientras se juega): aplica el desgaste de los
   * stats con decayPerMinute según el tiempo jugado desde el último cambio,
   * con tope maxGapSeconds (el tiempo desconectado no cuenta).
   */
  async heartbeat(userId: number) {
    const decaying = this.config.stats.filter((s) => s.decayPerMinute)
    return db.transaction(async (trx) => {
      const rows = (await trx
        .from(TABLE)
        .where('user_id', userId)
        .whereIn(
          'key',
          decaying.map((s) => s.key)
        )
        .forUpdate()) as StatRow[]
      const byKey = new Map(rows.map((r) => [r.key, r]))
      const now = new Date()
      for (const def of decaying) {
        const row = byKey.get(def.key)
        let value = def.initial
        if (row) {
          const elapsed = Math.min(
            (now.getTime() - new Date(row.updated_at).getTime()) / 1000,
            this.config.heartbeat.maxGapSeconds
          )
          value = Number(row.value) - (def.decayPerMinute! * Math.max(elapsed, 0)) / 60
        }
        await this.#write(trx, userId, def, value, now)
      }
      return this.snapshot(userId, trx)
    })
  }

  /** Suma (o resta) a un stat, respetando sus límites. Devuelve el valor nuevo. */
  async add(userId: number, key: string, delta: number) {
    const def = this.#require(key)
    return db.transaction(async (trx) => {
      const row = (await trx
        .from(TABLE)
        .where({ user_id: userId, key })
        .forUpdate()
        .first()) as StatRow | null
      const current = row ? Number(row.value) : def.initial
      return this.#write(trx, userId, def, current + delta, new Date())
    })
  }

  /** Fija un stat a un valor (herramientas de desarrollo, ajustes de admin). */
  async set(userId: number, key: string, value: number) {
    const def = this.#require(key)
    return db.transaction((trx) => this.#write(trx, userId, def, value, new Date()))
  }

  async #write(
    trx: TransactionClientContract,
    userId: number,
    def: StatDefinition,
    raw: number,
    now: Date
  ) {
    const value = this.clamp(def, raw)
    await trx
      .insertQuery()
      .table(TABLE)
      .insert({ user_id: userId, key: def.key, value, updated_at: now })
      .knexQuery.onConflict(['user_id', 'key'])
      .merge(['value', 'updated_at'])
    return value
  }

  clamp(def: StatDefinition, raw: number) {
    let value = Number.isFinite(raw) ? raw : def.initial
    if (def.integer) value = Math.round(value)
    value = Math.max(def.min, value)
    if (def.max !== null) value = Math.min(def.max, value)
    return value
  }

  #require(key: string) {
    const def = this.#byKey.get(key)
    if (!def) throw new Error(`Stat desconocido: ${key}`)
    return def
  }

  #view(def: StatDefinition, value: number): StatView {
    const view: StatView = {
      key: def.key,
      label: def.label,
      kind: def.kind,
      value: this.clamp(def, value),
      min: def.min,
      max: def.max,
      hud: def.hud,
      order: def.order,
      icon: def.icon,
      color: def.color,
    }
    if (def.kind === 'level') view.level = levelFromXp(view.value, this.config.levelCurve)
    return view
  }
}

/** Pasar del nivel N al N+1 cuesta round(base · N^exponent) de xp. */
export function levelFromXp(
  xp: number,
  curve: { base: number; exponent: number; maxLevel: number }
): LevelInfo {
  let level = 1
  let remaining = Math.max(0, Math.floor(xp))
  while (level < curve.maxLevel) {
    const cost = Math.round(curve.base * Math.pow(level, curve.exponent))
    if (remaining < cost)
      return { level, current: remaining, needed: cost, progress: remaining / cost }
    remaining -= cost
    level++
  }
  return { level, current: 0, needed: 0, progress: 1 }
}
