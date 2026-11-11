import app from '@adonisjs/core/services/app'
import type { HttpContext } from '@adonisjs/core/http'
import type { OAuthConfig } from '#config/oauth'
import { isLocalRequest } from '#auth/local_request'

/**
 * Herramientas de desarrollo (usuarios de prueba, editar stats…): solo con
 * DEV_LOGIN_ENABLED=true, fuera de producción y desde esta misma máquina.
 */
export function devToolsAllowed(request: HttpContext['request']) {
  const config = app.config.get<OAuthConfig['devLogin']>('oauth.devLogin')
  return config.enabled && !app.inProduction && isLocalRequest(request)
}
