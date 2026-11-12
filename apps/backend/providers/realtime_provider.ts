import type { ApplicationService } from '@adonisjs/core/types'
import type { RealtimeConfig } from '#config/realtime'
import { GameRealtimeServer } from '#realtime/game_server'
import { PlayerStatsService } from '#services/player_stats_service'
import { FriendsService } from '#services/friends_service'

export default class RealtimeProvider {
  #realtime?: GameRealtimeServer

  constructor(protected app: ApplicationService) {}

  register() {
    this.app.container.singleton(GameRealtimeServer, async (resolver) => {
      const map = this.app.config.get<{ cellZoom: number; chunkZoom: number }>('map')
      return new GameRealtimeServer(
        this.app.config.get<RealtimeConfig>('realtime'),
        map,
        await resolver.make(PlayerStatsService),
        await resolver.make(FriendsService)
      )
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
