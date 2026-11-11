import { createHash, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto'
import { DateTime } from 'luxon'
import db from '@adonisjs/lucid/services/db'
import User from '#models/user'
import type { OAuthConfig } from '#config/oauth'
import { type GoogleOAuthClient, type GoogleProfile, OAuthProviderError } from '#auth/google_client'

const TABLE = 'oauth_logins'

export type StartResult =
  | {
      state: 'ok'
      loginId: string
      pollSecret: string
      url: string
      expiresIn: number
      interval: number
    }
  | { state: 'not_configured' }
  | { state: 'throttled' }

export type RedirectResult = { state: 'ok'; url: string } | { state: 'invalid' }

export type CallbackResult =
  | { state: 'ok'; user: User; isNew: boolean }
  | { state: 'cancelled' }
  | { state: 'invalid' }
  | { state: 'failed'; error: string }

export type PollResult =
  | { state: 'pending' }
  | { state: 'complete'; user: User; token: string; isNew: boolean }
  | { state: 'failed'; error: string }
  | { state: 'not_found' }

interface LoginRow {
  id: string
  status: 'pending' | 'redirected' | 'complete' | 'failed'
  poll_secret_hash: string
  state: string | null
  code_verifier: string | null
  error: string | null
  user_id: number | null
  is_new_user: boolean
  expires_at: Date
}

/**
 * Inicio de sesión con Google para el juego, sin que el cliente reciba el
 * callback (sirve igual en PC, Android, iOS y web):
 *
 *   1. start(): el juego recibe loginId + pollSecret + una URL de este backend.
 *   2. El juego abre esa URL en el navegador → redirect() → Google.
 *   3. Google vuelve a callback(): se crea o vincula la cuenta.
 *   4. El juego consulta poll(loginId, pollSecret) y recibe su token de acceso.
 *
 * El pollSecret nunca aparece en una URL: quien vea la URL del navegador no
 * puede recoger el token. PKCE protege el canje del código.
 */
export class OAuthLoginService {
  #starts = new Map<string, number[]>()

  constructor(
    private config: OAuthConfig,
    private google: GoogleOAuthClient
  ) {}

  get configured() {
    return this.google.configured
  }

  async start(ip: string | null): Promise<StartResult> {
    if (!this.google.configured) return { state: 'not_configured' }
    if (!this.#allowStart(ip ?? 'unknown')) return { state: 'throttled' }

    await db.from(TABLE).where('expires_at', '<', new Date()).delete()

    const loginId = randomUUID()
    const pollSecret = randomBytes(32).toString('base64url')
    const now = DateTime.now()
    await db.table(TABLE).insert({
      id: loginId,
      provider: 'google',
      poll_secret_hash: sha256(pollSecret),
      status: 'pending',
      ip,
      expires_at: now.plus({ seconds: this.config.login.ttlSeconds }).toJSDate(),
      created_at: now.toJSDate(),
    })
    return {
      state: 'ok',
      loginId,
      pollSecret,
      url: `${this.config.publicUrl}/auth/google/redirect?login=${loginId}`,
      expiresIn: this.config.login.ttlSeconds,
      interval: this.config.login.pollIntervalSeconds,
    }
  }

  /** Paso del navegador: prepara state + PKCE y devuelve la URL de Google. */
  async redirect(loginId: string): Promise<RedirectResult> {
    const row = await this.#find(loginId)
    if (!row || !['pending', 'redirected'].includes(row.status)) return { state: 'invalid' }

    // Recargar la página genera un state nuevo (el anterior deja de valer).
    const state = randomBytes(24).toString('base64url')
    const codeVerifier = randomBytes(48).toString('base64url')
    await db.from(TABLE).where('id', row.id).update({
      status: 'redirected',
      state,
      code_verifier: codeVerifier,
      updated_at: new Date(),
    })
    const challenge = createHash('sha256').update(codeVerifier).digest('base64url')
    return { state: 'ok', url: this.google.authorizeUrl(state, challenge) }
  }

  async callback(params: {
    code?: string
    state?: string
    error?: string
  }): Promise<CallbackResult> {
    if (!params.state) return { state: 'invalid' }
    const row = (await db
      .from(TABLE)
      .where('state', params.state)
      .where('status', 'redirected')
      .where('expires_at', '>', new Date())
      .first()) as LoginRow | null
    if (!row) return { state: 'invalid' }

    if (params.error || !params.code) {
      const error = params.error === 'access_denied' ? 'cancelled' : (params.error ?? 'no_code')
      await this.#fail(row.id, error)
      return error === 'cancelled' ? { state: 'cancelled' } : { state: 'failed', error }
    }

    try {
      const profile = await this.google.exchange(params.code, row.code_verifier!)
      const { user, isNew } = await this.findOrCreateUser(profile)
      await db.from(TABLE).where('id', row.id).update({
        status: 'complete',
        user_id: user.id,
        is_new_user: isNew,
        state: null,
        code_verifier: null,
        updated_at: new Date(),
      })
      return { state: 'ok', user, isNew }
    } catch (error) {
      const code =
        error instanceof OAuthProviderError || error instanceof AccountConflictError
          ? error.code
          : 'server_error'
      if (code === 'server_error') throw error
      await this.#fail(row.id, code)
      return { state: 'failed', error: code }
    }
  }

  /** El juego recoge el resultado. Un login completo se entrega una sola vez. */
  async poll(loginId: string, pollSecret: string): Promise<PollResult> {
    const row = await this.#find(loginId)
    if (!row || !safeEqual(row.poll_secret_hash, sha256(pollSecret))) return { state: 'not_found' }

    switch (row.status) {
      case 'pending':
      case 'redirected':
        return { state: 'pending' }
      case 'failed':
        await db.from(TABLE).where('id', row.id).delete()
        return { state: 'failed', error: row.error ?? 'failed' }
    }

    // Borrar primero: si dos peticiones llegan a la vez, solo una recibe token.
    const deleted = await db.from(TABLE).where('id', row.id).where('status', 'complete').delete()
    if (!deleted || (Array.isArray(deleted) && deleted[0] === 0)) return { state: 'not_found' }
    const user = await User.find(row.user_id)
    if (!user) return { state: 'failed', error: 'user_deleted' }
    const token = await User.accessTokens.create(user, ['*'], {
      name: this.config.token.name,
      expiresIn: this.config.token.expiresIn,
    })
    return { state: 'complete', user, token: token.value!.release(), isNew: row.is_new_user }
  }

  /**
   * Busca la cuenta por id de Google; si no existe, vincula una cuenta con el
   * mismo email (solo si Google lo da por verificado) o crea una nueva.
   */
  async findOrCreateUser(profile: GoogleProfile): Promise<{ user: User; isNew: boolean }> {
    const byGoogle = await User.findBy('googleId', profile.sub)
    if (byGoogle) {
      byGoogle.avatarUrl = profile.picture
      if (!byGoogle.fullName) byGoogle.fullName = profile.name
      await byGoogle.save()
      return { user: byGoogle, isNew: false }
    }

    const byEmail = await User.query().whereRaw('lower(email) = ?', [profile.email]).first()
    if (byEmail) {
      if (!profile.emailVerified) {
        throw new AccountConflictError(
          'El email ya está registrado y Google no lo verificó',
          'email_in_use'
        )
      }
      if (byEmail.googleId) {
        throw new AccountConflictError(
          'El email ya está vinculado a otra cuenta de Google',
          'email_in_use'
        )
      }
      byEmail.googleId = profile.sub
      byEmail.avatarUrl = profile.picture
      if (!byEmail.fullName) byEmail.fullName = profile.name
      if (!byEmail.nickname) byEmail.nickname = await this.uniqueNickname(profile)
      await byEmail.save()
      return { user: byEmail, isNew: false }
    }

    const user = await User.create({
      email: profile.email,
      fullName: profile.name,
      googleId: profile.sub,
      avatarUrl: profile.picture,
      nickname: await this.uniqueNickname(profile),
    })
    return { user, isNew: true }
  }

  /**
   * Usuario de prueba (login de desarrollo): siempre el mismo para el mismo
   * nombre, con email <nombre>@dev.urbancraft.test y ese apodo si está libre.
   */
  async findOrCreateDevUser(name: string): Promise<{ user: User; isNew: boolean }> {
    const email = `${devSlug(name)}@${this.config.devLogin.emailDomain}`
    const existing = await User.findBy('email', email)
    if (existing) return { user: existing, isNew: false }
    const nickname =
      name.length >= 3 && !(await isNicknameTaken(name))
        ? name
        : await this.uniqueNickname({ givenName: name, name, email })
    const user = await User.create({ email, fullName: `Prueba ${name}`, nickname })
    return { user, isNew: true }
  }

  /** Token de acceso para un usuario ya autenticado por otro medio (dev login). */
  async issueToken(user: User, name: string, expiresIn: string) {
    const token = await User.accessTokens.create(user, ['*'], { name, expiresIn })
    return token.value!.release()
  }

  /** Apodo inicial a partir del nombre ("Gustavo" → "Gustavo4821"); se puede cambiar. */
  async uniqueNickname(profile: Pick<GoogleProfile, 'givenName' | 'name' | 'email'>) {
    const base = nicknameBase(profile.givenName ?? profile.name ?? profile.email.split('@')[0])
    for (let attempt = 0; attempt < 6; attempt++) {
      const candidate = `${base}${randomInt(1000, 10000)}`
      if (!(await isNicknameTaken(candidate))) return candidate
    }
    return `Jugador${randomBytes(4).toString('hex')}`
  }

  async #find(loginId: string): Promise<LoginRow | null> {
    if (!/^[0-9a-f-]{36}$/i.test(loginId)) return null
    return (await db
      .from(TABLE)
      .where('id', loginId)
      .where('expires_at', '>', new Date())
      .first()) as LoginRow | null
  }

  async #fail(id: string, error: string) {
    await db
      .from(TABLE)
      .where('id', id)
      .update({
        status: 'failed',
        error: error.slice(0, 64),
        state: null,
        code_verifier: null,
        updated_at: new Date(),
      })
  }

  #allowStart(ip: string): boolean {
    const now = Date.now()
    const { startsPerIp, windowMs } = this.config.login
    const recent = (this.#starts.get(ip) ?? []).filter((t) => now - t < windowMs)
    const allowed = recent.length < startsPerIp
    if (allowed) recent.push(now)
    this.#starts.set(ip, recent)
    return allowed
  }
}

export class AccountConflictError extends Error {
  constructor(
    message: string,
    readonly code: string
  ) {
    super(message)
  }
}

export async function isNicknameTaken(nickname: string, exceptUserId?: number) {
  const query = User.query().whereRaw('lower(nickname) = lower(?)', [nickname])
  if (exceptUserId !== undefined) query.whereNot('id', exceptUserId)
  return (await query.first()) !== null
}

/** "José María" → "JoseMaria" (ASCII, 3–16 caracteres). */
export function nicknameBase(source: string) {
  const ascii = source
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9_]/g, '')
    .slice(0, 16)
  return ascii.length >= 3 ? ascii : 'Jugador'
}

/** "José Mª" → "josem"; si no queda nada ASCII, un hash corto. */
export function devSlug(name: string) {
  const slug = name
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, '')
  return slug || `u${sha256(name).slice(0, 10)}`
}

function sha256(value: string) {
  return createHash('sha256').update(value).digest('hex')
}

function safeEqual(a: string, b: string) {
  return a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b))
}
