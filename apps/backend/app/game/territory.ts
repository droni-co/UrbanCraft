import { RULES, SECTOR_NAMES } from '#game/catalog/rules'
import type { GameStore } from '#game/store'
import { hash, type Ctx, type Trx } from '#game/types'

const T = RULES.territory
const HALF_LIFE_SECONDS = T.halfLifeDays * 86_400

/** Puntos de una fila de sector_influence con el desgaste por inactividad aplicado. */
const EFFECTIVE = (alias: string) =>
  `(${alias}.points * power(0.5, EXTRACT(EPOCH FROM (now() - ${alias}.updated_at)) / ${HALF_LIFE_SECONDS}))`

/** Jugadores con bandera en un sector y su influencia, de mayor a menor. */
const FLAG_HOLDERS = `
  SELECT si.user_id, ${EFFECTIVE('si')} AS points
  FROM sector_influence si
  WHERE si.sx = ? AND si.sy = ?
    AND EXISTS (SELECT 1 FROM world_objects f
                WHERE f.kind = 'bandera' AND f.owner_id = si.user_id AND f.sx = si.sx AND f.sy = si.sy)
  ORDER BY points DESC, si.user_id ASC
  LIMIT 1`

export interface SectorView {
  sx: number
  sy: number
  name: string
  /** Tu influencia y tu rango ahí. */
  points: number
  rank: number
  /** Dueño actual (id y apodo), si lo hay. */
  owner: { id: number; name: string } | null
  mine: boolean
}

/**
 * Territorio: la ciudad se divide en sectores (cuadrados de sectorChunks chunks,
 * unos 300 m). Lo que un jugador hace en un sector le da influencia ahí; con
 * suficiente influencia y una bandera plantada, el sector es suyo mientras
 * nadie con bandera lo supere. La influencia se apaga si no se vuelve.
 */
export class Territory {
  constructor(
    private store: GameStore,
    private chunkCells: number
  ) {}

  get sectorCells() {
    return this.chunkCells * T.sectorChunks
  }

  sectorOf(x: number, y: number): [number, number] {
    return [Math.floor(x / this.sectorCells), Math.floor(y / this.sectorCells)]
  }

  /** Nombre del sector: estable y con algo de gracia. */
  name(sx: number, sy: number) {
    const h = hash(`${sx}:${sy}`)
    const first = SECTOR_NAMES.first[h % SECTOR_NAMES.first.length]
    const second = SECTOR_NAMES.second[(h >>> 8) % SECTOR_NAMES.second.length]
    return `${first} ${second}`
  }

  rankOf(points: number) {
    let rank = 0
    for (let i = 0; i < T.ranks.length; i++) if (points >= T.ranks[i].points) rank = i
    return rank
  }

  /** Influencia actual del jugador en un sector (con el desgaste aplicado). */
  async points(trx: Trx, userId: number, sx: number, sy: number) {
    const { rows } = await trx.rawQuery(
      `SELECT ${EFFECTIVE('si')} AS points FROM sector_influence si
       WHERE si.sx = ? AND si.sy = ? AND si.user_id = ?`,
      [sx, sy, userId]
    )
    return rows[0] ? Number(rows[0].points) : 0
  }

  async owner(trx: Trx, sx: number, sy: number): Promise<number | null> {
    const { rows } = await trx.rawQuery(FLAG_HOLDERS, [sx, sy])
    return rows[0] && Number(rows[0].points) >= T.ownPoints ? Number(rows[0].user_id) : null
  }

  /**
   * Da influencia al jugador de la acción en el sector de la celda (x, y).
   * Con bandera propia ahí rinde más. Avisa si sube de rango o gana el sector.
   */
  async gain(ctx: Ctx, x: number, y: number, amount: number) {
    if (amount <= 0) return
    const [sx, sy] = this.sectorOf(x, y)
    const before = await this.points(ctx.trx, ctx.userId, sx, sy)
    const ownerBefore = await this.owner(ctx.trx, sx, sy)
    const flag = await ctx.trx
      .from('world_objects')
      .where({ kind: 'bandera', owner_id: ctx.userId, sx, sy })
      .first()
    const after = before + amount * (flag ? T.flagBonus : 1)
    await this.#write(ctx.trx, ctx.userId, sx, sy, after)

    const rank = this.rankOf(after)
    if (rank > this.rankOf(before)) {
      ctx.events.push({
        type: 'sector',
        kind: 'rank',
        name: this.name(sx, sy),
        rank,
        rankName: T.ranks[rank].name,
      })
    }
    await this.#ownerChanged(ctx, sx, sy, ownerBefore)
    await this.refreshMetrics(ctx)
  }

  /** Quita influencia (al recoger un objeto del mapa). */
  async lose(ctx: Ctx, x: number, y: number, amount: number) {
    const [sx, sy] = this.sectorOf(x, y)
    const before = await this.points(ctx.trx, ctx.userId, sx, sy)
    if (before <= 0) return
    const ownerBefore = await this.owner(ctx.trx, sx, sy)
    await this.#write(ctx.trx, ctx.userId, sx, sy, Math.max(0, before - amount))
    await this.#ownerChanged(ctx, sx, sy, ownerBefore)
    await this.refreshMetrics(ctx)
  }

  /**
   * Influencia para otro jugador (alguien usó su parrilla, regó su matera…).
   * Sin eventos para quien hace la acción; el beneficiado ve su rango al entrar.
   */
  async gainFor(ctx: Ctx, userId: number, x: number, y: number, amount: number) {
    if (userId === ctx.userId) return this.gain(ctx, x, y, amount)
    const [sx, sy] = this.sectorOf(x, y)
    const ownerBefore = await this.owner(ctx.trx, sx, sy)
    const before = await this.points(ctx.trx, userId, sx, sy)
    await this.#write(ctx.trx, userId, sx, sy, before + amount)
    await this.#ownerChanged(ctx, sx, sy, ownerBefore)
    await this.#writeMetrics(ctx.trx, userId)
  }

  /** Revisa si cambió el dueño de un sector (tras mover influencia o banderas). */
  async checkOwner(ctx: Ctx, sx: number, sy: number, ownerBefore: number | null) {
    await this.#ownerChanged(ctx, sx, sy, ownerBefore)
    await this.refreshMetrics(ctx)
  }

  async #ownerChanged(ctx: Ctx, sx: number, sy: number, ownerBefore: number | null) {
    const ownerAfter = await this.owner(ctx.trx, sx, sy)
    if (ownerAfter === ownerBefore) return
    const name = this.name(sx, sy)
    for (const [userId, kind] of [
      [ownerAfter, 'owned'],
      [ownerBefore, 'lost'],
    ] as const) {
      if (userId === null) continue
      const event = { type: 'sector' as const, kind, name }
      if (userId === ctx.userId) ctx.events.push(event)
      else {
        ctx.notices.push({ userId, events: [event] })
        await this.#writeMetrics(ctx.trx, userId)
      }
    }
  }

  async #write(trx: Trx, userId: number, sx: number, sy: number, points: number) {
    await trx
      .insertQuery()
      .table('sector_influence')
      .insert({ sx, sy, user_id: userId, points, updated_at: new Date() })
      .knexQuery.onConflict(['sx', 'sy', 'user_id'])
      .merge(['points', 'updated_at'])
  }

  /** Medidas de territorio del jugador: sectores pisados, por rango y dominados. */
  async metrics(trx: Trx, userId: number) {
    const { rows } = await trx.rawQuery(
      `SELECT ${EFFECTIVE('si')} AS points,
         (EXISTS (SELECT 1 FROM world_objects f WHERE f.kind = 'bandera' AND f.owner_id = si.user_id
                  AND f.sx = si.sx AND f.sy = si.sy)
          AND NOT EXISTS (
            SELECT 1 FROM sector_influence o
            WHERE o.sx = si.sx AND o.sy = si.sy AND o.user_id <> si.user_id
              AND ${EFFECTIVE('o')} > ${EFFECTIVE('si')}
              AND EXISTS (SELECT 1 FROM world_objects g WHERE g.kind = 'bandera'
                          AND g.owner_id = o.user_id AND g.sx = o.sx AND g.sy = o.sy))) AS leads
       FROM sector_influence si WHERE si.user_id = ?`,
      [userId]
    )
    const out: Record<string, number> = {
      sectors_visited: 0,
      rank2_sectors: 0,
      rank3_sectors: 0,
      rank4_sectors: 0,
      rank5_sectors: 0,
      sectors_owned: 0,
    }
    for (const row of rows) {
      const points = Number(row.points)
      if (points >= 1) out.sectors_visited++
      const rank = this.rankOf(points)
      for (let r = 2; r <= 5; r++) if (rank >= r) out[`rank${r}_sectors`]++
      if (row.leads && points >= T.ownPoints) out.sectors_owned++
    }
    return out
  }

  /** Recalcula las medidas del jugador de la acción y las guarda como contadores. */
  async refreshMetrics(ctx: Ctx) {
    const metrics = await this.metrics(ctx.trx, ctx.userId)
    for (const [key, value] of Object.entries(metrics)) await this.store.setCounter(ctx, key, value)
  }

  async #writeMetrics(trx: Trx, userId: number) {
    const metrics = await this.metrics(trx, userId)
    for (const [key, value] of Object.entries(metrics)) {
      await this.store.setCounterFor(trx, userId, key, value)
    }
  }

  /** Sectores alrededor de (sx, sy) para el mapa de territorio. */
  async around(trx: Trx, userId: number, sx: number, sy: number, radius: number) {
    const { rows } = await trx.rawQuery(
      `SELECT si.sx, si.sy, si.user_id, u.nickname, ${EFFECTIVE('si')} AS points,
         EXISTS (SELECT 1 FROM world_objects f WHERE f.kind = 'bandera' AND f.owner_id = si.user_id
                 AND f.sx = si.sx AND f.sy = si.sy) AS flag
       FROM sector_influence si JOIN users u ON u.id = si.user_id
       WHERE si.sx BETWEEN ? AND ? AND si.sy BETWEEN ? AND ?`,
      [sx - radius, sx + radius, sy - radius, sy + radius]
    )
    const sectors = new Map<string, SectorView & { best: number }>()
    const get = (x: number, y: number) => {
      const key = `${x}:${y}`
      let sector = sectors.get(key)
      if (!sector) {
        sector = {
          sx: x,
          sy: y,
          name: this.name(x, y),
          points: 0,
          rank: 0,
          owner: null,
          mine: false,
          best: 0,
        }
        sectors.set(key, sector)
      }
      return sector
    }
    for (const row of rows) {
      const sector = get(Number(row.sx), Number(row.sy))
      const points = Number(row.points)
      if (Number(row.user_id) === userId) {
        sector.points = Math.floor(points)
        sector.rank = this.rankOf(points)
      }
      if (row.flag && points >= T.ownPoints && points > sector.best) {
        sector.best = points
        sector.owner = { id: Number(row.user_id), name: row.nickname ?? 'Jugador' }
        sector.mine = Number(row.user_id) === userId
      }
    }
    get(sx, sy) // el sector donde está el jugador siempre va
    return [...sectors.values()].map(({ best, ...sector }) => sector)
  }

  /** Renta acumulada de los sectores dominados (hasta maxDays días). */
  async rent(trx: Trx, userId: number, since: number, now: number) {
    const metrics = await this.metrics(trx, userId)
    if (metrics.sectors_owned === 0) return { sectors: 0, amount: 0, perDay: 0 }
    const { rows } = await trx.rawQuery(
      `SELECT count(*) AS n FROM world_objects w
       WHERE w.owner_id = ? AND w.kind <> 'bandera'
         AND EXISTS (SELECT 1 FROM world_objects f WHERE f.kind = 'bandera' AND f.owner_id = w.owner_id
                     AND f.sx = w.sx AND f.sy = w.sy)`,
      [userId]
    )
    const objects = Math.min(Number(rows[0].n), T.rent.maxObjects * metrics.sectors_owned)
    const perDay = metrics.sectors_owned * T.rent.perSector + objects * T.rent.perObject
    const days = Math.min((now - since) / 86_400_000, T.rent.maxDays)
    return { sectors: metrics.sectors_owned, amount: Math.floor(perDay * days), perDay }
  }
}
