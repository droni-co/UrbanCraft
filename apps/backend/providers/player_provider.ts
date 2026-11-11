import type { ApplicationService } from '@adonisjs/core/types'
import type { PlayerStatsConfig } from '#config/player_stats'
import { PlayerStatsService } from '#services/player_stats_service'

export default class PlayerProvider {
  constructor(protected app: ApplicationService) {}

  register() {
    this.app.container.singleton(
      PlayerStatsService,
      () => new PlayerStatsService(this.app.config.get<PlayerStatsConfig>('player_stats'))
    )
  }
}
