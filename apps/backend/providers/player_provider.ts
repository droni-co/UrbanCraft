import type { ApplicationService } from '@adonisjs/core/types'
import type { PlayerStatsConfig } from '#config/player_stats'
import type { MapConfig } from '#config/map'
import { PlayerStatsService } from '#services/player_stats_service'
import { GameService } from '#game/game_service'
import { WorldIndex } from '#game/world_index'

export default class PlayerProvider {
  constructor(protected app: ApplicationService) {}

  register() {
    this.app.container.singleton(
      PlayerStatsService,
      () => new PlayerStatsService(this.app.config.get<PlayerStatsConfig>('player_stats'))
    )
    this.app.container.singleton(
      WorldIndex,
      () => new WorldIndex(this.app.config.get<MapConfig>('map'))
    )
    // Mecánicas del juego. El tiempo real se conecta en RealtimeProvider.
    this.app.container.singleton(
      GameService,
      async (resolver) =>
        new GameService(
          this.app.config.get<PlayerStatsConfig>('player_stats'),
          await resolver.make(PlayerStatsService),
          await resolver.make(WorldIndex)
        )
    )
  }
}
