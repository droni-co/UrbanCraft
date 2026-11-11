import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'
import { OAuthLoginService } from '#services/oauth_login_service'
import { browserPage } from '#auth/browser_page'
import UserTransformer from '#transformers/user_transformer'

const ERROR_MESSAGES: Record<string, string> = {
  email_in_use: 'Ese email ya pertenece a otra cuenta de UrbanCraft.',
  invalid_grant: 'El código de Google caducó. Vuelve a intentarlo desde el juego.',
  network: 'No pudimos contactar a Google. Vuelve a intentarlo desde el juego.',
}

/**
 * Inicio de sesión con Google. Ver OAuthLoginService para el flujo completo.
 *
 * API del juego (JSON):
 *   POST /api/v1/auth/google/start  → { loginId, pollSecret, url, expiresIn, interval }
 *   POST /api/v1/auth/google/poll   { loginId, pollSecret }
 *        202 pendiente · 200 { data: { user, token, isNew } } · 410 { error }
 *
 * Navegador (HTML):
 *   GET /auth/google/redirect?login=…  → Google
 *   GET /auth/google/callback          ← Google
 */
@inject()
export default class GoogleAuthController {
  constructor(private logins: OAuthLoginService) {}

  async start({ request, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const result = await this.logins.start(request.ip())
    switch (result.state) {
      case 'not_configured':
        return response.serviceUnavailable({
          error: 'not_configured',
          message: 'El inicio de sesión con Google no está configurado en el servidor',
        })
      case 'throttled':
        response.header('Retry-After', '60')
        return response.tooManyRequests({ error: 'throttled', message: 'Demasiados intentos' })
    }
    return {
      loginId: result.loginId,
      pollSecret: result.pollSecret,
      url: result.url,
      expiresIn: result.expiresIn,
      interval: result.interval,
    }
  }

  async poll({ request, response, serialize }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const loginId = request.input('loginId')
    const pollSecret = request.input('pollSecret')
    if (typeof loginId !== 'string' || typeof pollSecret !== 'string') {
      return response.unprocessableEntity({ error: 'invalid_request' })
    }
    const result = await this.logins.poll(loginId, pollSecret)
    switch (result.state) {
      case 'pending':
        return response.accepted({ status: 'pending' })
      case 'not_found':
        return response.gone({ error: 'expired', message: 'El inicio de sesión caducó' })
      case 'failed':
        return response.gone({ error: result.error, message: ERROR_MESSAGES[result.error] ?? null })
    }
    return serialize({
      user: UserTransformer.transform(result.user),
      token: result.token,
      isNew: result.isNew,
    })
  }

  async redirect({ request, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const result = await this.logins.redirect(String(request.input('login', '')))
    // withQs(false): config/app.ts reenvía la query por defecto y añadiría
    // "?login=…" a la URL de Google.
    if (result.state === 'ok') return response.redirect().withQs(false).toPath(result.url)
    return this.#page(response, 410, {
      ok: false,
      title: 'Enlace caducado',
      message: 'Este enlace ya no es válido. Vuelve al juego e inicia sesión otra vez.',
    })
  }

  async callback({ request, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const result = await this.logins.callback({
      code: request.input('code'),
      state: request.input('state'),
      error: request.input('error'),
    })
    switch (result.state) {
      case 'ok':
        return this.#page(response, 200, {
          ok: true,
          title: result.isNew ? '¡Cuenta creada!' : '¡Sesión iniciada!',
          message: 'Ya puedes cerrar esta pestaña y volver a UrbanCraft.',
        })
      case 'cancelled':
        return this.#page(response, 200, {
          ok: false,
          title: 'Inicio de sesión cancelado',
          message: 'No se compartió nada. Puedes cerrar esta pestaña.',
        })
      case 'invalid':
        return this.#page(response, 400, {
          ok: false,
          title: 'Enlace caducado',
          message: 'Vuelve al juego e inicia sesión otra vez.',
        })
      case 'failed':
        return this.#page(response, 400, {
          ok: false,
          title: 'No se pudo iniciar sesión',
          message: ERROR_MESSAGES[result.error] ?? 'Vuelve al juego e inténtalo otra vez.',
        })
    }
  }

  #page(
    response: HttpContext['response'],
    status: number,
    page: { ok: boolean; title: string; message: string }
  ) {
    response.status(status)
    response.header('Content-Type', 'text/html; charset=utf-8')
    return response.send(browserPage(page))
  }
}
