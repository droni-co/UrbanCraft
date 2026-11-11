import { inject } from '@adonisjs/core'
import vine from '@vinejs/vine'
import type { HttpContext } from '@adonisjs/core/http'
import { devToolsAllowed } from '#auth/dev_tools'
import { PlayerStatsService } from '#services/player_stats_service'

const devUpdateValidator = vine.create({
  key: vine.string().trim().maxLength(32),
  delta: vine.number().optional(),
  value: vine.number().optional(),
})

/**
 * GET  /api/v1/player/stats            → { stats: StatView[] }
 * POST /api/v1/player/heartbeat        → { stats, nextHeartbeat }  (cada ~60 s jugando)
 * POST /api/v1/player/stats/dev        { key, delta | value }  solo desarrollo y en local
 */
@inject()
export default class PlayerStatsController {
  constructor(private stats: PlayerStatsService) {}

  async show({ auth, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    return { stats: await this.stats.snapshot(auth.getUserOrFail().id) }
  }

  async heartbeat({ auth, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    return {
      stats: await this.stats.heartbeat(auth.getUserOrFail().id),
      nextHeartbeat: this.stats.heartbeatInterval,
    }
  }

  async devUpdate({ auth, request, response }: HttpContext) {
    if (!devToolsAllowed(request)) return response.notFound({ error: 'not_found' })
    const { key, delta, value } = await request.validateUsing(devUpdateValidator)
    if (!this.stats.definition(key)) {
      return response.unprocessableEntity({
        error: 'unknown_stat',
        message: `Stat desconocido: ${key}`,
      })
    }
    const userId = auth.getUserOrFail().id
    if (value !== undefined) await this.stats.set(userId, key, value)
    else await this.stats.add(userId, key, delta ?? 0)
    return { stats: await this.stats.snapshot(userId) }
  }
}
