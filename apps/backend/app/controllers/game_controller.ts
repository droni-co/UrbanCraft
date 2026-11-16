import { inject } from '@adonisjs/core'
import vine from '@vinejs/vine'
import type { HttpContext } from '@adonisjs/core/http'
import { devToolsAllowed } from '#auth/dev_tools'
import { GameService } from '#game/game_service'
import { GameError } from '#game/types'

const poi = vine.object({
  id: vine.string().trim().maxLength(32),
  cx: vine.number().withoutDecimals().min(0),
  cy: vine.number().withoutDecimals().min(0),
})
const qty = vine.number().withoutDecimals().min(1).max(99)
const item = vine.string().trim().maxLength(32)
const cell = vine
  .number()
  .withoutDecimals()
  .min(0)
  .max(2 ** 30)

const visitValidator = vine.create({ poi })
const tradeValidator = vine.create({ poi, item, qty })
const serviceValidator = vine.create({ poi, service: vine.string().trim().maxLength(32) })
const talkValidator = vine.create({ poi: poi.clone().optional() })
const gatherValidator = vine.create({ x: cell, y: cell })
const useValidator = vine.create({ item })
const craftValidator = vine.create({
  recipe: vine.string().trim().maxLength(32),
  times: vine.number().withoutDecimals().min(1).max(20).optional(),
})
const placeValidator = vine.create({ item, x: cell, y: cell })
const actValidator = vine.create({
  action: vine.string().trim().maxLength(16),
  item: item.clone().optional(),
  qty: qty.clone().optional(),
  price: vine.number().withoutDecimals().min(1).max(100_000).optional(),
  phrase: vine.number().withoutDecimals().min(0).max(200).optional(),
})
const objectsValidator = vine.create({
  cx0: vine.number().withoutDecimals().min(0),
  cy0: vine.number().withoutDecimals().min(0),
  cx1: vine.number().withoutDecimals().min(0),
  cy1: vine.number().withoutDecimals().min(0),
})
const devValidator = vine.create({
  action: vine.string().trim().maxLength(16),
  item: item.clone().optional(),
  qty: vine.number().withoutDecimals().min(1).max(999).optional(),
  points: vine.number().min(1).max(5000).optional(),
})

/** Lado máximo (en chunks) del rectángulo de objetos que se puede pedir de una vez. */
const MAX_OBJECTS_SPAN = 16

/**
 * Mecánicas del juego (ver GameService). Todas las rutas van bajo
 * /api/v1/game y piden sesión. Las acciones responden con su resultado más el
 * jugador al día: { …, stats, inventory, story, events }.
 * Los errores de juego son 4xx con { error, message } (mensaje para mostrar).
 */
@inject()
export default class GameController {
  constructor(private game: GameService) {}

  catalog({ response }: HttpContext) {
    response.header('Cache-Control', 'public, max-age=300')
    return this.game.catalog()
  }

  state(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.state(userId))
  }

  storySeen(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.storySeen(userId))
  }

  async storyTalk(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(talkValidator)
    return this.#run(ctx, (userId) => this.game.storyTalk(userId, body.poi ?? null))
  }

  async visit(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(visitValidator)
    return this.#run(ctx, (userId) => this.game.visit(userId, body.poi))
  }

  async buy(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(tradeValidator)
    return this.#run(ctx, (userId) => this.game.buy(userId, body.poi, body.item, body.qty))
  }

  async sell(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(tradeValidator)
    return this.#run(ctx, (userId) => this.game.sell(userId, body.poi, body.item, body.qty))
  }

  async work(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(visitValidator)
    return this.#run(ctx, (userId) => this.game.work(userId, body.poi))
  }

  async service(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(serviceValidator)
    return this.#run(ctx, (userId) => this.game.service(userId, body.poi, body.service))
  }

  async gather(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(gatherValidator)
    return this.#run(ctx, (userId) => this.game.gather(userId, body.x, body.y))
  }

  async use(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(useValidator)
    return this.#run(ctx, (userId) => this.game.use(userId, body.item))
  }

  async craft(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(craftValidator)
    return this.#run(ctx, (userId) => this.game.craft(userId, body.recipe, body.times ?? 1))
  }

  jobs(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.jobList(userId))
  }

  jobRefresh(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.jobRefresh(userId))
  }

  jobAccept(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.jobAccept(userId, Number(ctx.params.id)))
  }

  jobAbandon(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.jobAbandon(userId, Number(ctx.params.id)))
  }

  async jobStep(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(visitValidator)
    return this.#run(ctx, (userId) => this.game.jobStep(userId, Number(ctx.params.id), body.poi))
  }

  territory(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.territoryView(userId))
  }

  collectRent(ctx: HttpContext) {
    return this.#run(ctx, (userId) => this.game.collectRent(userId))
  }

  async objects(ctx: HttpContext) {
    const q = await objectsValidator.validate(ctx.request.qs())
    if (
      q.cx1 < q.cx0 ||
      q.cy1 < q.cy0 ||
      q.cx1 - q.cx0 >= MAX_OBJECTS_SPAN ||
      q.cy1 - q.cy0 >= MAX_OBJECTS_SPAN
    ) {
      return ctx.response.unprocessableEntity({ error: 'bad_area', message: 'Área inválida.' })
    }
    ctx.response.header('Cache-Control', 'no-store')
    return { objects: await this.game.objectsIn(q.cx0, q.cy0, q.cx1, q.cy1) }
  }

  async placeObject(ctx: HttpContext) {
    const body = await ctx.request.validateUsing(placeValidator)
    return this.#run(ctx, (userId) => this.game.placeObject(userId, body.item, body.x, body.y))
  }

  async objectAction(ctx: HttpContext) {
    const { action, ...args } = await ctx.request.validateUsing(actValidator)
    return this.#run(ctx, (userId) =>
      this.game.objectAction(userId, Number(ctx.params.id), action, args)
    )
  }

  async dev(ctx: HttpContext) {
    if (!devToolsAllowed(ctx.request)) return ctx.response.notFound({ error: 'not_found' })
    const { action, ...args } = await ctx.request.validateUsing(devValidator)
    return this.#run(ctx, (userId) => this.game.dev(userId, action, args))
  }

  async #run<T>({ auth, response }: HttpContext, action: (userId: number) => Promise<T>) {
    response.header('Cache-Control', 'no-store')
    try {
      return await action(auth.getUserOrFail().id)
    } catch (error) {
      if (!(error instanceof GameError)) throw error
      return response.status(error.status).send({ error: error.code, message: error.message })
    }
  }
}
