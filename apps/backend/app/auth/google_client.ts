import type { OAuthConfig } from '#config/oauth'

/** Datos de la cuenta de Google que usa el juego. */
export interface GoogleProfile {
  /** Id estable de la cuenta ("sub"). El email puede cambiar; esto no. */
  sub: string
  email: string
  emailVerified: boolean
  name: string | null
  givenName: string | null
  picture: string | null
}

export class OAuthProviderError extends Error {
  constructor(
    message: string,
    /** Código corto para el cliente (p. ej. "invalid_grant"). */
    readonly code = 'provider_error'
  ) {
    super(message)
  }
}

/**
 * Cliente de Google OAuth. Abstracto para poder sustituirlo en los tests
 * (app.container.swap) sin llamar a Google.
 */
export abstract class GoogleOAuthClient {
  abstract get configured(): boolean
  /** URL de consentimiento de Google (con PKCE S256). */
  abstract authorizeUrl(state: string, codeChallenge: string): string
  /** Canjea el código del callback y devuelve el perfil del usuario. */
  abstract exchange(code: string, codeVerifier: string): Promise<GoogleProfile>
}

export class HttpGoogleOAuthClient extends GoogleOAuthClient {
  constructor(private config: OAuthConfig['google']) {
    super()
  }

  get configured() {
    return this.config.clientId !== '' && this.config.clientSecret !== ''
  }

  authorizeUrl(state: string, codeChallenge: string) {
    const url = new URL(this.config.authorizeUrl)
    url.search = new URLSearchParams({
      client_id: this.config.clientId,
      redirect_uri: this.config.callbackUrl,
      response_type: 'code',
      scope: this.config.scopes.join(' '),
      state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
      // Deja elegir cuenta aunque el navegador ya tenga una sesión de Google.
      prompt: 'select_account',
    }).toString()
    return url.toString()
  }

  async exchange(code: string, codeVerifier: string): Promise<GoogleProfile> {
    const tokenResponse = await this.#fetch(this.config.tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        code_verifier: codeVerifier,
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        redirect_uri: this.config.callbackUrl,
        grant_type: 'authorization_code',
      }),
    })
    const tokens = (await tokenResponse.json().catch(() => ({}))) as Record<string, unknown>
    if (!tokenResponse.ok || typeof tokens.access_token !== 'string') {
      const reason =
        typeof tokens.error === 'string' ? tokens.error : `http_${tokenResponse.status}`
      throw new OAuthProviderError(`Google rechazó el código (${reason})`, reason)
    }

    // El access token llega directo de Google por TLS: el perfil de userinfo
    // es confiable sin verificar firmas de JWT.
    const infoResponse = await this.#fetch(this.config.userInfoUrl, {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    })
    if (!infoResponse.ok) {
      throw new OAuthProviderError(`userinfo respondió ${infoResponse.status}`)
    }
    const info = (await infoResponse.json()) as Record<string, unknown>
    if (typeof info.sub !== 'string' || typeof info.email !== 'string') {
      throw new OAuthProviderError('Google no devolvió el id o el email', 'missing_profile')
    }
    const str = (v: unknown) => (typeof v === 'string' && v !== '' ? v : null)
    return {
      sub: info.sub,
      email: info.email.toLowerCase(),
      emailVerified: info.email_verified === true || info.email_verified === 'true',
      name: str(info.name),
      givenName: str(info.given_name),
      picture: str(info.picture),
    }
  }

  async #fetch(url: string, init: RequestInit) {
    try {
      return await fetch(url, { ...init, signal: AbortSignal.timeout(this.config.timeoutMs) })
    } catch (error) {
      throw new OAuthProviderError(
        `No se pudo contactar a Google: ${(error as Error).message}`,
        'network'
      )
    }
  }
}
