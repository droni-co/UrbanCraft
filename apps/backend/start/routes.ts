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

router
  .group(() => {
    router
      .group(() => {
        router.post('signup', [controllers.NewAccount, 'store'])
        router.post('login', [controllers.AccessTokens, 'store'])
      })
      .prefix('auth')
      .as('auth')

    router
      .group(() => {
        router.get('profile', [controllers.Profile, 'show'])
        router.post('logout', [controllers.AccessTokens, 'destroy'])
      })
      .prefix('account')
      .as('profile')
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
