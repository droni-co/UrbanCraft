import type { ApplicationService } from '@adonisjs/core/types'
import type { RealtimeConfig } from '#config/realtime'
import { GameRealtimeServer } from '#realtime/game_server'
import { PlayerStatsService } from '#services/player_stats_service'
import { FriendsService } from '#services/friends_service'
import { GameService } from '#game/game_service'

export default class RealtimeProvider {
  #realtime?: GameRealtimeServer

  constructor(protected app: ApplicationService) {}

  register() {
    this.app.container.singleton(GameRealtimeServer, async (resolver) => {
      const map = this.app.config.get<{ cellZoom: number; chunkZoom: number }>('map')
      const realtime = new GameRealtimeServer(
        this.app.config.get<RealtimeConfig>('realtime'),
        map,
        await resolver.make(PlayerStatsService),
        await resolver.make(FriendsService)
      )
      // Las mecánicas del juego validan con la posición del tiempo real y
      // avisan por él; el tiempo real les cuenta lo que ve (metros, saludos, chat).
      const game = await resolver.make(GameService)
      game.connect({
        position: (userId) => realtime.position(userId),
        notify: (userId, events) => realtime.notifyGame(userId, events),
        broadcastObject: (x, y, payload) => realtime.broadcastNear(x, y, payload),
      })
      realtime.setGameHooks({ track: (userId, key, delta) => game.track(userId, key, delta) })
      return realtime
    })
  }

  /** Con el servidor HTTP ya creado (HTTP ignitor), engancha el WebSocket. */
  async ready() {
    if (this.app.getEnvironment() !== 'web') return
    const server = await this.app.container.make('server')
    this.#realtime = await this.app.container.make(GameRealtimeServer)
    this.#realtime.attach(server.getNodeServer())
  }

  async shutdown() {
    await this.#realtime?.close()
  }
}
