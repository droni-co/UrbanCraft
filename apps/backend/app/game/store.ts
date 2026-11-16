import type { PlayerStatsConfig, StatDefinition } from '#config/player_stats'
import { levelFromXp } from '#services/player_stats_service'
import { BASE_SLOTS, ITEMS_BY_KEY, MAX_STACK } from '#game/catalog/items'
import { GameError, newPlayerState, type Ctx, type PlayerState, type Trx } from '#game/types'

/**
 * Acceso a los datos del jugador dentro de una transacción: estado, morral,
 * contadores y stats. Sin reglas del juego (eso es GameService).
 */
export class GameStore {
  #stats: Map<string, StatDefinition>

  constructor(private statsConfig: PlayerStatsConfig) {
    this.#stats = new Map(statsConfig.stats.map((s) => [s.key, s]))
  }

  // --- Estado ------------------------------------------------------------------

  /** Carga el estado bloqueando la fila: las acciones de un jugador van en fila. */
  async lockState(trx: Trx, userId: number, now: Date): Promise<PlayerState> {
    await trx
      .insertQuery()
      .table('player_state')
      .insert({
        user_id: userId,
        data: JSON.stringify(newPlayerState(now.getTime())),
        updated_at: now,
      })
      .knexQuery.onConflict('user_id')
      .ignore()
    const row = await trx.from('player_state').where('user_id', userId).forUpdate().first()
    const data = typeof row.data === 'string' ? JSON.parse(row.data) : row.data
    return { ...newPlayerState(now.getTime()), ...data }
  }

  async saveState(ctx: Ctx) {
    const nowMs = ctx.now.getTime()
    for (const [key, until] of Object.entries(ctx.state.cooldowns)) {
      if (until <= nowMs) delete ctx.state.cooldowns[key]
    }
    await ctx.trx
      .from('player_state')
      .where('user_id', ctx.userId)
      .update({ data: JSON.stringify(ctx.state), updated_at: ctx.now })
  }

  // --- Morral ------------------------------------------------------------------

  async inventory(trx: Trx, userId: number): Promise<Record<string, number>> {
    const rows = await trx.from('inventory_items').where('user_id', userId).where('qty', '>', 0)
    return Object.fromEntries(rows.map((r) => [r.item, Number(r.qty)]))
  }

  /** Espacios del morral: los de base más los de canastas y morrales. */
  slots(inventory: Record<string, number>) {
    let slots = BASE_SLOTS
    for (const key of Object.keys(inventory)) slots += ITEMS_BY_KEY.get(key)?.slots ?? 0
    return slots
  }

  /**
   * Agrega objetos al morral. Falla si no caben (espacios o tope por espacio),
   * salvo con `force` (regalos de la historia: nunca se pierden).
   */
  async addItems(trx: Trx, userId: number, items: Record<string, number>, force = false) {
    const inventory = await this.inventory(trx, userId)
    const after = { ...inventory }
    for (const [key, qty] of Object.entries(items)) {
      if (!ITEMS_BY_KEY.has(key)) throw new GameError('unknown_item', 'Ese objeto no existe.')
      after[key] = (after[key] ?? 0) + qty
      if (!force && after[key] > MAX_STACK) {
        throw new GameError(
          'stack_full',
          `No te caben más de ${MAX_STACK} de ${ITEMS_BY_KEY.get(key)!.name}.`
        )
      }
    }
    if (!force && Object.keys(after).length > this.slots(after)) {
      throw new GameError('inventory_full', 'Tu morral está lleno.')
    }
    for (const [key, qty] of Object.entries(items)) {
      await trx.rawQuery(
        `INSERT INTO inventory_items (user_id, item, qty) VALUES (?, ?, ?)
         ON CONFLICT (user_id, item) DO UPDATE SET qty = inventory_items.qty + EXCLUDED.qty`,
        [userId, key, qty]
      )
    }
  }

  async removeItems(trx: Trx, userId: number, items: Record<string, number>) {
    const inventory = await this.inventory(trx, userId)
    for (const [key, qty] of Object.entries(items)) {
      if ((inventory[key] ?? 0) < qty) {
        const name = ITEMS_BY_KEY.get(key)?.name ?? key
        throw new GameError('missing_item', `Te falta: ${name} (${inventory[key] ?? 0}/${qty}).`)
      }
    }
    for (const [key, qty] of Object.entries(items)) {
      const left = inventory[key] - qty
      const query = trx.from('inventory_items').where({ user_id: userId, item: key })
      if (left > 0) await query.update({ qty: left })
      else await query.delete()
    }
  }

  // --- Contadores --------------------------------------------------------------

  async counters(trx: Trx, userId: number): Promise<Record<string, number>> {
    const rows = await trx.from('player_counters').where('user_id', userId)
    return Object.fromEntries(rows.map((r) => [r.key, Number(r.value)]))
  }

  /** Suma a un contador y lo marca para revisar logros e historia. */
  async count(ctx: Ctx, key: string, delta = 1) {
    if (delta === 0) return
    await ctx.trx.rawQuery(
      `INSERT INTO player_counters (user_id, key, value) VALUES (?, ?, ?)
       ON CONFLICT (user_id, key) DO UPDATE SET value = player_counters.value + EXCLUDED.value`,
      [ctx.userId, key, delta]
    )
    ctx.touched.add(key)
  }

  /** Fija un contador (medidas: nivel, sectores dominados…). */
  async setCounter(ctx: Ctx, key: string, value: number, onlyIfHigher = false) {
    await this.setCounterFor(ctx.trx, ctx.userId, key, value, onlyIfHigher)
    ctx.touched.add(key)
  }

  async setCounterFor(trx: Trx, userId: number, key: string, value: number, onlyIfHigher = false) {
    const merged = onlyIfHigher
      ? 'GREATEST(player_counters.value, EXCLUDED.value)'
      : 'EXCLUDED.value'
    await trx.rawQuery(
      `INSERT INTO player_counters (user_id, key, value) VALUES (?, ?, ?)
       ON CONFLICT (user_id, key) DO UPDATE SET value = ${merged}`,
      [userId, key, value]
    )
  }

  // --- Stats -------------------------------------------------------------------

  async stat(trx: Trx, userId: number, key: string) {
    const def = this.#stats.get(key)!
    const row = await trx.from('player_stats').where({ user_id: userId, key }).first()
    return row ? Number(row.value) : def.initial
  }

  /** Suma (o resta) a un stat respetando sus límites. Devuelve el valor nuevo. */
  async addStat(trx: Trx, userId: number, key: string, delta: number) {
    const def = this.#stats.get(key)!
    const row = await trx.from('player_stats').where({ user_id: userId, key }).forUpdate().first()
    let value = (row ? Number(row.value) : def.initial) + delta
    if (def.integer) value = Math.round(value)
    value = Math.max(def.min, value)
    if (def.max !== null) value = Math.min(def.max, value)
    await trx
      .insertQuery()
      .table('player_stats')
      .insert({ user_id: userId, key, value, updated_at: new Date() })
      .knexQuery.onConflict(['user_id', 'key'])
      .merge(['value', 'updated_at'])
    return value
  }

  async level(trx: Trx, userId: number) {
    return levelFromXp(await this.stat(trx, userId, 'xp'), this.statsConfig.levelCurve).level
  }

  /** Cobra dinero; falla si no alcanza. */
  async pay(ctx: Ctx, amount: number) {
    if (amount <= 0) return
    const money = await this.stat(ctx.trx, ctx.userId, 'money')
    if (money < amount) {
      throw new GameError('no_money', `No te alcanza: cuesta $${amount} y tienes $${money}.`)
    }
    await this.addStat(ctx.trx, ctx.userId, 'money', -amount)
    await this.count(ctx, 'money_spent', amount)
  }
}
