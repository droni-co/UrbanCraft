import env from '#start/env'

const appUrl = env.get('APP_URL').replace(/\/+$/, '')
const inProduction = env.get('NODE_ENV') === 'production'

/**
 * Inicio de sesión con Google (OAuth 2.0 / OpenID Connect) para el juego.
 *
 * El juego (PC, móvil, web) no recibe el callback de Google: abre el navegador
 * del sistema en /auth/google/redirect y consulta al backend hasta que el
 * jugador termina ("polling", como el device flow). El client secret vive solo
 * aquí, nunca en el cliente de Godot. Ver docs/login-google.md.
 */
const oauthConfig = {
  /** URL pública del backend: la abre el navegador del jugador. */
  publicUrl: appUrl,

  google: {
    /** Google Cloud Console → APIs y servicios → Credenciales → ID de cliente OAuth (Aplicación web). */
    clientId: env.get('GOOGLE_CLIENT_ID', ''),
    clientSecret: env.get('GOOGLE_CLIENT_SECRET', ''),
    /** Debe estar registrada tal cual en "URIs de redireccionamiento autorizados". */
    callbackUrl: env.get('GOOGLE_CALLBACK_URL') ?? `${appUrl}/auth/google/callback`,
    authorizeUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    userInfoUrl: 'https://openidconnect.googleapis.com/v1/userinfo',
    scopes: ['openid', 'email', 'profile'],
    timeoutMs: 10_000,
  },

  login: {
    /** Tiempo que tiene el jugador para completar el login en el navegador. */
    ttlSeconds: 600,
    /** Cada cuánto consulta el cliente si ya terminó. */
    pollIntervalSeconds: 2,
    /** Límite de logins iniciados por IP (en memoria, por instancia). */
    startsPerIp: 10,
    windowMs: 60_000,
  },

  /** Token de acceso que recibe el juego al terminar. */
  token: {
    name: 'game',
    expiresIn: '30 days',
  },

  /**
   * Login de usuarios de prueba (sin Google) para depurar y para pruebas
   * automáticas: POST /api/v1/auth/dev/login { name }.
   * - Solo con DEV_LOGIN_ENABLED=true y NUNCA con NODE_ENV=production.
   * - Solo desde esta máquina: conexión loopback y sin cabeceras de proxy
   *   (un túnel como cloudflared también llega por 127.0.0.1).
   */
  devLogin: {
    enabled: env.get('DEV_LOGIN_ENABLED', false) && !inProduction,
    emailDomain: 'dev.urbancraft.test',
    expiresIn: '30 days',
  },
}

export type OAuthConfig = typeof oauthConfig
export default oauthConfig
