import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import db from '@adonisjs/lucid/services/db'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'
import { PlayerStatsService } from '#services/player_stats_service'

async function makeUser() {
  return User.create({ email: 'ana@example.com', googleId: 'g-1', nickname: 'Ana1234' })
}

function byKey(body: any) {
  return Object.fromEntries((body.stats as any[]).map((s) => [s.key, s]))
}

/** Simula que el último cambio de un stat fue hace `seconds` segundos. */
async function age(userId: number, key: string, seconds: number) {
  await db
    .from('player_stats')
    .where({ user_id: userId, key })
    .update({ updated_at: new Date(Date.now() - seconds * 1000) })
}

test.group('Stats del jugador', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.teardown(() => {
    app.config.set('oauth.devLogin.enabled', true)
  })

  test('requiere sesión', async ({ client }) => {
    const res = await client.get('/api/v1/player/stats')
    res.assertStatus(401)
  })

  test('un jugador nuevo tiene los valores iniciales del catálogo', async ({ client, assert }) => {
    const user = await makeUser()
    const res = await client.get('/api/v1/player/stats').loginAs(user)
    res.assertStatus(200)
    const stats = byKey(res.body())
    assert.equal(stats.hunger.value, 100)
    assert.equal(stats.hunger.max, 100)
    assert.equal(stats.money.value, 100)
    assert.equal(stats.xp.value, 0)
    assert.deepEqual(stats.xp.level, { level: 1, current: 0, needed: 100, progress: 0 })
    assert.deepEqual(
      (res.body() as any).stats.map((s: any) => s.key),
      ['hunger', 'xp', 'money']
    )
  })

  test('el hambre baja con el tiempo jugado, no con el tiempo desconectado', async ({
    client,
    assert,
  }) => {
    const user = await makeUser()
    let res = await client.post('/api/v1/player/heartbeat').loginAs(user)
    assert.equal(byKey(res.body()).hunger.value, 100) // primer latido: sin desgaste

    await age(user.id, 'hunger', 60) // un minuto jugando
    res = await client.post('/api/v1/player/heartbeat').loginAs(user)
    assert.closeTo(byKey(res.body()).hunger.value, 99.5, 0.05)

    await age(user.id, 'hunger', 6 * 3600) // 6 horas sin jugar: cuenta como máximo 2 min
    res = await client.post('/api/v1/player/heartbeat').loginAs(user)
    assert.closeTo(byKey(res.body()).hunger.value, 98.5, 0.05)
    assert.equal((res.body() as any).nextHeartbeat, 60)
  })

  test('respeta los límites y redondea los enteros', async ({ assert }) => {
    const user = await makeUser()
    const stats = await app.container.make(PlayerStatsService)
    assert.equal(await stats.add(user.id, 'money', -500), 0)
    assert.equal(await stats.add(user.id, 'money', 10.6), 11)
    assert.equal(await stats.add(user.id, 'hunger', 50), 100)
    assert.equal(await stats.set(user.id, 'hunger', -3), 0)
  })

  test('el nivel sale de la experiencia acumulada', async ({ client, assert }) => {
    const user = await makeUser()
    const stats = await app.container.make(PlayerStatsService)
    await stats.set(user.id, 'xp', 150) // nivel 1 cuesta 100 → nivel 2 con 50 de 283
    const res = await client.get('/api/v1/player/stats').loginAs(user)
    const { level } = byKey(res.body()).xp
    assert.equal(level.level, 2)
    assert.equal(level.current, 50)
    assert.equal(level.needed, 283)
  })

  test('la ruta de desarrollo modifica stats solo en local', async ({ client, assert }) => {
    const user = await makeUser()
    let res = await client
      .post('/api/v1/player/stats/dev')
      .loginAs(user)
      .json({ key: 'money', delta: 250 })
    res.assertStatus(200)
    assert.equal(byKey(res.body()).money.value, 350)

    res = await client
      .post('/api/v1/player/stats/dev')
      .loginAs(user)
      .json({ key: 'nope', value: 1 })
    res.assertStatus(422)

    res = await client
      .post('/api/v1/player/stats/dev')
      .loginAs(user)
      .header('x-forwarded-for', '203.0.113.7')
      .json({ key: 'money', delta: 1 })
    res.assertStatus(404)

    app.config.set('oauth.devLogin.enabled', false)
    res = await client
      .post('/api/v1/player/stats/dev')
      .loginAs(user)
      .json({ key: 'money', delta: 1 })
    res.assertStatus(404)
  })
})
