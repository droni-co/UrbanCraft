import { ITEMS_BY_KEY } from '#game/catalog/items'
import { placeProfile } from '#game/catalog/places'
import { RULES } from '#game/catalog/rules'
import { itemName, type Progress } from '#game/progress'
import type { GameStore } from '#game/store'
import type { Territory } from '#game/territory'
import { GameError, pick, randomInt, type Ctx } from '#game/types'
import type { WorldIndex, WorldPoi } from '#game/world_index'

const J = RULES.jobs

type StepType = 'pickup' | 'deliver' | 'bring' | 'visit'

interface JobStep {
  type: StepType
  poi: { id: string; cx: number; cy: number; x: number; y: number; name: string; cat: string }
  item?: string
  qty?: number
  done: boolean
}

interface JobData {
  title: string
  text: string
  steps: JobStep[]
  reward: { money: number; xp: number }
}

export interface JobView extends JobData {
  id: number
  kind: string
  status: 'offered' | 'active'
  /** Segundos hasta que caduca. */
  expiresIn: number
}

/** Cosas que la gente manda a pedir (mandados). */
const ERRANDS: { item: string; qty: [number, number] }[] = [
  { item: 'fruta', qty: [2, 3] },
  { item: 'pan', qty: [2, 4] },
  { item: 'tinto', qty: [1, 2] },
  { item: 'agua', qty: [2, 3] },
  { item: 'empanada', qty: [2, 3] },
  { item: 'palo', qty: [4, 6] },
  { item: 'hoja', qty: [5, 8] },
  { item: 'semilla', qty: [2, 3] },
  { item: 'botella', qty: [2, 3] },
  { item: 'flor', qty: [1, 2] },
  { item: 'chocolatina', qty: [2, 3] },
]

const DELIVERY_TEXTS = [
  'Pidieron esto hace rato y ya están llamando. Vuele, pero no lo riegue.',
  'Frágil. Bueno, no tanto. Pero llévelo como si lo fuera.',
  'El cliente es de los que cuentan los minutos. No le dé ese gusto.',
  'Es una sorpresa. Para ellos y para mí, porque no sé qué hay adentro.',
]
const ERRAND_TEXTS = [
  'Se nos acabó y la gente pregunta. ¿Me colabora?',
  'No puedo salir del mostrador. Consígalo donde sea, yo no pregunto.',
  'Lo necesito para hoy. Bueno, para ayer, pero hoy sirve.',
]
const TOUR_TEXTS = [
  'Dese una vuelta por estos sitios y me cuenta cómo está la cosa.',
  'Quiero saber si siguen abiertos. No es chisme, es investigación.',
  'Vaya, salude y vuelva. Lo llaman relaciones públicas.',
]

/**
 * Encargos: trabajos cortos que el servidor arma con los lugares reales que
 * hay cerca del jugador (domicilios, mandados y vueltas). Cada jugador tiene
 * unos cuantos ofrecidos; acepta los que quiera y los cumple en los lugares.
 */
export class JobBoard {
  constructor(
    private store: GameStore,
    private territory: Territory,
    private progress: Progress,
    private world: WorldIndex
  ) {}

  /** Encargos del jugador. Si hay pocos ofrecidos y se sabe dónde está, arma más. */
  async list(ctx: Ctx, position: { x: number; y: number } | null): Promise<JobView[]> {
    await ctx.trx
      .from('player_jobs')
      .where('user_id', ctx.userId)
      .where('expires_at', '<', ctx.now)
      .delete()
    let rows = await this.#rows(ctx)
    const offered = rows.filter((r) => r.status === 'offered').length
    if (position && offered < J.offered) {
      await this.#generate(ctx, position, J.offered - offered, rows)
      rows = await this.#rows(ctx)
    }
    return rows.map((row) => this.#view(ctx, row))
  }

  /** Cambia los encargos ofrecidos por otros (con un rato de espera entre cambios). */
  async refresh(ctx: Ctx, position: { x: number; y: number }) {
    const wait = ctx.state.jobsAt + J.refreshCooldownSeconds * 1000 - ctx.now.getTime()
    if (wait > 0) {
      throw new GameError(
        'cooldown',
        `Espera ${Math.ceil(wait / 1000)} s para pedir otros encargos.`
      )
    }
    ctx.state.jobsAt = ctx.now.getTime()
    await ctx.trx.from('player_jobs').where({ user_id: ctx.userId, status: 'offered' }).delete()
    return this.list(ctx, position)
  }

  async accept(ctx: Ctx, id: number) {
    const row = await this.#row(ctx, id)
    if (row.status !== 'offered') throw new GameError('job_taken', 'Ese encargo ya lo tienes.')
    const active = await ctx.trx
      .from('player_jobs')
      .where({ user_id: ctx.userId, status: 'active' })
      .count('* as n')
    if (Number(active[0].n) >= J.maxActive) {
      throw new GameError('too_many_jobs', `Solo puedes llevar ${J.maxActive} encargos a la vez.`)
    }
    await ctx.trx
      .from('player_jobs')
      .where('id', id)
      .update({
        status: 'active',
        expires_at: new Date(ctx.now.getTime() + J.activeHours * 3_600_000),
      })
    ctx.events.push({ type: 'toast', text: `Encargo aceptado: ${this.#data(row).title}` })
  }

  async abandon(ctx: Ctx, id: number) {
    await this.#row(ctx, id)
    await ctx.trx.from('player_jobs').where('id', id).delete()
  }

  /** Pasos de encargos activos que se pueden cumplir en este lugar. */
  async stepsAt(ctx: Ctx, poi: WorldPoi) {
    const rows = await ctx.trx.from('player_jobs').where({ user_id: ctx.userId, status: 'active' })
    const out: { id: number; title: string; label: string }[] = []
    for (const row of rows) {
      const data = this.#data(row)
      const step = this.#nextStep(data, poi.id)
      if (step) out.push({ id: Number(row.id), title: data.title, label: stepLabel(step) })
    }
    return out
  }

  /**
   * Cumple en `poi` el paso que toca de un encargo. Devuelve true si con eso
   * el encargo quedó completo (ya pagado).
   */
  async step(ctx: Ctx, id: number, poi: WorldPoi, payFactor: number) {
    const row = await this.#row(ctx, id)
    if (row.status !== 'active') throw new GameError('job_not_active', 'Primero acepta el encargo.')
    const data = this.#data(row)
    const step = this.#nextStep(data, poi.id)
    if (!step) throw new GameError('wrong_place', 'Ese encargo no es aquí.')
    if (step.type === 'bring') {
      await this.store.removeItems(ctx.trx, ctx.userId, { [step.item!]: step.qty! })
    }
    step.done = true
    if (data.steps.some((s) => !s.done)) {
      await ctx.trx
        .from('player_jobs')
        .where('id', id)
        .update({ data: JSON.stringify(data) })
      ctx.events.push({
        type: 'toast',
        text:
          step.type === 'pickup'
            ? 'Recogiste el paquete. ¡A entregarlo!'
            : 'Listo. Sigue con el resto.',
      })
      return false
    }
    await ctx.trx.from('player_jobs').where('id', id).delete()
    await this.store.count(ctx, 'jobs_completed')
    await this.store.count(ctx, `jobs_${row.kind}`)
    if (payFactor < 1) ctx.events.push({ type: 'toast', text: 'Con hambre rindes la mitad.' })
    await this.progress.reward(
      ctx,
      { money: data.reward.money * payFactor, xp: data.reward.xp },
      `Encargo: ${data.title}`
    )
    await this.territory.gain(ctx, poi.x, poi.y, J.influence)
    return true
  }

  // --- Interno -------------------------------------------------------------------

  async #rows(ctx: Ctx) {
    return ctx.trx.from('player_jobs').where('user_id', ctx.userId).orderBy('id', 'asc')
  }

  async #row(ctx: Ctx, id: number) {
    const row = await ctx.trx.from('player_jobs').where({ id, user_id: ctx.userId }).first()
    if (!row) throw new GameError('unknown_job', 'Ese encargo ya no existe.', 404)
    return row
  }

  #data(row: any): JobData {
    return typeof row.data === 'string' ? JSON.parse(row.data) : row.data
  }

  #view(ctx: Ctx, row: any): JobView {
    return {
      id: Number(row.id),
      kind: row.kind,
      status: row.status,
      expiresIn: Math.max(
        0,
        Math.round((new Date(row.expires_at).getTime() - ctx.now.getTime()) / 1000)
      ),
      ...this.#data(row),
    }
  }

  /** El paso sin cumplir que toca en este lugar: en orden, salvo las vueltas. */
  #nextStep(data: JobData, poiId: string) {
    const pending = data.steps.filter((s) => !s.done)
    if (pending.length === 0) return null
    if (pending[0].type === 'visit') return pending.find((s) => s.poi.id === poiId) ?? null
    return pending[0].poi.id === poiId ? pending[0] : null
  }

  async #generate(ctx: Ctx, position: { x: number; y: number }, count: number, existing: any[]) {
    const around = await this.world.poisAround(position.x, position.y, RULES.searchChunks)
    const pois = around.filter((poi) => placeProfile(poi.kind, poi.cat).key !== 'culto')
    if (pois.length === 0) return
    const kinds = new Set(existing.map((r) => r.kind))
    for (let i = 0; i < count; i++) {
      // Variedad: primero los tipos que el jugador no tiene ofrecidos.
      const options = ['delivery', 'errand', 'tour'].filter((k) => !kinds.has(k))
      const kind =
        options.length > 0 ? pick(options) : pick(['delivery', 'delivery', 'errand', 'tour'])
      const data = this.#make(kind, pois)
      if (!data) continue
      kinds.add(kind)
      await ctx.trx
        .insertQuery()
        .table('player_jobs')
        .insert({
          user_id: ctx.userId,
          kind,
          status: 'offered',
          data: JSON.stringify(data),
          expires_at: new Date(ctx.now.getTime() + J.offerMinutes * 60_000),
          created_at: ctx.now,
        })
    }
  }

  #make(kind: string, pois: WorldPoi[]): JobData | null {
    const ref = (poi: WorldPoi) => ({
      id: poi.id,
      cx: poi.cx,
      cy: poi.cy,
      x: poi.x,
      y: poi.y,
      name: poi.name,
      cat: poi.cat,
    })
    if (kind === 'delivery') {
      if (pois.length < 2) return null
      const from = pick(pois)
      const far = pois.filter(
        (p) => p.id !== from.id && Math.hypot(p.x - from.x, p.y - from.y) >= J.delivery.minCells
      )
      const to = pick(far.length > 0 ? far : pois.filter((p) => p.id !== from.id))
      const cells = Math.hypot(to.x - from.x, to.y - from.y)
      return {
        title: `Domicilio para ${to.name}`,
        text: `${pick(DELIVERY_TEXTS)} Recoge en ${from.name} y entrega en ${to.name}.`,
        steps: [
          { type: 'pickup', poi: ref(from), done: false },
          { type: 'deliver', poi: ref(to), done: false },
        ],
        reward: {
          money: Math.round(J.delivery.money + cells * J.delivery.moneyPerCell),
          xp: Math.round(J.delivery.xp + cells * J.delivery.xpPerCell),
        },
      }
    }
    if (kind === 'errand') {
      const to = pick(pois)
      const want = pick(ERRANDS)
      const qty = randomInt(want.qty[0], want.qty[1])
      const value = ITEMS_BY_KEY.get(want.item)!.price * qty
      return {
        title: `Mandado: ${qty} × ${itemName(want.item)}`,
        text: `${pick(ERRAND_TEXTS)} Lleva ${qty} × ${itemName(want.item)} a ${to.name}.`,
        steps: [{ type: 'bring', poi: ref(to), item: want.item, qty, done: false }],
        reward: { money: Math.round(J.errand.money + value * J.errand.markup), xp: J.errand.xp },
      }
    }
    if (pois.length < J.tour.stops) return null
    const stops = [...pois].sort(() => Math.random() - 0.5).slice(0, J.tour.stops)
    return {
      title: 'Vuelta por el barrio',
      text: `${pick(TOUR_TEXTS)} Pasa por ${stops.map((p) => p.name).join(', ')}.`,
      steps: stops.map((poi) => ({ type: 'visit' as const, poi: ref(poi), done: false })),
      reward: { money: J.tour.money, xp: J.tour.xp },
    }
  }
}

function stepLabel(step: JobStep) {
  switch (step.type) {
    case 'pickup':
      return 'Recoger el paquete'
    case 'deliver':
      return 'Entregar el paquete'
    case 'bring':
      return `Entregar ${step.qty} × ${itemName(step.item!)}`
    case 'visit':
      return 'Pasar a saludar'
  }
}
