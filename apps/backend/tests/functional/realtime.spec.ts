import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import testUtils from '@adonisjs/core/services/test_utils'
import { WebSocket } from 'ws'
import User from '#models/user'
import realtimeConfig from '#config/realtime'
import { GameRealtimeServer, CLOSE } from '#realtime/game_server'

/** Celda global de referencia (Bogotá, z24): ~2,4 m por celda. */
const BASE = { x: 4_957_000.5, y: 8_330_000.5 }

let realtime: GameRealtimeServer
const sockets: WebSocket[] = []

/** Cliente de prueba: guarda los mensajes y permite esperar uno por tipo. */
async function connect(token: string | null) {
  const url = `ws://${process.env.HOST || 'localhost'}:${process.env.PORT || 3333}${realtimeConfig.path}`
  const ws = new WebSocket(url)
  sockets.push(ws)
  const inbox: any[] = []
  const waiters: { pred: (m: any) => boolean; resolve: (m: any) => void }[] = []
  ws.on('message', (data) => {
    const msg = JSON.parse(data.toString())
    const i = waiters.findIndex((w) => w.pred(msg))
    if (i >= 0) waiters.splice(i, 1)[0].resolve(msg)
    else inbox.push(msg)
  })
  await new Promise((resolve, reject) => ws.once('open', resolve).once('error', reject))

  const client = {
    ws,
    send: (msg: object) => ws.send(JSON.stringify(msg)),
    /** Espera (o toma del buzón) el próximo mensaje que cumpla `pred`. */
    next(pred: (m: any) => boolean, timeoutMs = 1500): Promise<any> {
      const i = inbox.findIndex(pred)
      if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0])
      return new Promise((resolve, reject) => {
        const waiter = { pred, resolve }
        waiters.push(waiter)
        setTimeout(() => {
          const j = waiters.indexOf(waiter)
          if (j >= 0) {
            waiters.splice(j, 1)
            reject(new Error('timeout esperando mensaje'))
          }
        }, timeoutMs)
      })
    },
    closed: () =>
      new Promise<number>((resolve) =>
        ws.readyState === WebSocket.CLOSED ? resolve(0) : ws.once('close', (code) => resolve(code))
      ),
    clearInbox: () => inbox.splice(0),
  }
  if (token) {
    client.send({ t: 'auth', token })
    await client.next((m) => m.t === 'welcome')
  }
  return client
}

async function player(name: string) {
  const user = await User.create({ email: `${name}@realtime.test`, nickname: name, fullName: name })
  const token = await User.accessTokens.create(user, ['*'], { name: 'game' })
  return { user, token: token.value!.release() }
}

/** Crea un jugador y lo conecta. */
async function joinAs(name: string) {
  const { token } = await player(name)
  return connect(token)
}

const state = (x: number, y: number, extra: object = {}) => ({
  t: 'state',
  x,
  y,
  d: 2,
  m: 1,
  ...extra,
})
const ofType = (t: string) => (m: any) => m.t === t

test.group('Multijugador (WebSocket)', (group) => {
  group.setup(async () => {
    // El mismo que usa la app (el perfil le avisa de los cambios de apodo/personaje).
    realtime = await app.container.make(GameRealtimeServer)
    const server = await app.container.make('server')
    realtime.attach(server.getNodeServer())
  })
  group.teardown(() => realtime.close())
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.teardown(async () => {
    for (const ws of sockets.splice(0)) ws.terminate()
    await new Promise((r) => setTimeout(r, 30))
  })

  test('rechaza conexiones sin token válido', async ({ assert }) => {
    const anon = await connect(null)
    anon.send({ t: 'auth', token: 'oat_no.valido' })
    assert.equal(await anon.closed(), CLOSE.unauthorized)

    const rude = await connect(null)
    rude.send(state(1, 1))
    assert.equal(await rude.closed(), CLOSE.unauthorized)
  })

  test('dos jugadores cercanos se ven con nickname y nivel', async ({ assert }) => {
    const ana = await player('ana')
    const beto = await player('beto')
    const a = await connect(ana.token)
    const b = await connect(beto.token)
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 5, BASE.y + 3, { d: 4, m: 2 }))

    const snap = await a.next((m) => m.t === 'snap' && m.p.length === 1)
    assert.deepEqual(snap.p[0], [beto.user.id, BASE.x + 5, BASE.y + 3, 4, 2])
    assert.deepEqual(snap.info[beto.user.id], { n: 'beto', lv: 1, s: null })

    const fromB = await b.next((m) => m.t === 'snap' && m.p.length === 1)
    assert.equal(fromB.p[0][0], ana.user.id)

    // El nickname va solo la primera vez.
    const again = await a.next((m) => m.t === 'snap' && m.p.length === 1)
    assert.isUndefined(again.info)
  })

  test('un jugador lejano solo aparece en el radar, sin id y redondeado', async ({ assert }) => {
    const a = await joinAs('ana')
    const b = await joinAs('beto')
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 200.3, BASE.y + 1.7)) // ~480 m: fuera de pantalla, dentro del radar

    const radar = await a.next((m) => m.t === 'radar' && m.p.length === 1)
    const [x, y] = radar.p[0]
    assert.lengthOf(radar.p[0], 2)
    assert.notEqual(x, BASE.x + 200.3)
    assert.approximately(x, BASE.x + 200.3, 10)
    assert.approximately(y, BASE.y + 1.7, 10)

    // Y nunca en un snap.
    await new Promise((r) => setTimeout(r, 250))
    assert.isFalse(a.clearInbox().some((m) => m.t === 'snap' && m.p.length > 0))
  })

  test('fuera del radio de alcance no aparece', async ({ assert }) => {
    const a = await joinAs('ana')
    const b = await joinAs('beto')
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 1000, BASE.y)) // ~2,4 km

    const radar = await a.next(ofType('radar'))
    assert.lengthOf(radar.p, 0)
  })

  test('rechaza movimientos demasiado rápidos; el teletransporte usa spawn', async ({ assert }) => {
    const a = await joinAs('ana')
    const b = await joinAs('beto')
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 2, BASE.y))
    await a.next((m) => m.t === 'snap' && m.p.length === 1)

    b.send(state(BASE.x + 30, BASE.y)) // 28 celdas de golpe
    const reject = await b.next(ofType('reject'))
    assert.equal(reject.r, 'speed')
    a.clearInbox()
    const snap = await a.next((m) => m.t === 'snap' && m.p.length === 1)
    assert.equal(snap.p[0][1], BASE.x + 2)

    // spawn recién aparecido: hay que esperar minSpawnIntervalMs
    b.send(state(BASE.x + 30, BASE.y, { spawn: true }))
    const tooSoon = await b.next(ofType('reject'))
    assert.equal(tooSoon.r, 'spawn')
  })

  test('las acciones llegan a los jugadores cercanos', async ({ assert }) => {
    const ana = await player('ana')
    const a = await connect(ana.token)
    const b = await joinAs('beto')
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 4, BASE.y))
    await b.next((m) => m.t === 'snap' && m.p.length === 1)

    a.send({ t: 'act', k: 'wave' })
    assert.deepEqual(await b.next(ofType('act')), { t: 'act', id: ana.user.id, k: 'wave' })

    a.send({ t: 'act', k: 'bailar' }) // no existe
    const error = await a.next(ofType('error'))
    assert.equal(error.e, 'bad_message')
  })

  test('modo fantasma: no aparece para los demás', async ({ assert }) => {
    const a = await joinAs('ana')
    const b = await joinAs('beto')
    b.send({ t: 'vis', v: false })
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 3, BASE.y))
    // b ve a a, pero a no ve a b
    await b.next((m) => m.t === 'snap' && m.p.length === 1)
    const radar = await a.next(ofType('radar'))
    assert.lengthOf(radar.p, 0)
    assert.isFalse(a.clearInbox().some((m) => m.t === 'snap' && m.p.length > 0))
  })

  test('una segunda conexión de la misma cuenta reemplaza a la primera', async ({ assert }) => {
    const ana = await player('ana')
    const first = await connect(ana.token)
    await connect(ana.token)
    assert.equal(await first.closed(), CLOSE.replaced)
    assert.equal(realtime.connected, 1)
  })

  test('cambiar de personaje se ve al momento en los cercanos', async ({ assert, client }) => {
    const ana = await player('ana')
    const beto = await player('beto')
    const a = await connect(ana.token)
    const b = await connect(beto.token)
    a.send(state(BASE.x, BASE.y))
    b.send(state(BASE.x + 3, BASE.y))
    await a.next((m) => m.t === 'snap' && m.info?.[beto.user.id])

    const res = await client
      .patch('/api/v1/account/profile')
      .bearerToken(beto.token)
      .json({ skin: 'player03' })
    res.assertStatus(200)
    assert.equal((res.body() as any).data.skin, 'player03')

    const update = await a.next((m) => m.t === 'snap' && m.info?.[beto.user.id])
    assert.deepEqual(update.info[beto.user.id], { n: 'beto', lv: 1, s: 'player03' })
  })

  test('responde ping con pong', async ({ assert }) => {
    const a = await joinAs('ana')
    a.send({ t: 'ping', c: 42 })
    assert.deepEqual(await a.next(ofType('pong')), { t: 'pong', c: 42 })
  })
})
