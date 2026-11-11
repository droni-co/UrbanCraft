import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'

test.group('Login de usuarios de prueba', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.teardown(() => {
    app.config.set('oauth.devLogin.enabled', true)
  })

  test('crea el usuario de prueba y devuelve un token válido', async ({ client, assert }) => {
    const res = await client.post('/api/v1/auth/dev/login').json({ name: 'ana' })
    res.assertStatus(200)
    const { user, token, isNew } = (res.body() as any).data
    assert.isTrue(isNew)
    assert.equal(user.email, 'ana@dev.urbancraft.test')
    assert.equal(user.nickname, 'ana')

    const profile = await client.get('/api/v1/account/profile').bearerToken(token)
    profile.assertStatus(200)
  })

  test('el mismo nombre entra siempre al mismo usuario', async ({ client, assert }) => {
    const first = await client.post('/api/v1/auth/dev/login').json({ name: 'Peña' })
    const second = await client.post('/api/v1/auth/dev/login').json({ name: 'Peña' })
    assert.equal((first.body() as any).data.user.id, (second.body() as any).data.user.id)
    assert.isFalse((second.body() as any).data.isNew)
    assert.lengthOf(await User.query().where('email', 'pena@dev.urbancraft.test'), 1)
  })

  test('sin nombre usa "tester"', async ({ client, assert }) => {
    const res = await client.post('/api/v1/auth/dev/login').json({})
    res.assertStatus(200)
    assert.equal((res.body() as any).data.user.email, 'tester@dev.urbancraft.test')
  })

  test('rechaza nombres inválidos', async ({ client }) => {
    const res = await client.post('/api/v1/auth/dev/login').json({ name: 'a b' })
    res.assertStatus(422)
  })

  test('desactivado responde 404 y no se anuncia', async ({ client }) => {
    app.config.set('oauth.devLogin.enabled', false)
    const res = await client.post('/api/v1/auth/dev/login').json({ name: 'ana' })
    res.assertStatus(404)
    const methods = await client.get('/api/v1/auth/methods')
    methods.assertBodyContains({ dev: false })
  })

  test('a través de un proxy o túnel responde 404', async ({ client }) => {
    for (const header of ['x-forwarded-for', 'forwarded', 'cf-connecting-ip']) {
      const res = await client
        .post('/api/v1/auth/dev/login')
        .header(header, '203.0.113.7')
        .json({ name: 'ana' })
      res.assertStatus(404)
    }
    const methods = await client
      .get('/api/v1/auth/methods')
      .header('x-forwarded-for', '203.0.113.7')
    methods.assertBodyContains({ dev: false })
  })

  test('methods anuncia dev en local', async ({ client }) => {
    const res = await client.get('/api/v1/auth/methods')
    res.assertStatus(200)
    res.assertBodyContains({ dev: true })
  })
})
