import db from '@adonisjs/lucid/services/db'
import { ITEMS_BY_KEY } from '#game/catalog/items'
import { NO_BUILD_CATEGORIES } from '#game/catalog/places'
import { RULES, SIGN_PHRASES } from '#game/catalog/rules'
import { itemName, type Progress } from '#game/progress'
import type { GameStore } from '#game/store'
import type { Territory } from '#game/territory'
import { GameError, type Ctx, type Trx } from '#game/types'
import type { WorldIndex } from '#game/world_index'

const O = RULES.objects
const DAY_MS = 86_400_000

/** Lo que ven todos de un objeto del mapa. */
export interface ObjectView {
  id: number
  kind: string
  x: number
  y: number
  owner: number
  ownerName: string
  /** Estado público: etapa de la matera, frase del letrero, si el puesto tiene surtido… */
  state: Record<string, unknown>
}

interface Row {
  id: number | string
  owner_id: number
  kind: string
  x: number
  y: number
  sx: number
  sy: number
  state: any
  nickname?: string | null
}

/**
 * Objetos que los jugadores dejan en el mapa: materas, bancas, letreros,
 * cajas de trueque, puestos de venta, parrillas, mesas de trabajo, banderas y
 * faroles. Los ven y los usan todos. No estorban el paso (nadie puede encerrar
 * a otro) y los que su dueño abandona desaparecen solos.
 */
export class WorldObjects {
  constructor(
    private store: GameStore,
    private territory: Territory,
    private progress: Progress,
    private world: WorldIndex
  ) {}

  // --- Lectura -------------------------------------------------------------------

  async list(cx0: number, cy0: number, cx1: number, cy1: number): Promise<ObjectView[]> {
    await db
      .from('world_objects')
      .where('touched_at', '<', new Date(Date.now() - O.expireDays * DAY_MS))
      .whereBetween('cx', [cx0, cx1])
      .whereBetween('cy', [cy0, cy1])
      .delete()
    const rows = await db
      .from('world_objects as w')
      .join('users as u', 'u.id', 'w.owner_id')
      .whereBetween('w.cx', [cx0, cx1])
      .whereBetween('w.cy', [cy0, cy1])
      .select('w.*', 'u.nickname')
      .limit(2000)
    return rows.map((row) => this.#view(row))
  }

  async view(id: number): Promise<ObjectView | null> {
    const row = await db
      .from('world_objects as w')
      .join('users as u', 'u.id', 'w.owner_id')
      .where('w.id', id)
      .select('w.*', 'u.nickname')
      .first()
    return row ? this.#view(row) : null
  }

  async find(trx: Trx, id: number): Promise<Row> {
    const row = await trx
      .from('world_objects as w')
      .join('users as u', 'u.id', 'w.owner_id')
      .where('w.id', id)
      .select('w.*', 'u.nickname')
      .forUpdate('w')
      .first()
    if (!row) throw new GameError('unknown_object', 'Ese objeto ya no está.', 404)
    row.state = typeof row.state === 'string' ? JSON.parse(row.state) : row.state
    return row
  }

  /** Objeto de un tipo a mano del jugador (mesa de trabajo, parrilla). */
  async nearest(trx: Trx, position: { x: number; y: number }, kind: string) {
    const r = RULES.nearCells
    const rows = await trx
      .from('world_objects')
      .where('kind', kind)
      .whereBetween('x', [Math.floor(position.x - r), Math.ceil(position.x + r)])
      .whereBetween('y', [Math.floor(position.y - r), Math.ceil(position.y + r)])
    return (
      rows.find((row) => Math.hypot(row.x + 0.5 - position.x, row.y + 0.5 - position.y) <= r) ??
      null
    )
  }

  #view(row: Row): ObjectView {
    const state = typeof row.state === 'string' ? JSON.parse(row.state) : (row.state ?? {})
    const pub: Record<string, unknown> = {}
    switch (row.kind) {
      case 'matera':
        pub.stage = state.stage ?? 0
        break
      case 'letrero':
        pub.phrase = state.phrase ?? 0
        break
      case 'caja':
        pub.filled = Object.keys(state.items ?? {}).length > 0
        break
      case 'puesto':
        pub.open = Object.keys(state.stock ?? {}).length > 0
        break
    }
    return {
      id: Number(row.id),
      kind: row.kind,
      x: Number(row.x),
      y: Number(row.y),
      owner: Number(row.owner_id),
      ownerName: row.nickname ?? 'Jugador',
      state: pub,
    }
  }

  // --- Colocar y recoger ---------------------------------------------------------

  async place(ctx: Ctx, item: string, x: number, y: number): Promise<ObjectView> {
    const def = ITEMS_BY_KEY.get(item)
    if (!def?.object) throw new GameError('not_placeable', 'Eso no se puede poner en el mapa.')
    const cell = await this.world.cell(x, y)
    if (!cell) throw new GameError('no_map', 'Esa zona todavía no está cargada.')
    if (!cell.buildable) {
      throw new GameError(
        'bad_cell',
        'Ahí no se puede: busca un andén o zona verde libre (no en la calle ni encima de algo).'
      )
    }
    const [cx, cy] = this.world.chunkOf(x, y)
    const [sx, sy] = this.territory.sectorOf(x, y)

    const taken = await ctx.trx.from('world_objects').where({ x, y }).first()
    if (taken) throw new GameError('cell_taken', 'Ahí ya hay algo puesto.')

    const pois = await this.world.poisAround(x, y, 1)
    for (const poi of pois) {
      const distance = Math.hypot(poi.x - x, poi.y - y)
      if (distance < 1) throw new GameError('bad_cell', 'Ahí queda la entrada de un lugar.')
      if (NO_BUILD_CATEGORIES.has(poi.cat) && distance <= O.respectCells) {
        throw new GameError('bad_cell', `Muy cerca de ${poi.name}. Deja ese espacio libre.`)
      }
    }

    const mine = await ctx.trx.from('world_objects').where('owner_id', ctx.userId).count('* as n')
    const level = await this.store.level(ctx.trx, ctx.userId)
    const limit = Math.min(O.perPlayer.max, O.perPlayer.base + O.perPlayer.perLevel * level)
    if (Number(mine[0].n) >= limit) {
      throw new GameError(
        'too_many_objects',
        `Ya tienes ${limit} objetos en el mapa (sube de nivel para poner más, o recoge alguno).`
      )
    }
    const inChunk = await ctx.trx.from('world_objects').where({ cx, cy }).count('* as n')
    if (Number(inChunk[0].n) >= O.perChunk) {
      throw new GameError('chunk_full', 'Esta cuadra ya está muy llena. Prueba más allá.')
    }
    if (def.object === 'bandera') {
      const flag = await ctx.trx
        .from('world_objects')
        .where({ kind: 'bandera', owner_id: ctx.userId, sx, sy })
        .first()
      if (flag) throw new GameError('flag_exists', 'Ya tienes una bandera en este sector.')
    }

    await this.store.removeItems(ctx.trx, ctx.userId, { [item]: 1 })
    const ownerBefore = await this.territory.owner(ctx.trx, sx, sy)
    const inserted = await ctx.trx
      .insertQuery()
      .table('world_objects')
      .insert({
        owner_id: ctx.userId,
        kind: def.object,
        x,
        y,
        cx,
        cy,
        sx,
        sy,
        state: JSON.stringify(initialState(def.object)),
        created_at: ctx.now,
        touched_at: ctx.now,
      })
      .returning('id')
    const id = Number(inserted[0].id ?? inserted[0])
    await this.store.count(ctx, 'objects_placed')
    await this.store.count(ctx, `placed_${def.object}`)
    await this.territory.gain(ctx, x, y, def.influence ?? O.influence)
    if (def.object === 'bandera') await this.territory.checkOwner(ctx, sx, sy, ownerBefore)
    ctx.objectChanges.push({ op: 'put', id, x, y })
    ctx.events.push({ type: 'toast', text: `Pusiste: ${def.name}.` })
    const row = await this.find(ctx.trx, id)
    return this.#view(row)
  }

  async #pickup(ctx: Ctx, row: Row) {
    this.#owner(ctx, row)
    const state = row.state ?? {}
    if (Object.keys(state.items ?? {}).length > 0 || Object.keys(state.stock ?? {}).length > 0) {
      throw new GameError('not_empty', 'Primero vacíalo.')
    }
    if ((state.till ?? 0) > 0)
      throw new GameError('not_empty', 'Primero recoge la plata de la caja.')
    await this.store.addItems(ctx.trx, ctx.userId, { [row.kind]: 1 })
    const ownerBefore = await this.territory.owner(ctx.trx, row.sx, row.sy)
    await ctx.trx.from('world_objects').where('id', row.id).delete()
    await this.territory.lose(
      ctx,
      row.x,
      row.y,
      ITEMS_BY_KEY.get(row.kind)?.influence ?? O.influence
    )
    if (row.kind === 'bandera') await this.territory.checkOwner(ctx, row.sx, row.sy, ownerBefore)
    ctx.objectChanges.push({ op: 'del', id: Number(row.id), x: row.x, y: row.y })
    ctx.events.push({ type: 'toast', text: `Recogiste: ${itemName(row.kind)}.` })
    return { removed: true }
  }

  // --- Acciones ------------------------------------------------------------------

  /** Usa un objeto. Cada tipo tiene sus acciones; "look" y "pickup" valen para todos. */
  async act(ctx: Ctx, row: Row, action: string, args: Record<string, unknown>) {
    const isOwner = row.owner_id === ctx.userId
    if (action === 'pickup') return this.#pickup(ctx, row)
    if (isOwner) {
      await ctx.trx.from('world_objects').where('id', row.id).update({ touched_at: ctx.now })
    }
    let message = ''
    switch (`${row.kind}:${action}`) {
      case 'matera:water':
        message = await this.#water(ctx, row)
        break
      case 'matera:pick':
        message = await this.#pickFlower(ctx, row)
        break
      case 'letrero:set': {
        this.#owner(ctx, row)
        const phrase = Number(args.phrase)
        if (!Number.isInteger(phrase) || phrase < 0 || phrase >= SIGN_PHRASES.length) {
          throw new GameError('bad_phrase', 'Esa frase no existe.')
        }
        row.state.phrase = phrase
        await this.#save(ctx, row)
        break
      }
      case 'caja:put':
        await this.#boxPut(ctx, row, String(args.item), int(args.qty))
        break
      case 'caja:take':
        await this.#boxTake(ctx, row, String(args.item), int(args.qty))
        break
      case 'puesto:stock':
        await this.#stallStock(ctx, row, String(args.item), int(args.qty), int(args.price))
        break
      case 'puesto:unstock':
        await this.#stallUnstock(ctx, row, String(args.item))
        break
      case 'puesto:buy':
        await this.#stallBuy(ctx, row, String(args.item), int(args.qty))
        break
      case 'puesto:collect':
        await this.#stallCollect(ctx, row)
        break
      default:
        if (action !== 'look')
          throw new GameError('bad_action', 'Eso no se puede hacer con este objeto.')
    }
    if (row.kind === 'puesto') await this.#stallSimulate(ctx, row)
    return {
      object: this.#view(row),
      detail: this.#detail(ctx, row),
      ...(message ? { message } : {}),
    }
  }

  /** Lo que ve quien abre el objeto (contenido de la caja, surtido del puesto…). */
  #detail(ctx: Ctx, row: Row) {
    const isOwner = row.owner_id === ctx.userId
    const state = row.state ?? {}
    const nowMs = ctx.now.getTime()
    const detail: Record<string, unknown> = { isOwner }
    switch (row.kind) {
      case 'matera': {
        const watered = (state.w ?? {})[ctx.userId] ?? 0
        const picked = (state.p ?? {})[ctx.userId] ?? 0
        detail.stage = state.stage ?? 0
        detail.canWater = nowMs - watered >= O.matera.waterHours * 3_600_000
        detail.canPick =
          (state.stage ?? 0) >= 2 && nowMs - picked >= O.matera.flowerHours * 3_600_000
        break
      }
      case 'letrero':
        detail.phrase = state.phrase ?? 0
        break
      case 'caja':
        detail.items = state.items ?? {}
        detail.stacks = O.caja.stacks
        break
      case 'puesto':
        detail.stock = Object.entries(state.stock ?? {}).map(([item, s]: [string, any]) => ({
          item,
          qty: s.n,
          price: s.p,
        }))
        detail.products = O.puesto.products
        if (isOwner) detail.till = state.till ?? 0
        break
    }
    return detail
  }

  #owner(ctx: Ctx, row: Row) {
    if (row.owner_id !== ctx.userId) {
      throw new GameError('not_owner', `Eso es de ${row.nickname ?? 'otro jugador'}.`, 403)
    }
  }

  async #save(ctx: Ctx, row: Row) {
    await ctx.trx
      .from('world_objects')
      .where('id', row.id)
      .update({ state: JSON.stringify(row.state) })
    ctx.objectChanges.push({ op: 'put', id: Number(row.id), x: row.x, y: row.y })
  }

  // Matera: cualquiera la riega (una vez al día cada uno). Con dos riegos
  // florece, y entonces cada jugador puede llevarse una flor al día.
  async #water(ctx: Ctx, row: Row) {
    const state = row.state
    const nowMs = ctx.now.getTime()
    state.w = prune(state.w, nowMs, O.matera.waterHours * 3_600_000)
    if (state.w[ctx.userId])
      throw new GameError('cooldown', 'Ya la regaste hoy. Tampoco la ahogues.')
    state.w[ctx.userId] = nowMs
    state.stage = Math.min(2, (state.stage ?? 0) + 1)
    await this.#save(ctx, row)
    await this.store.count(ctx, 'waterings')
    await this.progress.reward(ctx, { xp: O.matera.waterXp }, 'Regaste una matera')
    await this.territory.gainFor(ctx, row.owner_id, row.x, row.y, O.matera.ownerInfluence)
    return state.stage >= 2 ? '¡Floreció!' : 'Ya le salieron brotes.'
  }

  async #pickFlower(ctx: Ctx, row: Row) {
    const state = row.state
    const nowMs = ctx.now.getTime()
    if ((state.stage ?? 0) < 2)
      throw new GameError('not_ready', 'Todavía no ha florecido. Riégala.')
    state.p = prune(state.p, nowMs, O.matera.flowerHours * 3_600_000)
    if (state.p[ctx.userId]) throw new GameError('cooldown', 'Hoy ya te llevaste una flor de aquí.')
    await this.store.addItems(ctx.trx, ctx.userId, { flor: 1 })
    state.p[ctx.userId] = nowMs
    await this.#save(ctx, row)
    ctx.events.push({ type: 'reward', items: { flor: 1 } })
    return 'Te llevaste una flor.'
  }

  // Caja de trueque: cualquiera deja y cualquiera se lleva (con tope al día).
  async #boxPut(ctx: Ctx, row: Row, item: string, qty: number) {
    const items: Record<string, number> = (row.state.items ??= {})
    if (!ITEMS_BY_KEY.has(item)) throw new GameError('unknown_item', 'Ese objeto no existe.')
    if (!(item in items) && Object.keys(items).length >= O.caja.stacks) {
      throw new GameError('box_full', 'La caja está llena.')
    }
    if ((items[item] ?? 0) + qty > O.caja.stack) {
      throw new GameError('box_full', `No caben más de ${O.caja.stack} de lo mismo.`)
    }
    await this.store.removeItems(ctx.trx, ctx.userId, { [item]: qty })
    items[item] = (items[item] ?? 0) + qty
    await this.#save(ctx, row)
    await this.store.count(ctx, 'trueque_dejados', qty)
    if (row.owner_id !== ctx.userId)
      await this.territory.gainFor(ctx, row.owner_id, row.x, row.y, 1)
  }

  async #boxTake(ctx: Ctx, row: Row, item: string, qty: number) {
    const state = row.state
    const items: Record<string, number> = (state.items ??= {})
    if ((items[item] ?? 0) < qty) throw new GameError('missing_item', 'Ya no queda de eso.')
    if (row.owner_id !== ctx.userId) {
      const nowMs = ctx.now.getTime()
      const takes: number[] = ((state.t ??= {})[ctx.userId] ?? []).filter(
        (at: number) => nowMs - at < DAY_MS
      )
      if (takes.length >= O.caja.takesPerDay) {
        throw new GameError(
          'cooldown',
          'Hoy ya sacaste bastante de esta caja. Deja para los demás.'
        )
      }
      takes.push(nowMs)
      state.t[ctx.userId] = takes
    }
    await this.store.addItems(ctx.trx, ctx.userId, { [item]: qty })
    items[item] -= qty
    if (items[item] <= 0) delete items[item]
    await this.#save(ctx, row)
    await this.store.count(ctx, 'trueque_tomados', qty)
    ctx.events.push({ type: 'reward', items: { [item]: qty } })
  }

  // Puesto de venta: el dueño surte y pone precios; compran los demás
  // jugadores y, con el tiempo, la gente del barrio (#stallSimulate).
  async #stallStock(ctx: Ctx, row: Row, item: string, qty: number, price: number) {
    this.#owner(ctx, row)
    const def = ITEMS_BY_KEY.get(item)
    if (!def) throw new GameError('unknown_item', 'Ese objeto no existe.')
    const stock: Record<string, { n: number; p: number }> = (row.state.stock ??= {})
    if (!(item in stock) && Object.keys(stock).length >= O.puesto.products) {
      throw new GameError(
        'stall_full',
        `El puesto solo aguanta ${O.puesto.products} productos distintos.`
      )
    }
    if ((stock[item]?.n ?? 0) + qty > O.puesto.stack) {
      throw new GameError('stall_full', `No caben más de ${O.puesto.stack} de lo mismo.`)
    }
    const max = Math.max(1, def.price * O.puesto.maxPriceFactor)
    if (price < 1 || price > max) {
      throw new GameError('bad_price', `El precio debe estar entre $1 y $${max}.`)
    }
    await this.store.removeItems(ctx.trx, ctx.userId, { [item]: qty })
    stock[item] = { n: (stock[item]?.n ?? 0) + qty, p: price }
    row.state.simAt ??= ctx.now.getTime()
    await this.#save(ctx, row)
  }

  async #stallUnstock(ctx: Ctx, row: Row, item: string) {
    this.#owner(ctx, row)
    const stock = row.state.stock ?? {}
    if (!stock[item]) throw new GameError('missing_item', 'Eso no está en el puesto.')
    await this.store.addItems(ctx.trx, ctx.userId, { [item]: stock[item].n })
    delete stock[item]
    await this.#save(ctx, row)
  }

  async #stallBuy(ctx: Ctx, row: Row, item: string, qty: number) {
    if (row.owner_id === ctx.userId)
      throw new GameError('own_stall', 'Es tu puesto: retira el producto.')
    const stock = row.state.stock ?? {}
    const entry = stock[item]
    if (!entry || entry.n < qty) throw new GameError('missing_item', 'Ya no queda de eso.')
    const total = entry.p * qty
    await this.store.pay(ctx, total)
    await this.store.addItems(ctx.trx, ctx.userId, { [item]: qty })
    entry.n -= qty
    if (entry.n <= 0) delete stock[item]
    row.state.till = (row.state.till ?? 0) + total
    row.state.sold = (row.state.sold ?? 0) + qty
    await this.#save(ctx, row)
    await this.store.count(ctx, 'purchases')
    ctx.events.push({ type: 'toast', text: `Compraste ${qty} × ${itemName(item)} por $${total}.` })
    ctx.notices.push({
      userId: row.owner_id,
      events: [{ type: 'toast', text: `Vendiste ${qty} × ${itemName(item)} en tu puesto.` }],
    })
  }

  async #stallCollect(ctx: Ctx, row: Row) {
    this.#owner(ctx, row)
    await this.#stallSimulate(ctx, row)
    const till = row.state.till ?? 0
    const sold = row.state.sold ?? 0
    if (till <= 0) throw new GameError('empty_till', 'Todavía no hay plata en la caja.')
    row.state.till = 0
    row.state.sold = 0
    await this.#save(ctx, row)
    await this.store.count(ctx, 'stall_income', till)
    await this.store.count(ctx, 'stall_sales', sold)
    await this.progress.reward(ctx, { money: till }, 'Ventas de tu puesto')
    await this.territory.gain(ctx, row.x, row.y, Math.min(10, sold * 0.5))
  }

  /**
   * Clientes del barrio: desde la última vez que alguien miró el puesto, cada
   * saleMinutes pasa un cliente y puede llevarse una unidad. Compra más fácil
   * lo barato (respecto al precio base) y casi nunca lo carísimo.
   */
  async #stallSimulate(ctx: Ctx, row: Row) {
    const state = row.state
    const stock: Record<string, { n: number; p: number }> = state.stock ?? {}
    const nowMs = ctx.now.getTime()
    const step = O.puesto.saleMinutes * 60_000
    const since = state.simAt ?? nowMs
    const visits = Math.min(O.puesto.maxSalesPerVisit, Math.floor((nowMs - since) / step))
    if (visits <= 0) return
    state.simAt = visits === O.puesto.maxSalesPerVisit ? nowMs : since + visits * step
    let changed = false
    for (let i = 0; i < visits; i++) {
      const items = Object.keys(stock)
      if (items.length === 0) break
      const item = items[Math.floor(Math.random() * items.length)]
      const ratio = stock[item].p / Math.max(1, ITEMS_BY_KEY.get(item)!.price)
      // Al precio base compra 7 de cada 10; al doble, 1 de cada 4; a más del triple, nadie.
      const chance = Math.max(0, Math.min(0.95, 1.15 - 0.45 * ratio))
      if (Math.random() >= chance) continue
      stock[item].n--
      state.till = (state.till ?? 0) + stock[item].p
      state.sold = (state.sold ?? 0) + 1
      if (stock[item].n <= 0) delete stock[item]
      changed = true
    }
    state.stock = stock
    await ctx.trx
      .from('world_objects')
      .where('id', row.id)
      .update({ state: JSON.stringify(state) })
    if (changed) ctx.objectChanges.push({ op: 'put', id: Number(row.id), x: row.x, y: row.y })
  }
}

function initialState(kind: string): Record<string, unknown> {
  switch (kind) {
    case 'matera':
      return { stage: 0 }
    case 'letrero':
      return { phrase: 0 }
    case 'caja':
      return { items: {} }
    case 'puesto':
      return { stock: {}, till: 0 }
    default:
      return {}
  }
}

/** Quita de un registro usuario → momento los que ya vencieron. */
function prune(record: Record<string, number> | undefined, nowMs: number, ttlMs: number) {
  const out: Record<string, number> = {}
  for (const [key, at] of Object.entries(record ?? {})) if (nowMs - at < ttlMs) out[key] = at
  return out
}

function int(value: unknown) {
  const n = Number(value)
  if (!Number.isInteger(n) || n < 1 || n > 100_000) {
    throw new GameError('bad_number', 'Cantidad inválida.')
  }
  return n
}
