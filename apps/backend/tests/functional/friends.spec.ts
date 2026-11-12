import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import testUtils from '@adonisjs/core/services/test_utils'
import { WebSocket } from 'ws'
import User from '#models/user'
import realtimeConfig from '#config/realtime'
import { GameRealtimeServer } from '#realtime/game_server'

let realtime: GameRealtimeServer
const sockets: WebSocket[] = []

function makeUser(nickname: string) {
  return User.create({ email: `${nickname.toLowerCase()}@friends.test`, nickname })
}

/** Conecta al jugador al multijugador y devuelve los mensajes que recibe. */
async function goOnline(user: User) {
  const accessToken = await User.accessTokens.create(user, ['*'], { name: 'game' })
  const token = accessToken.value!.release()
  const url = `ws://${process.env.HOST || 'localhost'}:${process.env.PORT || 3333}${realtimeConfig.path}`
  const ws = new WebSocket(url)
  sockets.push(ws)
  const inbox: any[] = []
  ws.on('message', (data) => inbox.push(JSON.parse(data.toString())))
  await new Promise((resolve, reject) => ws.once('open', resolve).once('error', reject))
  ws.send(JSON.stringify({ t: 'auth', token }))
  await waitFor(() => inbox.some((m) => m.t === 'welcome'))
  return { ws, inbox, send: (msg: object) => ws.send(JSON.stringify(msg)) }
}

async function waitFor(cond: () => boolean, timeoutMs = 1500) {
  const start = Date.now()
  while (!cond()) {
    if (Date.now() - start > timeoutMs) throw new Error('timeout')
    await new Promise((r) => setTimeout(r, 10))
  }
}

async function befriend(client: any, a: User, b: User) {
  await client.post('/api/v1/friends/requests').json({ nickname: b.nickname }).loginAs(a)
  const res = await client.get('/api/v1/friends').loginAs(b)
  const requestId = res.body().incoming[0].id
  await client.post(`/api/v1/friends/requests/${requestId}/accept`).loginAs(b)
}

test.group('Amigos', (group) => {
  group.setup(async () => {
    realtime = await app.container.make(GameRealtimeServer)
    const server = await app.container.make('server')
    realtime.attach(server.getNodeServer())
  })
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.teardown(async () => {
    for (const ws of sockets.splice(0)) ws.terminate()
    await new Promise((r) => setTimeout(r, 30))
  })

  test('requiere sesión', async ({ client }) => {
    const res = await client.get('/api/v1/friends')
    res.assertStatus(401)
  })

  test('busca por apodo exacto sin distinguir mayúsculas', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    await makeUser('Beto')
    let res: any = await client.get('/api/v1/friends/search').qs({ nickname: 'beto' }).loginAs(ana)
    res.assertStatus(200)
    assert.equal(res.body().user.nickname, 'Beto')
    assert.equal(res.body().user.relation, 'none')
    assert.notProperty(res.body().user, 'email')

    res = await client.get('/api/v1/friends/search').qs({ nickname: 'Bet' }).loginAs(ana)
    res.assertStatus(404)

    res = await client.get('/api/v1/friends/search').qs({ nickname: 'ana' }).loginAs(ana)
    assert.equal(res.body().user.relation, 'self')
  })

  test('enviar, ver en la bandeja y aceptar una solicitud', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')

    let res: any = await client.post('/api/v1/friends/requests').json({ nickname: 'beto' }).loginAs(ana)
    res.assertStatus(201)
    assert.equal(res.body().status, 'sent')

    res = await client.post('/api/v1/friends/requests').json({ nickname: 'Beto' }).loginAs(ana)
    res.assertStatus(409)
    assert.equal(res.body().error, 'already_requested')

    res = await client.get('/api/v1/friends').loginAs(ana)
    assert.lengthOf(res.body().outgoing, 1)
    assert.lengthOf(res.body().friends, 0)

    res = await client.get('/api/v1/friends').loginAs(beto)
    assert.lengthOf(res.body().incoming, 1)
    assert.equal(res.body().incoming[0].user.nickname, 'Ana')
    const requestId = res.body().incoming[0].id

    // Solo el destinatario puede aceptarla.
    res = await client.post(`/api/v1/friends/requests/${requestId}/accept`).loginAs(ana)
    res.assertStatus(404)

    res = await client.post(`/api/v1/friends/requests/${requestId}/accept`).loginAs(beto)
    res.assertStatus(200)

    for (const [me, other] of [
      [ana, 'Beto'],
      [beto, 'Ana'],
    ] as const) {
      res = await client.get('/api/v1/friends').loginAs(me)
      assert.deepEqual(
        res.body().friends.map((f: any) => [f.nickname, f.online]),
        [[other, false]]
      )
      assert.lengthOf(res.body().incoming, 0)
      assert.lengthOf(res.body().outgoing, 0)
    }

    res = await client.post('/api/v1/friends/requests').json({ nickname: 'Ana' }).loginAs(beto)
    res.assertStatus(409)
    assert.equal(res.body().error, 'already_friends')
  })

  test('rechazar borra la solicitud y se puede volver a enviar', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    await client.post('/api/v1/friends/requests').json({ nickname: 'Beto' }).loginAs(ana)
    let res: any = await client.get('/api/v1/friends').loginAs(beto)
    const requestId = res.body().incoming[0].id

    res = await client.delete(`/api/v1/friends/requests/${requestId}`).loginAs(beto)
    res.assertStatus(204)
    res = await client.get('/api/v1/friends').loginAs(ana)
    assert.lengthOf(res.body().outgoing, 0)

    res = await client.post('/api/v1/friends/requests').json({ nickname: 'Beto' }).loginAs(ana)
    res.assertStatus(201)
  })

  test('si los dos se envían solicitud, quedan como amigos', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    await client.post('/api/v1/friends/requests').json({ nickname: 'Beto' }).loginAs(ana)
    const res: any = await client
      .post('/api/v1/friends/requests')
      .json({ nickname: 'Ana' })
      .loginAs(beto)
    res.assertStatus(200)
    assert.equal(res.body().status, 'accepted')
  })

  test('errores al enviar: apodo inexistente o uno mismo', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    let res: any = await client.post('/api/v1/friends/requests').json({ nickname: 'Nadie' }).loginAs(ana)
    res.assertStatus(404)
    assert.equal(res.body().error, 'user_not_found')
    res = await client.post('/api/v1/friends/requests').json({ nickname: 'ana' }).loginAs(ana)
    res.assertStatus(422)
    assert.equal(res.body().error, 'self')
  })

  test('eliminar a un amigo', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    await befriend(client, ana, beto)
    let res: any = await client.delete(`/api/v1/friends/${beto.id}`).loginAs(ana)
    res.assertStatus(204)
    res = await client.get('/api/v1/friends').loginAs(beto)
    assert.lengthOf(res.body().friends, 0)
    res = await client.delete(`/api/v1/friends/${beto.id}`).loginAs(ana)
    res.assertStatus(404)
  })

  test('el destinatario conectado recibe el aviso por WebSocket', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    const b = await goOnline(beto)
    await client.post('/api/v1/friends/requests').json({ nickname: 'Beto' }).loginAs(ana)
    await waitFor(() => b.inbox.some((m) => m.t === 'friends'))
    assert.deepInclude(b.inbox, { t: 'friends', e: 'request', n: 'Ana' })
  })

  test('ubicación de un amigo: solo amigos, conectado y visible', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    const carla = await makeUser('Carla')
    await befriend(client, ana, beto)

    let res: any = await client.get(`/api/v1/friends/${beto.id}/location`).loginAs(ana)
    res.assertStatus(409)
    assert.equal(res.body().error, 'friend_offline')

    const b = await goOnline(beto)
    // Celdas globales a z24 (≈ 1.257, -73.634).
    b.send({ t: 'state', x: 4_957_000.5, y: 8_330_000.5, d: 2, m: 0 })
    await waitFor(() => realtime.locate(beto.id) !== null)

    res = await client.get(`/api/v1/friends/${beto.id}/location`).loginAs(ana)
    res.assertStatus(200)
    assert.closeTo(res.body().lat, 1.257, 0.001)
    assert.closeTo(res.body().lon, -73.634, 0.001)

    res = await client.get('/api/v1/friends').loginAs(ana)
    assert.isTrue(res.body().friends[0].online)

    // Quien no es amigo no puede verla.
    res = await client.get(`/api/v1/friends/${beto.id}/location`).loginAs(carla)
    res.assertStatus(404)

    // Modo fantasma: aparece desconectado.
    b.send({ t: 'vis', v: false })
    await waitFor(() => !realtime.isOnline(beto.id))
    res = await client.get(`/api/v1/friends/${beto.id}/location`).loginAs(ana)
    res.assertStatus(409)
  })
})
