import { inject } from '@adonisjs/core'
import app from '@adonisjs/core/services/app'
import db from '@adonisjs/lucid/services/db'
import type { HttpContext } from '@adonisjs/core/http'
import { ACHIEVEMENTS } from '#game/catalog/achievements'
import { FriendsService } from '#services/friends_service'
import { PlayerStatsService } from '#services/player_stats_service'
import { GameRealtimeServer } from '#realtime/game_server'

/** Contadores que se muestran en el perfil público (en este orden). */
const PUBLIC_COUNTERS = [
  'distance_m',
  'pois_discovered',
  'jobs_completed',
  'items_crafted',
  'days_played',
  'friends',
] as const

/** Medallas recientes que se muestran en el perfil. */
const RECENT_MEDALS = 8

const BY_KEY = new Map(ACHIEVEMENTS.map((a) => [a.key, a]))

/**
 * GET /api/v1/players/:id → perfil público de otro jugador:
 *   { player: { id, nickname, skin, level, since, relation, requestId,
 *               online, counters, achievements: { unlocked, total, recent } } }
 *
 * Para no permitir listar a todos los jugadores, solo se ve el perfil de
 * quien tienes cerca en el mapa, de tus amigos o de quien tiene una
 * solicitud contigo. Si no, 404 (igual que si no existiera).
 */
@inject()
export default class PlayersController {
  constructor(
    private friends: FriendsService,
    private stats: PlayerStatsService
  ) {}

  async show({ auth, params, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const me = auth.getUserOrFail().id
    const id = Number(params.id)
    const realtime = await app.container.make(GameRealtimeServer)
    const { relation, requestId } = await this.friends.relationDetail(me, id)
    if (relation === 'none' && !realtime.canSee(me, id)) {
      return response.notFound({ error: 'player_not_found', message: 'Ese jugador no está cerca' })
    }
    const user = await this.friends.findById(id)
    if (!user) {
      return response.notFound({ error: 'player_not_found', message: 'Ese jugador no está cerca' })
    }

    const snapshot = await this.stats.snapshot(id)
    const counterRows = await db
      .from('player_counters')
      .where('user_id', id)
      .whereIn('key', [...PUBLIC_COUNTERS])
    const achievementRows = await db
      .from('player_achievements')
      .where('user_id', id)
      .orderBy('unlocked_at', 'desc')
      .select('key')
    const created = await db.from('users').where('id', id).select('created_at').first()
    const values = new Map(counterRows.map((r) => [r.key as string, Number(r.value)]))
    const recent = achievementRows
      .map((r) => BY_KEY.get(r.key as string))
      .filter((a) => a !== undefined)
      .slice(0, RECENT_MEDALS)
      .map((a) => ({ key: a.key, name: a.name, desc: a.desc, emblem: a.emblem, tier: a.tier }))

    return {
      player: {
        ...user,
        level: snapshot.find((s) => s.kind === 'level')?.level?.level ?? 1,
        since: created?.created_at ?? null,
        relation,
        requestId,
        online: relation === 'friend' ? realtime.isOnline(id) : undefined,
        counters: PUBLIC_COUNTERS.map((key) => ({ key, value: values.get(key) ?? 0 })),
        achievements: { unlocked: achievementRows.length, total: ACHIEVEMENTS.length, recent },
      },
    }
  }
}
