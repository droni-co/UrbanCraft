import { inject } from '@adonisjs/core'
import app from '@adonisjs/core/services/app'
import vine from '@vinejs/vine'
import type { HttpContext } from '@adonisjs/core/http'
import type { OAuthConfig } from '#config/oauth'
import { devToolsAllowed } from '#auth/dev_tools'
import { OAuthLoginService } from '#services/oauth_login_service'
import UserTransformer from '#transformers/user_transformer'

const devLoginValidator = vine.create({
  name: vine
    .string()
    .trim()
    .minLength(1)
    .maxLength(20)
    .regex(/^[\p{L}\p{N}_]+$/u)
    .optional(),
})

/**
 * Métodos de inicio de sesión disponibles y login de usuarios de prueba.
 * Ver config/oauth.ts (devLogin) para las condiciones de seguridad.
 */
@inject()
export default class DevLoginController {
  constructor(private logins: OAuthLoginService) {}

  /** GET /api/v1/auth/methods → { google, dev } (dev solo se anuncia en local). */
  async methods({ request, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    return {
      google: this.logins.configured,
      dev: devToolsAllowed(request),
    }
  }

  /** POST /api/v1/auth/dev/login { name? } → { data: { user, token, isNew } } · 404 si no está permitido. */
  async store({ request, response, serialize }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    if (!devToolsAllowed(request)) return response.notFound({ error: 'not_found' })

    const { name = 'tester' } = await request.validateUsing(devLoginValidator)
    const { user, isNew } = await this.logins.findOrCreateDevUser(name)
    const token = await this.logins.issueToken(user, 'dev', this.#config().expiresIn)
    return serialize({ user: UserTransformer.transform(user), token, isNew })
  }

  #config() {
    return app.config.get<OAuthConfig['devLogin']>('oauth.devLogin')
  }
}
