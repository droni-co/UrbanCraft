/*
|--------------------------------------------------------------------------
| Routes file
|--------------------------------------------------------------------------
|
| The routes file is used for defining the HTTP routes.
|
*/

import { middleware } from '#start/kernel'
import router from '@adonisjs/core/services/router'
import { controllers } from '#generated/controllers'
import db from '@adonisjs/lucid/services/db'

const MapController = () => import('#controllers/map_controller')
const GeoController = () => import('#controllers/geo_controller')
const GoogleAuthController = () => import('#controllers/google_auth_controller')
const DevLoginController = () => import('#controllers/dev_login_controller')
const PlayerStatsController = () => import('#controllers/player_stats_controller')

router.get('/', () => {
  return { name: 'UrbanCraft API', version: 'v1' }
})

/**
 * Health check usado por el cliente de Godot y por despliegues.
 */
router.get('/health', async ({ response }) => {
  try {
    await db.rawQuery('SELECT 1')
    return { status: 'ok', database: 'up' }
  } catch {
    return response.serviceUnavailable({ status: 'degraded', database: 'down' })
  }
})

/**
 * Inicio de sesión con Google: estas dos rutas las abre el NAVEGADOR del
 * jugador (devuelven HTML/redirecciones). El juego usa /api/v1/auth/google/*.
 */
router
  .group(() => {
    router.get('redirect', [GoogleAuthController, 'redirect']).as('redirect')
    router.get('callback', [GoogleAuthController, 'callback']).as('callback')
  })
  .prefix('/auth/google')
  .as('google_browser')

router
  .group(() => {
    router
      .group(() => {
        router.post('signup', [controllers.NewAccount, 'store'])
        router.post('login', [controllers.AccessTokens, 'store'])
        router.post('google/start', [GoogleAuthController, 'start']).as('google.start')
        router.post('google/poll', [GoogleAuthController, 'poll']).as('google.poll')
        router.get('methods', [DevLoginController, 'methods']).as('methods')
        // Solo desarrollo: usuarios de prueba (ver config/oauth.ts → devLogin).
        router.post('dev/login', [DevLoginController, 'store']).as('dev.login')
      })
      .prefix('auth')
      .as('auth')

    router
      .group(() => {
        router.get('profile', [controllers.Profile, 'show'])
        router.patch('profile', [controllers.Profile, 'update'])
        router.post('logout', [controllers.AccessTokens, 'destroy'])
      })
      .prefix('account')
      .as('profile')
      .use(middleware.auth())

    router
      .group(() => {
        router.get('stats', [PlayerStatsController, 'show']).as('stats')
        router.post('heartbeat', [PlayerStatsController, 'heartbeat']).as('heartbeat')
        // Solo desarrollo y en local (ver app/auth/dev_tools.ts).
        router.post('stats/dev', [PlayerStatsController, 'devUpdate']).as('stats.dev')
      })
      .prefix('player')
      .as('player')
      .use(middleware.auth())

    router
      .group(() => {
        router.get('config', [MapController, 'config'])
        router.get('chunks/:z/:x/:y', [MapController, 'chunk'])
      })
      .prefix('map')
      .as('map')

    router
      .group(() => {
        router.get('place', [GeoController, 'place'])
        router.get('ip', [GeoController, 'ip'])
      })
      .prefix('geo')
      .as('geo')
  })
  .prefix('/api/v1')
