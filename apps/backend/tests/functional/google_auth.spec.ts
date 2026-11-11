import { createHash } from 'node:crypto'
import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import testUtils from '@adonisjs/core/services/test_utils'
import type { ApiClient } from '@japa/api-client'
import User from '#models/user'
import type { OAuthConfig } from '#config/oauth'
import { GoogleOAuthClient, type GoogleProfile, OAuthProviderError } from '#auth/google_client'
import { OAuthLoginService } from '#services/oauth_login_service'

class FakeGoogle extends GoogleOAuthClient {
  challenges = new Map<string, string>()
  constructor(
    public profile: GoogleProfile,
    public isConfigured = true,
    public failWith: string | null = null
  ) {
    super()
  }
  get configured() {
    return this.isConfigured
  }
  authorizeUrl(state: string, codeChallenge: string) {
    this.challenges.set(state, codeChallenge)
    return `https://accounts.example/auth?state=${state}&code_challenge=${codeChallenge}`
  }
  async exchange(code: string, codeVerifier: string) {
    if (this.failWith) throw new OAuthProviderError('falla simulada', this.failWith)
    const [, state] = code.split(':')
    const expected = this.challenges.get(state)
    const actual = createHash('sha256').update(codeVerifier).digest('base64url')
    if (expected !== actual) throw new OAuthProviderError('PKCE no coincide', 'invalid_grant')
    return this.profile
  }
}

const PROFILE: GoogleProfile = {
  sub: 'google-123',
  email: 'ana.lopez@example.com',
  emailVerified: true,
  name: 'Ana López',
  givenName: 'Ana',
  picture: 'https://example.com/ana.png',
}

function useFake(fake: FakeGoogle, overrides: Partial<OAuthConfig['login']> = {}) {
  const base = app.config.get<OAuthConfig>('oauth')
  const config: OAuthConfig = { ...base, login: { ...base.login, ...overrides } }
  // Una sola instancia (como el singleton real): el límite por IP vive en ella.
  const service = new OAuthLoginService(config, fake)
  app.container.swap(OAuthLoginService, () => service)
}

/** Hace el recorrido del navegador: redirect → "Google" → callback. */
async function browserLogin(client: ApiClient, url: string, opts: { error?: string } = {}) {
  const path = new URL(url).pathname + new URL(url).search
  const redirect = await client.get(path).redirects(0)
  redirect.assertStatus(302)
  const google = new URL(redirect.header('location')!)
  // La URL de Google no debe arrastrar la query de la nuestra (?login=…).
  if (google.searchParams.has('login') || /\?.*\?/.test(google.href)) {
    throw new Error(`URL de Google con query reenviada: ${google.href}`)
  }
  const state = google.searchParams.get('state')!
  const query = opts.error ? { state, error: opts.error } : { state, code: `code:${state}` }
  return client.get('/auth/google/callback').qs(query)
}

async function start(client: ApiClient) {
  const res = await client.post('/api/v1/auth/google/start')
  res.assertStatus(200)
  return res.body() as { loginId: string; pollSecret: string; url: string; interval: number }
}

function poll(client: ApiClient, login: { loginId: string; pollSecret: string }) {
  return client
    .post('/api/v1/auth/google/poll')
    .json({ loginId: login.loginId, pollSecret: login.pollSecret })
}

test.group('Login con Google', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.teardown(() => app.container.restoreAll())

  test('responde 503 si Google no está configurado', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE, false))
    const res = await client.post('/api/v1/auth/google/start')
    res.assertStatus(503)
    res.assertBodyContains({ error: 'not_configured' })
  })

  test('flujo completo: crea la cuenta y entrega el token una sola vez', async ({
    client,
    assert,
  }) => {
    useFake(new FakeGoogle(PROFILE))
    const login = await start(client)
    assert.match(login.url, /\/auth\/google\/redirect\?login=[0-9a-f-]{36}$/)
    assert.notInclude(login.url, login.pollSecret)

    const res1 = await poll(client, login)
    res1.assertStatus(202)

    const page = await browserLogin(client, login.url)
    page.assertStatus(200)
    assert.include(page.text(), '¡Cuenta creada!')

    const done = await poll(client, login)
    done.assertStatus(200)
    const { user, token, isNew } = (done.body() as any).data
    assert.isTrue(isNew)
    assert.equal(user.email, PROFILE.email)
    assert.equal(user.fullName, 'Ana López')
    assert.match(user.nickname, /^Ana\d{4}$/)
    assert.isTrue(user.hasGoogle)
    assert.isFalse(user.hasPassword)

    const profile = await client.get('/api/v1/account/profile').bearerToken(token)
    profile.assertStatus(200)
    assert.equal((profile.body() as any).data.email, PROFILE.email)

    // Ya entregado: no se puede recoger otra vez.
    const res2 = await poll(client, login)
    res2.assertStatus(410)
  })

  test('el segundo login usa la misma cuenta', async ({ client, assert }) => {
    useFake(new FakeGoogle(PROFILE))
    for (const expectedNew of [true, false]) {
      const login = await start(client)
      await browserLogin(client, login.url)
      const done = await poll(client, login)
      assert.equal((done.body() as any).data.isNew, expectedNew)
    }
    assert.lengthOf(await User.query().where('googleId', PROFILE.sub), 1)
  })

  test('sin el pollSecret correcto no se entrega nada', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE))
    const login = await start(client)
    await browserLogin(client, login.url)
    const res3 = await poll(client, { ...login, pollSecret: 'otro-secreto' })
    res3.assertStatus(410)
    const res4 = await poll(client, login)
    res4.assertStatus(200)
  })

  test('cancelar en Google se informa al juego', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE))
    const login = await start(client)
    const page = await browserLogin(client, login.url, { error: 'access_denied' })
    page.assertTextIncludes('cancelado')
    const res = await poll(client, login)
    res.assertStatus(410)
    res.assertBodyContains({ error: 'cancelled' })
  })

  test('un fallo de Google llega al juego con su código', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE, true, 'invalid_grant'))
    const login = await start(client)
    const res5 = await browserLogin(client, login.url)
    res5.assertStatus(400)
    const res = await poll(client, login)
    res.assertStatus(410)
    res.assertBodyContains({ error: 'invalid_grant' })
  })

  test('el callback rechaza un state desconocido', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE))
    const res = await client.get('/auth/google/callback').qs({ state: 'falso', code: 'x' })
    res.assertStatus(400)
  })

  test('un enlace de login inválido muestra una página de error', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE))
    const res = await client.get('/auth/google/redirect').qs({ login: 'no-existe' }).redirects(0)
    res.assertStatus(410)
    res.assertHeader('content-type', 'text/html; charset=utf-8')
  })

  test('vincula una cuenta existente con el mismo email verificado', async ({ client, assert }) => {
    useFake(new FakeGoogle(PROFILE))
    const existing = await User.create({
      email: PROFILE.email,
      password: 'secreto-123',
      fullName: null,
    })
    const login = await start(client)
    await browserLogin(client, login.url)
    const done = await poll(client, login)
    done.assertStatus(200)
    assert.equal((done.body() as any).data.user.id, existing.id)
    assert.isFalse((done.body() as any).data.isNew)
    await existing.refresh()
    assert.equal(existing.googleId, PROFILE.sub)
    assert.isNotNull(existing.nickname)
  })

  test('no vincula si Google no verificó el email', async ({ client }) => {
    useFake(new FakeGoogle({ ...PROFILE, emailVerified: false }))
    await User.create({ email: PROFILE.email, password: 'secreto-123', fullName: null })
    const login = await start(client)
    const res6 = await browserLogin(client, login.url)
    res6.assertStatus(400)
    const res7 = await poll(client, login)
    res7.assertBodyContains({ error: 'email_in_use' })
  })

  test('limita los logins iniciados por IP', async ({ client }) => {
    useFake(new FakeGoogle(PROFILE), { startsPerIp: 2 })
    const res8 = await client.post('/api/v1/auth/google/start')
    res8.assertStatus(200)
    const res9 = await client.post('/api/v1/auth/google/start')
    res9.assertStatus(200)
    const res10 = await client.post('/api/v1/auth/google/start')
    res10.assertStatus(429)
  })
})

test.group('Perfil del jugador', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('cambia el apodo; no permite duplicados sin importar mayúsculas', async ({
    client,
    assert,
  }) => {
    const ana = await User.create({
      email: 'ana@example.com',
      googleId: 'g-1',
      nickname: 'Ana1234',
    })
    const beto = await User.create({
      email: 'beto@example.com',
      googleId: 'g-2',
      nickname: 'Beto5678',
    })

    const ok = await client
      .patch('/api/v1/account/profile')
      .loginAs(ana)
      .json({ nickname: 'Peña_Ana' })
    ok.assertStatus(200)
    assert.equal((ok.body() as any).data.nickname, 'Peña_Ana')

    const taken = await client
      .patch('/api/v1/account/profile')
      .loginAs(beto)
      .json({ nickname: 'peña_ana' })
    taken.assertStatus(409)

    const invalid = await client
      .patch('/api/v1/account/profile')
      .loginAs(beto)
      .json({ nickname: 'a b' })
    invalid.assertStatus(422)
  })

  test('elegir personaje (skin) sin tocar el apodo', async ({ client, assert }) => {
    const ana = await User.create({
      email: 'ana@example.com',
      googleId: 'g-1',
      nickname: 'Ana1234',
    })

    const ok = await client.patch('/api/v1/account/profile').loginAs(ana).json({ skin: 'player04' })
    ok.assertStatus(200)
    assert.equal((ok.body() as any).data.skin, 'player04')
    assert.equal((ok.body() as any).data.nickname, 'Ana1234')

    const invalid = await client
      .patch('/api/v1/account/profile')
      .loginAs(ana)
      .json({ skin: '../secreto' })
    invalid.assertStatus(422)
  })

  test('una cuenta de Google no puede entrar con contraseña', async ({ client }) => {
    await User.create({ email: 'ana@example.com', googleId: 'g-1', nickname: 'Ana1234' })
    const res = await client
      .post('/api/v1/auth/login')
      .json({ email: 'ana@example.com', password: 'loquesea' })
    res.assertStatus(400)
    res.assertBodyContains({ error: 'use_google' })
  })
})
