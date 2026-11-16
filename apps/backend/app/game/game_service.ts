import db from '@adonisjs/lucid/services/db'
import type { PlayerStatsConfig } from '#config/player_stats'
import { worldToLon } from '#map/geo'
import { type PlayerStatsService, type StatView } from '#services/player_stats_service'
import { ACHIEVEMENTS } from '#game/catalog/achievements'
import { ITEMS, ITEMS_BY_KEY, MAX_STACK, SELL_FRACTION } from '#game/catalog/items'
import { GATHER, placeProfile, type PlaceProfile } from '#game/catalog/places'
import { RECIPES, RECIPES_BY_KEY } from '#game/catalog/recipes'
import { RULES, SIGN_PHRASES } from '#game/catalog/rules'
import { NPCS, STORY } from '#game/catalog/story'
import { JobBoard, type JobView } from '#game/jobs'
import { Progress, itemName, type StoryView } from '#game/progress'
import { GameStore } from '#game/store'
import { Territory } from '#game/territory'
import {
  GameError,
  hash,
  hash01,
  randomInt,
  pick,
  type Ctx,
  type GameEvent,
  type Trx,
} from '#game/types'
import { WorldObjects, type ObjectView } from '#game/world_objects'
import type { PoiRef, WorldIndex, WorldPoi } from '#game/world_index'

/** Lo que el juego necesita del servidor en tiempo real (posiciones y avisos). */
export interface GameLinks {
  /** Celda global (con decimales) donde está el jugador, o null si no está en el mundo. */
  position(userId: number): { x: number; y: number } | null
  /** Avisa a un jugador conectado (logros, sectores…). */
  notify(userId: number, events: GameEvent[]): void
  /** Un objeto del mapa cambió: lo ven los jugadores de la zona. */
  broadcastObject(x: number, y: number, payload: object): void
}

const NO_LINKS: GameLinks = {
  position: () => null,
  notify: () => {},
  broadcastObject: () => {},
}

/** Lo que acompaña a la respuesta de toda acción: el jugador al día. */
export interface PlayerView {
  stats: StatView[]
  inventory: { items: Record<string, number>; slots: number }
  story: StoryView
  events: GameEvent[]
}

/**
 * Las mecánicas del juego: lugares (comprar, vender, trabajar), rebusque,
 * morral, fabricación, encargos, historia, territorio y objetos del mapa.
 *
 * El servidor es la única fuente de verdad. Cada acción corre en una
 * transacción con la fila de estado del jugador bloqueada, valida contra el
 * mapa real (WorldIndex) y contra la posición del jugador en el servidor en
 * tiempo real, y al final revisa logros e historia (Progress.finish).
 */
export class GameService {
  readonly store: GameStore
  readonly territory: Territory
  readonly progress: Progress
  readonly jobs: JobBoard
  readonly objects: WorldObjects
  #links: GameLinks = NO_LINKS

  constructor(
    statsConfig: PlayerStatsConfig,
    private stats: PlayerStatsService,
    readonly world: WorldIndex
  ) {
    this.store = new GameStore(statsConfig)
    this.territory = new Territory(this.store, world.chunkCells)
    this.progress = new Progress(this.store)
    this.jobs = new JobBoard(this.store, this.territory, this.progress, world)
    this.objects = new WorldObjects(this.store, this.territory, this.progress, world)
  }

  /** Conecta el tiempo real (lo hace el provider; en pruebas, un doble). */
  connect(links: GameLinks) {
    this.#links = links
  }

  // --- Catálogo y estado --------------------------------------------------------

  /** Todo lo que el cliente necesita para dibujar: no cambia durante la partida. */
  catalog() {
    return {
      items: ITEMS,
      recipes: RECIPES,
      achievements: ACHIEVEMENTS,
      npcs: NPCS,
      chapters: STORY.map((c) => ({ key: c.key, title: c.title, summary: c.summary, npc: c.npc })),
      ranks: RULES.territory.ranks,
      signPhrases: SIGN_PHRASES,
      rules: {
        nearCells: RULES.nearCells,
        sectorCells: this.territory.sectorCells,
        maxStack: MAX_STACK,
        ownPoints: RULES.territory.ownPoints,
      },
    }
  }

  /** Estado completo al entrar al mundo (y premio del día si toca). */
  async state(userId: number) {
    return this.#act(userId, async (ctx) => {
      await this.#daily(ctx)
      await this.store.setCounter(ctx, 'level', await this.store.level(ctx.trx, userId), true)
      const friends = await ctx.trx
        .from('friendships')
        .where('status', 'accepted')
        .where((q) => q.where('requester_id', userId).orWhere('addressee_id', userId))
        .count('* as n')
      await this.store.setCounter(ctx, 'friends', Number(friends[0].n))
      const rows = await ctx.trx.from('player_achievements').where('user_id', userId).select('key')
      return {
        achievements: rows.map((r) => r.key as string),
        counters: await this.store.counters(ctx.trx, userId),
        jobs: await this.jobs.list(ctx, this.#links.position(userId)),
      }
    })
  }

  async #daily(ctx: Ctx) {
    const day = ctx.now.toISOString().slice(0, 10)
    const daily = ctx.state.daily
    if (daily.day === day) return
    const yesterday = new Date(ctx.now.getTime() - 86_400_000).toISOString().slice(0, 10)
    daily.streak = daily.day === yesterday ? daily.streak + 1 : 1
    daily.day = day
    const bonus = Math.min(RULES.daily.maxStreakBonus, RULES.daily.streakBonus * (daily.streak - 1))
    await this.store.count(ctx, 'days_played')
    await this.store.setCounter(ctx, 'streak_max', daily.streak, true)
    await this.progress.reward(
      ctx,
      { money: RULES.daily.money + bonus, xp: RULES.daily.xp },
      daily.streak > 1 ? `Día ${daily.streak} seguido en el barrio` : 'Bienvenido al barrio'
    )
  }

  /** El cliente ya mostró el diálogo de entrada del paso actual. */
  async storySeen(userId: number) {
    return this.#act(userId, async (ctx) => {
      ctx.state.story.introSeen = true
      return {}
    })
  }

  // --- Lugares -------------------------------------------------------------------

  /** Entrar a un lugar: lo descubre (la primera vez) y dice qué se puede hacer ahí. */
  async visit(userId: number, ref: PoiRef) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      await this.#discover(ctx, poi)
      return { place: await this.#placeView(ctx, poi) }
    })
  }

  async buy(userId: number, ref: PoiRef, item: string, qty: number) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      const profile = placeProfile(poi.kind, poi.cat)
      const discount = await this.#discount(ctx.trx, userId, poi)
      const offer = this.#stock(poi, profile, discount).find((s) => s.item === item)
      if (!offer) throw new GameError('not_sold', 'Aquí no venden eso.')
      const total = offer.price * qty
      await this.store.pay(ctx, total)
      await this.store.addItems(ctx.trx, userId, { [item]: qty })
      await this.store.count(ctx, 'purchases')
      await this.territory.gain(
        ctx,
        poi.x,
        poi.y,
        Math.min(RULES.buy.maxInfluence, total * RULES.buy.influencePerMoney)
      )
      ctx.events.push({
        type: 'toast',
        text: `Compraste ${qty} × ${itemName(item)} por $${total}.`,
      })
      return { place: await this.#placeView(ctx, poi) }
    })
  }

  async sell(userId: number, ref: PoiRef, item: string, qty: number) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      const profile = placeProfile(poi.kind, poi.cat)
      const price = this.#buyPrice(poi, profile, item)
      if (price <= 0) throw new GameError('not_bought', 'Aquí no compran eso.')
      await this.store.removeItems(ctx.trx, userId, { [item]: qty })
      await this.store.count(ctx, 'items_sold', qty)
      await this.progress.reward(ctx, { money: price * qty }, `Vendiste ${qty} × ${itemName(item)}`)
      return { place: await this.#placeView(ctx, poi) }
    })
  }

  /** Trabajar un turno en un lugar. */
  async work(userId: number, ref: PoiRef) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      const profile = placeProfile(poi.kind, poi.cat)
      if (!profile.work) throw new GameError('no_work', 'Aquí no dan trabajo.')
      await this.#discover(ctx, poi)
      const wait = await this.#workWait(ctx, poi)
      if (wait > 0) {
        throw new GameError('cooldown', `Aquí ya trabajaste. Vuelve en ${formatWait(wait)}.`)
      }
      const factor = await this.#hungryFactor(ctx)
      const [min, max] = profile.work.pay
      await ctx.trx
        .from('poi_visits')
        .where({ user_id: userId, poi_id: poi.id })
        .update({ last_work_at: ctx.now })
      ctx.state.cooldowns.work = ctx.now.getTime() + RULES.work.globalCooldownSeconds * 1000
      await this.store.addStat(ctx.trx, userId, 'hunger', -RULES.work.hunger)
      await this.store.count(ctx, 'work_shifts')
      await this.#countDayPart(ctx, poi.x)
      ctx.events.push({
        type: 'toast',
        text: profile.work.done + (factor < 1 ? ' Con hambre rindes la mitad.' : ''),
      })
      await this.progress.reward(
        ctx,
        { money: randomInt(min, max) * factor, xp: RULES.work.xp },
        profile.work.label
      )
      await this.territory.gain(ctx, poi.x, poi.y, RULES.work.influence)
      return { place: await this.#placeView(ctx, poi) }
    })
  }

  /** Servicios de un lugar: estudiar, entrenar, hacer el recorrido… */
  async service(userId: number, ref: PoiRef, key: string) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      const profile = placeProfile(poi.kind, poi.cat)
      const service = profile.services?.find((s) => s.key === key)
      if (!service) throw new GameError('no_service', 'Aquí no ofrecen eso.')
      await this.#discover(ctx, poi)
      const cooldown = `svc:${poi.id}:${key}`
      const wait = (ctx.state.cooldowns[cooldown] ?? 0) - ctx.now.getTime()
      if (wait > 0) throw new GameError('cooldown', `Vuelve en ${formatWait(wait / 1000)}.`)
      await this.store.pay(ctx, service.cost)
      ctx.state.cooldowns[cooldown] = ctx.now.getTime() + service.cooldownHours * 3_600_000
      if (service.hunger) await this.store.addStat(ctx.trx, userId, 'hunger', -service.hunger)
      await this.store.count(ctx, service.counter)
      ctx.events.push({ type: 'toast', text: service.done })
      await this.progress.reward(ctx, { xp: service.xp }, service.label)
      await this.territory.gain(ctx, poi.x, poi.y, 2)
      return { place: await this.#placeView(ctx, poi) }
    })
  }

  // --- Rebusque, comida y fabricación ---------------------------------------------

  /** Rebuscar en un árbol, arbusto, banca… de la celda global (x, y). */
  async gather(userId: number, x: number, y: number) {
    return this.#act(userId, async (ctx) => {
      this.#requireNear(ctx, x + 0.5, y + 0.5, 4)
      const cell = await this.world.cell(x, y)
      const source = cell?.prop ? GATHER[cell.prop] : undefined
      if (!source) throw new GameError('nothing_here', 'Aquí no hay nada que rebuscar.')
      const last = await ctx.trx.from('harvests').where({ user_id: userId, x, y }).first()
      const readyAt = last ? new Date(last.at).getTime() + source.cooldownMinutes * 60_000 : 0
      if (readyAt > ctx.now.getTime()) {
        const wait = formatWait((readyAt - ctx.now.getTime()) / 1000)
        throw new GameError('cooldown', `Aquí ya rebuscaste. Vuelve en ${wait}.`)
      }
      const items: Record<string, number> = {}
      for (const drop of source.drops) {
        if (Math.random() < drop.chance) items[drop.item] = randomInt(drop.qty[0], drop.qty[1])
      }
      const coins =
        source.coins && Math.random() < source.coins.chance
          ? randomInt(source.coins.amount[0], source.coins.amount[1])
          : 0
      const total = Object.values(items).reduce((a, b) => a + b, 0)
      // Primero el morral: si no cabe, no se gasta el intento.
      if (total > 0) await this.store.addItems(ctx.trx, userId, items)
      await ctx.trx
        .insertQuery()
        .table('harvests')
        .insert({ user_id: userId, x, y, at: ctx.now })
        .knexQuery.onConflict(['user_id', 'x', 'y'])
        .merge(['at'])
      if (total === 0 && coins === 0) {
        ctx.events.push({ type: 'toast', text: source.empty })
        return { found: false }
      }
      await this.store.count(ctx, 'items_gathered', total)
      ctx.events.push({ type: 'toast', text: source.text })
      ctx.events.push({ type: 'reward', ...(total > 0 ? { items } : {}) })
      await this.progress.reward(ctx, { money: coins, xp: total * RULES.gather.xp })
      return { found: true }
    })
  }

  /** Usar un objeto del morral: por ahora, comer. */
  async use(userId: number, item: string) {
    return this.#act(userId, async (ctx) => {
      const def = ITEMS_BY_KEY.get(item)
      if (!def || def.kind !== 'food') throw new GameError('not_usable', 'Eso no se come.')
      const hunger = await this.store.stat(ctx.trx, userId, 'hunger')
      if (hunger >= 99) throw new GameError('not_hungry', 'Estás lleno. Guárdalo para más tarde.')
      await this.store.removeItems(ctx.trx, userId, { [item]: 1 })
      await this.store.addStat(ctx.trx, userId, 'hunger', def.hunger ?? 0)
      await this.store.count(ctx, 'food_eaten')
      ctx.events.push({
        type: 'toast',
        text: `Te comiste: ${def.name}. +${def.hunger} de energía.`,
      })
      return {}
    })
  }

  async craft(userId: number, recipeKey: string, times: number) {
    return this.#act(userId, async (ctx) => {
      const recipe = RECIPES_BY_KEY.get(recipeKey)
      if (!recipe) throw new GameError('unknown_recipe', 'Esa receta no existe.')
      const level = await this.store.level(ctx.trx, userId)
      if (level < recipe.level) {
        throw new GameError('low_level', `Necesitas ser nivel ${recipe.level} para fabricar eso.`)
      }
      const inventory = await this.store.inventory(ctx.trx, userId)
      if (recipe.tool && !inventory[recipe.tool]) {
        throw new GameError('no_tool', `Necesitas: ${itemName(recipe.tool)}.`)
      }
      if (recipe.station) {
        const station = await this.objects.nearest(ctx.trx, this.#position(userId), recipe.station)
        if (!station) {
          throw new GameError(
            'no_station',
            `Tienes que estar junto a una ${itemName(recipe.station).toLowerCase()} (tuya o de otro).`
          )
        }
        await this.territory.gainFor(
          ctx,
          Number(station.owner_id),
          Number(station.x),
          Number(station.y),
          RULES.craft.stationInfluence
        )
      }
      const inputs = Object.fromEntries(
        Object.entries(recipe.inputs).map(([key, qty]) => [key, qty * times])
      )
      const made = recipe.qty * times
      await this.store.removeItems(ctx.trx, userId, inputs)
      await this.store.addItems(ctx.trx, userId, { [recipe.output]: made })
      await this.store.count(ctx, 'items_crafted', made)
      await this.store.count(ctx, `crafted_${recipe.output}`, made)
      if (recipe.station === 'parrilla') await this.store.count(ctx, 'food_cooked', made)
      ctx.events.push({ type: 'reward', items: { [recipe.output]: made } })
      await this.progress.reward(
        ctx,
        { xp: recipe.xp * times },
        `Fabricaste: ${itemName(recipe.output)}`
      )
      return {}
    })
  }

  // --- Encargos ------------------------------------------------------------------

  async jobList(userId: number) {
    return this.#act(userId, async (ctx) => ({
      jobs: await this.jobs.list(ctx, this.#links.position(userId)),
    }))
  }

  async jobRefresh(userId: number) {
    return this.#act(userId, async (ctx) => ({
      jobs: await this.jobs.refresh(ctx, this.#position(userId)),
    }))
  }

  async jobAccept(userId: number, id: number) {
    return this.#act(userId, async (ctx) => {
      await this.jobs.accept(ctx, id)
      return { jobs: await this.jobs.list(ctx, this.#links.position(userId)) }
    })
  }

  async jobAbandon(userId: number, id: number) {
    return this.#act(userId, async (ctx) => {
      await this.jobs.abandon(ctx, id)
      return { jobs: await this.jobs.list(ctx, this.#links.position(userId)) }
    })
  }

  /** Cumplir en un lugar el paso de un encargo (recoger, entregar, pasar a mirar). */
  async jobStep(userId: number, id: number, ref: PoiRef) {
    return this.#act(userId, async (ctx) => {
      const poi = await this.#poiNear(ctx, ref)
      await this.#discover(ctx, poi)
      const done = await this.jobs.step(ctx, id, poi, await this.#hungryFactor(ctx))
      if (done) await this.#countDayPart(ctx, poi.x)
      return {
        jobs: await this.jobs.list(ctx, this.#links.position(userId)),
        place: await this.#placeView(ctx, poi),
      }
    })
  }

  // --- Historia ------------------------------------------------------------------

  /**
   * Hablar con el personaje de la historia: en un lugar de la categoría que
   * pide el paso o, si en la zona no hay ninguno, por teléfono (sin `ref`).
   */
  async storyTalk(userId: number, ref: PoiRef | null) {
    return this.#act(userId, async (ctx) => {
      let poi: WorldPoi | null = null
      if (ref) {
        poi = await this.#poiNear(ctx, ref)
        await this.#discover(ctx, poi)
      }
      const talk = this.progress.talkGoal(ctx.state, poi ? poi.cat : null)
      if (!talk) throw new GameError('no_talk', 'Aquí no hay nadie que te esté esperando.')
      if (!poi) {
        const position = this.#position(userId)
        const around = await this.world.poisAround(position.x, position.y, RULES.searchChunks)
        if (around.some((p) => talk.goal.cats.includes(p.cat))) {
          throw new GameError(
            'place_nearby',
            `${NPCS[talk.goal.npc].name} no contesta: está cerca. Búscalo en el mapa.`
          )
        }
      }
      ctx.state.story.talked.push(talk.index)
      ctx.events.push({ type: 'dialog', npc: talk.goal.npc, lines: talk.goal.lines })
      return poi ? { place: await this.#placeView(ctx, poi) } : {}
    })
  }

  // --- Territorio ----------------------------------------------------------------

  /** Sectores alrededor del jugador y la renta que tiene por cobrar. */
  async territoryView(userId: number, radius = 3) {
    const position = this.#position(userId)
    const [sx, sy] = this.territory.sectorOf(position.x, position.y)
    return db.transaction(async (trx) => {
      const state = await this.store.lockState(trx, userId, new Date())
      return {
        here: { sx, sy },
        sectors: await this.territory.around(trx, userId, sx, sy, radius),
        rent: await this.territory.rent(trx, userId, state.rentAt, Date.now()),
      }
    })
  }

  async collectRent(userId: number) {
    return this.#act(userId, async (ctx) => {
      const rent = await this.territory.rent(ctx.trx, userId, ctx.state.rentAt, ctx.now.getTime())
      if (rent.amount <= 0) {
        throw new GameError(
          'no_rent',
          rent.sectors === 0
            ? 'Todavía no dominas ningún sector.'
            : 'Aún no hay renta por cobrar. Vuelve más tarde.'
        )
      }
      ctx.state.rentAt = ctx.now.getTime()
      await this.progress.reward(ctx, { money: rent.amount }, 'Renta de tus sectores')
      return { rent: { ...rent, amount: 0 } }
    })
  }

  // --- Objetos del mapa ----------------------------------------------------------

  /** Objetos de un rectángulo de chunks (lectura: sin transacción del jugador). */
  async objectsIn(cx0: number, cy0: number, cx1: number, cy1: number): Promise<ObjectView[]> {
    return this.objects.list(cx0, cy0, cx1, cy1)
  }

  async placeObject(userId: number, item: string, x: number, y: number) {
    return this.#act(userId, async (ctx) => {
      this.#requireNear(ctx, x + 0.5, y + 0.5, 5)
      return { object: await this.objects.place(ctx, item, x, y) }
    })
  }

  async objectAction(userId: number, id: number, action: string, args: Record<string, unknown>) {
    return this.#act(userId, async (ctx) => {
      const row = await this.objects.find(ctx.trx, id)
      this.#requireNear(ctx, Number(row.x) + 0.5, Number(row.y) + 0.5)
      return this.objects.act(ctx, row, action, args)
    })
  }

  // --- Contadores desde el tiempo real ---------------------------------------------

  /** Suma a un contador (metros caminados, saludos, chat) y avisa si pasó algo. */
  async track(userId: number, key: string, delta: number) {
    const out = await this.#act(userId, async (ctx) => {
      await this.store.count(ctx, key, delta)
      return {}
    })
    if (out.events.length > 0) this.#links.notify(userId, out.events)
  }

  // --- Desarrollo ----------------------------------------------------------------

  /** Herramientas de desarrollo: dar objetos, influencia, o empezar de cero. */
  async dev(
    userId: number,
    action: string,
    args: { item?: string; qty?: number; points?: number }
  ) {
    if (action === 'reset') {
      await db.transaction(async (trx) => {
        for (const table of [
          'inventory_items',
          'player_counters',
          'player_state',
          'player_achievements',
          'poi_visits',
          'player_jobs',
          'sector_influence',
          'harvests',
          'player_stats',
        ]) {
          await trx.from(table).where('user_id', userId).delete()
        }
        await trx.from('world_objects').where('owner_id', userId).delete()
      })
      return this.state(userId)
    }
    return this.#act(userId, async (ctx) => {
      if (action === 'give' && args.item) {
        await this.store.addItems(ctx.trx, userId, { [args.item]: args.qty ?? 1 }, true)
      } else if (action === 'influence') {
        const position = this.#position(userId)
        await this.territory.gain(ctx, position.x, position.y, args.points ?? 100)
      } else if (action === 'skip') {
        // Salta el paso actual de la historia (para probar los siguientes).
        const step = STORY[ctx.state.story.chapter]?.steps[ctx.state.story.step]
        for (const [index, goal] of (step?.goals ?? []).entries()) {
          if (goal.type === 'talk') ctx.state.story.talked.push(index)
          else if (goal.type === 'counter') await this.store.count(ctx, goal.key, goal.count)
          else if (goal.type === 'total')
            await this.store.setCounter(ctx, goal.key, goal.count, true)
          else if (goal.type === 'have') {
            await this.store.addItems(ctx.trx, userId, { [goal.item]: goal.count }, true)
          } else if (goal.key === 'money') {
            await this.store.addStat(ctx.trx, userId, 'money', goal.count)
          } else await this.store.addStat(ctx.trx, userId, 'xp', 5000)
        }
      } else {
        throw new GameError('unknown_action', 'Acción de desarrollo desconocida.')
      }
      return {}
    })
  }

  // --- Interno -------------------------------------------------------------------

  /**
   * Corre una acción del jugador en una transacción (con su estado bloqueado),
   * revisa logros e historia y devuelve el resultado con el jugador al día.
   * Los avisos a otros jugadores salen después del commit.
   */
  async #act<T extends object>(
    userId: number,
    action: (ctx: Ctx) => Promise<T>
  ): Promise<T & PlayerView> {
    const { ctx, out } = await db.transaction(async (trx) => {
      const now = new Date()
      const context: Ctx = {
        trx,
        userId,
        now,
        state: await this.store.lockState(trx, userId, now),
        events: [],
        touched: new Set(),
        notices: [],
        objectChanges: [],
      }
      if (!context.state.story.started) {
        context.state.story.started = true
        await this.progress.start(context)
      }
      const result = await action(context)
      await this.progress.finish(context)
      await this.store.saveState(context)
      const inventory = await this.store.inventory(trx, userId)
      return {
        ctx: context,
        out: {
          ...result,
          stats: await this.stats.snapshot(userId, trx),
          inventory: { items: inventory, slots: this.store.slots(inventory) },
          story: await this.progress.view(trx, userId, context.state),
          events: context.events,
        },
      }
    })
    for (const notice of ctx.notices) this.#links.notify(notice.userId, notice.events)
    for (const change of ctx.objectChanges) {
      const payload =
        change.op === 'del'
          ? { t: 'obj', op: 'del', id: change.id }
          : { t: 'obj', op: 'put', o: await this.objects.view(change.id) }
      this.#links.broadcastObject(change.x, change.y, payload)
    }
    return out
  }

  #position(userId: number) {
    const position = this.#links.position(userId)
    if (!position) {
      throw new GameError('not_in_world', 'Tienes que estar en el mapa para hacer eso.', 409)
    }
    return position
  }

  #requireNear(ctx: Ctx, x: number, y: number, cells: number = RULES.nearCells) {
    const position = this.#position(ctx.userId)
    if (Math.hypot(position.x - x, position.y - y) > cells) {
      throw new GameError('too_far', 'Estás muy lejos. Acércate más.')
    }
  }

  async #poiNear(ctx: Ctx, ref: PoiRef) {
    const poi = await this.world.poi(ref)
    if (!poi) throw new GameError('unknown_place', 'Ese lugar no existe en el mapa.', 404)
    this.#requireNear(ctx, poi.x + 0.5, poi.y + 0.5)
    return poi
  }

  /** Primera visita a un lugar: experiencia, influencia y contadores. */
  async #discover(ctx: Ctx, poi: WorldPoi) {
    const seen = await ctx.trx
      .from('poi_visits')
      .where({ user_id: ctx.userId, poi_id: poi.id })
      .first()
    if (seen) return
    await ctx.trx
      .insertQuery()
      .table('poi_visits')
      .insert({ user_id: ctx.userId, poi_id: poi.id, cat: poi.cat, first_at: ctx.now })
    await this.store.count(ctx, 'pois_discovered')
    await this.store.count(ctx, `disc_${poi.cat}`)
    const cats = await ctx.trx
      .from('poi_visits')
      .where('user_id', ctx.userId)
      .countDistinct('cat as n')
    await this.store.setCounter(ctx, 'cats_discovered', Number(cats[0].n))
    ctx.events.push({ type: 'discover', name: poi.name, cat: poi.cat })
    await this.progress.reward(ctx, { xp: RULES.discover.xp }, 'Lugar nuevo')
    await this.territory.gain(ctx, poi.x, poi.y, RULES.discover.influence)
  }

  /** Descuento del jugador en un lugar según su rango en el sector. */
  async #discount(trx: Trx, userId: number, poi: WorldPoi) {
    const [sx, sy] = this.territory.sectorOf(poi.x, poi.y)
    const points = await this.territory.points(trx, userId, sx, sy)
    return RULES.territory.ranks[this.territory.rankOf(points)].discount
  }

  /**
   * Qué vende un lugar y a cuánto. Cada lugar ofrece una parte del surtido de
   * su perfil, con su propio precio: sale del hash de su id, así es estable.
   */
  #stock(poi: WorldPoi, profile: PlaceProfile, discount: number) {
    const all = profile.sells
    let offered = all.filter((item) => hash01(`${poi.id}:s:${item}`) < 0.78)
    if (offered.length < Math.min(2, all.length)) offered = all.slice(0, 2)
    return offered.map((item) => {
      const base = ITEMS_BY_KEY.get(item)!.price * (profile.markup ?? 1)
      const factor = 0.85 + 0.35 * hash01(`${poi.id}:p:${item}`)
      return { item, price: Math.max(1, Math.round(base * factor * (1 - discount))) }
    })
  }

  /** Cuánto paga un lugar por un objeto (0 = no lo compra). */
  #buyPrice(poi: WorldPoi, profile: PlaceProfile, item: string) {
    const def = ITEMS_BY_KEY.get(item)
    if (!def || profile.key === 'culto' || profile.key === 'banco') return 0
    let fraction = profile.wants[item] ?? SELL_FRACTION
    // Lo que el lugar mismo vende no lo recompra caro (no hay negocio redondo).
    if (profile.sells.includes(item)) fraction = Math.min(fraction, 0.5)
    const factor = 0.85 + 0.15 * hash01(`${poi.id}:b:${item}`)
    return Math.max(1, Math.floor(def.price * fraction * factor))
  }

  /** Segundos que faltan para poder trabajar en un lugar (0 = ya). */
  async #workWait(ctx: Ctx, poi: WorldPoi) {
    const nowMs = ctx.now.getTime()
    const visit = await ctx.trx
      .from('poi_visits')
      .where({ user_id: ctx.userId, poi_id: poi.id })
      .first()
    const local = visit?.last_work_at
      ? new Date(visit.last_work_at).getTime() + RULES.work.cooldownMinutes * 60_000
      : 0
    return Math.max(0, local - nowMs, (ctx.state.cooldowns.work ?? 0) - nowMs) / 1000
  }

  async #hungryFactor(ctx: Ctx) {
    return (await this.store.stat(ctx.trx, ctx.userId, 'hunger')) <= 0 ? RULES.hungryFactor : 1
  }

  /** Cuenta la acción como hecha de noche o al amanecer (hora solar del lugar). */
  async #countDayPart(ctx: Ctx, x: number) {
    const lon = worldToLon(x, this.world.cellZoom)
    const hour = (ctx.now.getUTCHours() + ctx.now.getUTCMinutes() / 60 + lon / 15 + 24) % 24
    if (hour >= 20 || hour < 5) await this.store.count(ctx, 'night_actions')
    else if (hour < 8) await this.store.count(ctx, 'early_actions')
  }

  async #placeView(ctx: Ctx, poi: WorldPoi) {
    const profile = placeProfile(poi.kind, poi.cat)
    const [sx, sy] = this.territory.sectorOf(poi.x, poi.y)
    const points = await this.territory.points(ctx.trx, ctx.userId, sx, sy)
    const rank = this.territory.rankOf(points)
    const discount = RULES.territory.ranks[rank].discount
    const inventory = await this.store.inventory(ctx.trx, ctx.userId)
    const nowMs = ctx.now.getTime()
    const talk = this.progress.talkGoal(ctx.state, poi.cat)
    return {
      poi: { id: poi.id, cx: poi.cx, cy: poi.cy, name: poi.name, cat: poi.cat, kind: poi.kind },
      label: profile.label,
      npc: {
        name: profile.names[hash(`${poi.id}:n`) % profile.names.length],
        role: profile.role,
        portrait: profile.portrait,
        greeting: pick(profile.greetings),
      },
      sector: {
        name: this.territory.name(sx, sy),
        points: Math.floor(points),
        rank,
        rankName: RULES.territory.ranks[rank].name,
        discount,
      },
      sells: this.#stock(poi, profile, discount),
      buys: Object.keys(inventory)
        .map((item) => ({ item, price: this.#buyPrice(poi, profile, item), qty: inventory[item] }))
        .filter((offer) => offer.price > 0),
      work: profile.work
        ? {
            label: profile.work.label,
            pay: profile.work.pay,
            wait: Math.ceil(await this.#workWait(ctx, poi)),
          }
        : null,
      services: (profile.services ?? []).map((service) => ({
        key: service.key,
        label: service.label,
        cost: service.cost,
        xp: service.xp,
        wait: Math.max(
          0,
          Math.ceil(((ctx.state.cooldowns[`svc:${poi.id}:${service.key}`] ?? 0) - nowMs) / 1000)
        ),
      })),
      jobSteps: await this.jobs.stepsAt(ctx, poi),
      talk: talk ? { npc: talk.goal.npc, text: talk.goal.text } : null,
    }
  }
}

/** "45 s", "8 min", "3 h". */
export function formatWait(seconds: number) {
  if (seconds < 90) return `${Math.max(1, Math.ceil(seconds))} s`
  if (seconds < 5400) return `${Math.ceil(seconds / 60)} min`
  return `${Math.ceil(seconds / 3600)} h`
}

export type { JobView }
