/* eslint-disable @unicorn/no-await-expression-member */
import { test } from '@japa/runner'
import app from '@adonisjs/core/services/app'
import db from '@adonisjs/lucid/services/db'
import testUtils from '@adonisjs/core/services/test_utils'
import User from '#models/user'
import mapConfig from '#config/map'
import { encodeChunk } from '#map/chunk_codec'
import { Ground, NO_PROP, Prop } from '#map/catalog'
import { GameService } from '#game/game_service'
import { WorldIndex } from '#game/world_index'
import type { GameEvent } from '#game/types'

const SIZE = 64
/** Chunk de prueba (sus coordenadas pares lo dejan en la esquina de un sector). */
const CHUNK = { x: 77128, y: 127712 }
const ORIGIN = { x: CHUNK.x * SIZE, y: CHUNK.y * SIZE }

const POIS = {
  panaderia: { id: 'n1', kind: 'shop:bakery', cat: 'food', name: 'Pan de Prueba', cell: [20, 20] },
  tienda: {
    id: 'n2',
    kind: 'shop:convenience',
    cat: 'shop',
    name: 'Tienda La Prueba',
    cell: [40, 20],
  },
  biblioteca: {
    id: 'n3',
    kind: 'amenity:library',
    cat: 'education',
    name: 'Biblioteca',
    cell: [20, 45],
  },
  ferreteria: { id: 'n4', kind: 'shop:hardware', cat: 'shop', name: 'Ferretería', cell: [50, 50] },
  restaurante: {
    id: 'n5',
    kind: 'amenity:restaurant',
    cat: 'food',
    name: 'El Corrientazo',
    cell: [5, 40],
  },
} as const
const TREE = [10, 10]
const BUSH = [12, 10]

let game: GameService
const positions = new Map<number, { x: number; y: number }>()
const notices: { userId: number; events: GameEvent[] }[] = []
const broadcasts: any[] = []

/** Guarda en la base un chunk hecho a mano: andén, una calle, un árbol, un arbusto y lugares. */
async function seedChunk() {
  const ground = new Uint8Array(SIZE * SIZE).fill(Ground.PAVEMENT)
  for (let x = 0; x < SIZE; x++) ground[30 * SIZE + x] = Ground.ASPHALT
  const props = new Uint8Array(SIZE * SIZE).fill(NO_PROP)
  props[TREE[1] * SIZE + TREE[0]] = Prop.TREE
  props[BUSH[1] * SIZE + BUSH[0]] = Prop.BUSH
  const { data, etag } = encodeChunk(
    {
      z: mapConfig.chunkZoom,
      x: CHUNK.x,
      y: CHUNK.y,
      size: SIZE,
      ground,
      props,
      levels: new Uint8Array(SIZE * SIZE),
      roofs: new Uint8Array(SIZE * SIZE),
      pois: Object.values(POIS).map((p) => ({ ...p, cell: [...p.cell] as [number, number] })),
      labels: [],
      district: null,
    },
    {
      cellZoom: mapConfig.cellZoom,
      generatorVersion: mapConfig.generatorVersion,
      osmTimestamp: null,
      attribution: 'test',
    }
  )
  await db.rawQuery(
    `INSERT INTO map_chunks (z, x, y, generator_version, data, etag, byte_size, bounds, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ST_MakeEnvelope(0, 0, 1, 1, 4326), now())`,
    [mapConfig.chunkZoom, CHUNK.x, CHUNK.y, mapConfig.generatorVersion, data, etag, data.length]
  )
}

function makeUser(name: string) {
  return User.create({ email: `${name.toLowerCase()}@game.test`, nickname: name })
}

/** Pone al jugador en una celda local del chunk de prueba (como si estuviera conectado). */
function stand(user: User, cell: readonly number[]) {
  positions.set(user.id, { x: ORIGIN.x + cell[0] + 0.5, y: ORIGIN.y + cell[1] + 0.5 })
}

function ref(poi: { id: string }) {
  return { id: poi.id, cx: CHUNK.x, cy: CHUNK.y }
}

function stat(body: any, key: string) {
  return body.stats.find((s: any) => s.key === key).value
}

function eventsOf(body: any, type: string) {
  return (body.events as GameEvent[]).filter((e) => e.type === type)
}

test.group('Mecánicas del juego', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())
  group.each.setup(async () => {
    game = await app.container.make(GameService)
    ;(await app.container.make(WorldIndex)).clear()
    positions.clear()
    notices.length = 0
    broadcasts.length = 0
    game.connect({
      position: (userId) => positions.get(userId) ?? null,
      notify: (userId, events) => notices.push({ userId, events }),
      broadcastObject: (_x, _y, payload) => broadcasts.push(payload),
    })
    await seedChunk()
  })

  test('requiere sesión', async ({ client }) => {
    const res = await client.get('/api/v1/game/state')
    res.assertStatus(401)
  })

  test('el catálogo trae objetos, recetas, logros e historia', async ({ client, assert }) => {
    const user = await makeUser('Cata')
    const res = await client.get('/api/v1/game/catalog').loginAs(user)
    res.assertStatus(200)
    const body = res.body() as any
    assert.isAbove(body.items.length, 40)
    assert.isAbove(body.achievements.length, 100)
    assert.lengthOf(body.chapters, 9)
    assert.equal(body.rules.sectorCells, 128)
  })

  test('un jugador nuevo empieza el tutorial y recibe el premio del día', async ({
    client,
    assert,
  }) => {
    const user = await makeUser('Nueva')
    const res = await client.get('/api/v1/game/state').loginAs(user)
    res.assertStatus(200)
    const body = res.body() as any
    assert.equal(body.story.chapter.key, 'tutorial')
    assert.equal(body.story.dialog.npc, 'mona')
    assert.equal(body.story.goals[0].done, false)
    assert.equal(stat(body, 'money'), 120) // 100 iniciales + 20 del día
    assert.lengthOf(eventsOf(body, 'reward'), 1)

    // El mismo día no se repite el premio.
    const again = await client.get('/api/v1/game/state').loginAs(user)
    assert.equal(stat(again.body(), 'money'), 120)
  })

  test('hay que estar cerca de un lugar para entrar; la primera visita lo descubre', async ({
    client,
    assert,
  }) => {
    const user = await makeUser('Visita')
    const visit = () =>
      client
        .post('/api/v1/game/places/visit')
        .json({ poi: ref(POIS.panaderia) })
        .loginAs(user)

    let res: any = await visit()
    res.assertStatus(409) // no está en el mundo

    stand(user, [60, 60])
    res = await visit()
    res.assertStatus(422)
    assert.equal((res.body() as any).error, 'too_far')

    stand(user, [21, 21])
    res = await visit()
    res.assertStatus(200)
    const body = res.body() as any
    assert.equal(body.place.label, 'Panadería')
    assert.equal(body.place.npc.portrait, 'panadero')
    assert.isNotEmpty(body.place.sells)
    assert.lengthOf(eventsOf(body, 'discover'), 1)
    assert.equal(stat(body, 'xp'), 12)
    assert.equal(body.place.sector.points, 6)

    // La segunda vez ya no es nueva.
    res = await visit()
    assert.lengthOf(eventsOf(res.body(), 'discover'), 0)
    assert.equal(stat(res.body(), 'xp'), 12)
  })

  test('comprar comida, comerla y vender', async ({ client, assert }) => {
    const user = await makeUser('Compra')
    stand(user, POIS.panaderia.cell)
    const place = (
      (
        await client
          .post('/api/v1/game/places/visit')
          .json({ poi: ref(POIS.panaderia) })
          .loginAs(user)
      ).body() as any
    ).place
    const offer = place.sells[0]
    let res: any = await client
      .post('/api/v1/game/places/buy')
      .json({ poi: ref(POIS.panaderia), item: offer.item, qty: 2 })
      .loginAs(user)
    res.assertStatus(200)
    let body = res.body() as any
    assert.equal(body.inventory.items[offer.item], 2)
    assert.equal(stat(body, 'money'), 100 - offer.price * 2)

    res = await client
      .post('/api/v1/game/places/buy')
      .json({ poi: ref(POIS.panaderia), item: 'puesto', qty: 1 })
      .loginAs(user)
    res.assertStatus(422)

    // Con la barriga llena no se come.
    res = await client.post('/api/v1/game/items/use').json({ item: offer.item }).loginAs(user)
    res.assertStatus(422)
    await db.from('player_stats').where({ user_id: user.id, key: 'hunger' }).update({ value: 40 })
    await db
      .insertQuery()
      .table('player_stats')
      .insert({ user_id: user.id, key: 'hunger', value: 40, updated_at: new Date() })
      .knexQuery.onConflict(['user_id', 'key'])
      .merge(['value'])
    res = await client.post('/api/v1/game/items/use').json({ item: offer.item }).loginAs(user)
    res.assertStatus(200)
    body = res.body() as any
    assert.isAbove(stat(body, 'hunger'), 40)
    assert.equal(body.inventory.items[offer.item], 1)

    res = await client
      .post('/api/v1/game/places/sell')
      .json({ poi: ref(POIS.panaderia), item: offer.item, qty: 1 })
      .loginAs(user)
    res.assertStatus(200)
    assert.isUndefined((res.body() as any).inventory.items[offer.item])
  })

  test('rebuscar en un árbol da materiales y luego hay que esperar', async ({ client, assert }) => {
    const user = await makeUser('Rebusca')
    stand(user, [11, 11])
    const cell = { x: ORIGIN.x + TREE[0], y: ORIGIN.y + TREE[1] }
    let res: any = await client.post('/api/v1/game/gather').json(cell).loginAs(user)
    res.assertStatus(200)
    res = await client.post('/api/v1/game/gather').json(cell).loginAs(user)
    res.assertStatus(422)
    assert.equal((res.body() as any).error, 'cooldown')
    // Donde no hay nada, no hay nada.
    res = await client
      .post('/api/v1/game/gather')
      .json({ x: ORIGIN.x + 11, y: ORIGIN.y + 12 })
      .loginAs(user)
    res.assertStatus(422)
  })

  test('fabricar una matera, colocarla y que otro la riegue', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    stand(ana, [15, 15])
    await game.dev(ana.id, 'give', { item: 'palo', qty: 4 })
    await game.dev(ana.id, 'give', { item: 'hoja', qty: 2 })
    await game.dev(ana.id, 'give', { item: 'semilla', qty: 1 })

    let res: any = await client.post('/api/v1/game/craft').json({ recipe: 'matera' }).loginAs(ana)
    res.assertStatus(200)
    assert.equal((res.body() as any).inventory.items.matera, 1)
    assert.isUndefined((res.body() as any).inventory.items.palo)

    // En la calle no se puede.
    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'matera', x: ORIGIN.x + 15, y: ORIGIN.y + 30 })
      .loginAs(ana)
    res.assertStatus(422)
    // Ni pegado a la biblioteca.
    stand(ana, [21, 44])
    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'matera', x: ORIGIN.x + 21, y: ORIGIN.y + 44 })
      .loginAs(ana)
    res.assertStatus(422)

    stand(ana, [15, 15])
    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'matera', x: ORIGIN.x + 16, y: ORIGIN.y + 15 })
      .loginAs(ana)
    res.assertStatus(200)
    const object = (res.body() as any).object
    assert.equal(object.kind, 'matera')
    assert.equal(object.ownerName, 'Ana')
    assert.isTrue(broadcasts.some((b) => b.op === 'put' && b.o.id === object.id))

    res = await client
      .get('/api/v1/game/objects')
      .qs({ cx0: CHUNK.x, cy0: CHUNK.y, cx1: CHUNK.x, cy1: CHUNK.y })
      .loginAs(beto)
    assert.lengthOf((res.body() as any).objects, 1)

    stand(beto, [17, 16])
    const water = () =>
      client.post(`/api/v1/game/objects/${object.id}/act`).json({ action: 'water' }).loginAs(beto)
    res = await water()
    res.assertStatus(200)
    assert.equal((res.body() as any).object.state.stage, 1)
    res = await water()
    res.assertStatus(422) // una vez al día

    // Solo la dueña la puede recoger.
    res = await client
      .post(`/api/v1/game/objects/${object.id}/act`)
      .json({ action: 'pickup' })
      .loginAs(beto)
    res.assertStatus(403)
    res = await client
      .post(`/api/v1/game/objects/${object.id}/act`)
      .json({ action: 'pickup' })
      .loginAs(ana)
    res.assertStatus(200)
    assert.equal((res.body() as any).inventory.items.matera, 1)
  })

  test('un domicilio: aceptar, recoger, entregar y cobrar', async ({ client, assert }) => {
    const user = await makeUser('Domi')
    stand(user, [30, 25])
    let jobs: any[] = []
    // El tablero se arma al azar: se piden hasta que salga un domicilio.
    for (let i = 0; i < 20 && !jobs.some((j) => j.kind === 'delivery'); i++) {
      await db.from('player_state').where('user_id', user.id).delete()
      await db.from('player_jobs').where('user_id', user.id).delete()
      jobs = ((await client.get('/api/v1/game/jobs').loginAs(user)).body() as any).jobs
    }
    assert.lengthOf(jobs, 4)
    const job = jobs.find((j) => j.kind === 'delivery')
    assert.exists(job)

    let res: any = await client.post(`/api/v1/game/jobs/${job.id}/accept`).loginAs(user)
    res.assertStatus(200)
    const [pickup, deliver] = job.steps
    const at = (step: any) => [step.poi.x - ORIGIN.x, step.poi.y - ORIGIN.y]

    // No se puede entregar sin recoger.
    stand(user, at(deliver))
    res = await client
      .post(`/api/v1/game/jobs/${job.id}/step`)
      .json({ poi: ref(deliver.poi) })
      .loginAs(user)
    res.assertStatus(422)

    stand(user, at(pickup))
    res = await client
      .post(`/api/v1/game/jobs/${job.id}/step`)
      .json({ poi: ref(pickup.poi) })
      .loginAs(user)
    res.assertStatus(200)
    const before = stat(res.body(), 'money')

    stand(user, at(deliver))
    res = await client
      .post(`/api/v1/game/jobs/${job.id}/step`)
      .json({ poi: ref(deliver.poi) })
      .loginAs(user)
    res.assertStatus(200)
    const body = res.body() as any
    // Además de la paga llegan premios de logros (primer domicilio…).
    assert.isAtLeast(stat(body, 'money'), before + job.reward.money)
    assert.isTrue(eventsOf(body, 'achievement').some((e: any) => e.key === 'domicilios_1'))
    assert.isFalse(body.jobs.some((j: any) => j.id === job.id))
  })

  test('trabajar un turno paga, da hambre y tiene espera', async ({ client, assert }) => {
    const user = await makeUser('Turno')
    stand(user, POIS.tienda.cell)
    const work = () =>
      client
        .post('/api/v1/game/places/work')
        .json({ poi: ref(POIS.tienda) })
        .loginAs(user)
    let res: any = await work()
    res.assertStatus(200)
    const body = res.body() as any
    assert.isAbove(stat(body, 'money'), 100)
    assert.equal(stat(body, 'hunger'), 94)
    assert.isAbove(body.place.work.wait, 0)
    res = await work()
    res.assertStatus(422)
  })

  test('con influencia y bandera se domina un sector, y paga renta', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    stand(ana, [25, 25])
    stand(beto, [26, 26])
    await game.dev(ana.id, 'influence', { points: 200 })
    await game.dev(ana.id, 'give', { item: 'bandera', qty: 2 })

    let res: any = await client.get('/api/v1/game/territory').loginAs(ana)
    let here = (res.body() as any).sectors.find((s: any) => s.points > 0)
    assert.equal(here.rank, 3)
    assert.isNull(here.owner) // sin bandera no hay dueño

    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'bandera', x: ORIGIN.x + 25, y: ORIGIN.y + 26 })
      .loginAs(ana)
    res.assertStatus(200)
    assert.isTrue(eventsOf(res.body(), 'sector').some((e: any) => e.kind === 'owned'))

    // Una sola bandera por sector.
    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'bandera', x: ORIGIN.x + 24, y: ORIGIN.y + 26 })
      .loginAs(ana)
    res.assertStatus(422)

    res = await client.get('/api/v1/game/territory').loginAs(beto)
    here = (res.body() as any).sectors.find((s: any) => s.owner)
    assert.equal(here.owner.name, 'Ana')
    assert.isFalse(here.mine)

    // Beto la supera con su propia bandera: Ana pierde el sector y se entera.
    await game.dev(beto.id, 'give', { item: 'bandera', qty: 1 })
    await game.dev(beto.id, 'influence', { points: 400 })
    res = await client
      .post('/api/v1/game/objects')
      .json({ item: 'bandera', x: ORIGIN.x + 27, y: ORIGIN.y + 26 })
      .loginAs(beto)
    res.assertStatus(200)
    assert.isTrue(
      notices.some((n) => n.userId === ana.id && n.events.some((e: any) => e.kind === 'lost'))
    )

    // La renta se acumula con el tiempo.
    res = await client.post('/api/v1/game/territory/collect').loginAs(beto)
    res.assertStatus(422)
    const state = await db.from('player_state').where('user_id', beto.id).first()
    const data = typeof state.data === 'string' ? JSON.parse(state.data) : state.data
    data.rentAt = Date.now() - 86_400_000
    await db
      .from('player_state')
      .where('user_id', beto.id)
      .update({ data: JSON.stringify(data) })
    const money = stat((await client.get('/api/v1/game/state').loginAs(beto)).body(), 'money')
    res = await client.post('/api/v1/game/territory/collect').loginAs(beto)
    res.assertStatus(200)
    assert.isAtLeast(stat(res.body(), 'money'), money + 30)
  })

  test('un puesto: el dueño surte, otro compra y el dueño cobra', async ({ client, assert }) => {
    const ana = await makeUser('Ana')
    const beto = await makeUser('Beto')
    stand(ana, [35, 40])
    stand(beto, [36, 41])
    await game.dev(ana.id, 'give', { item: 'puesto', qty: 1 })
    await game.dev(ana.id, 'give', { item: 'arepa', qty: 5 })
    let res: any = await client
      .post('/api/v1/game/objects')
      .json({ item: 'puesto', x: ORIGIN.x + 35, y: ORIGIN.y + 41 })
      .loginAs(ana)
    const id = (res.body() as any).object.id
    const act = (user: User, body: object) =>
      client.post(`/api/v1/game/objects/${id}/act`).json(body).loginAs(user)

    res = await act(beto, { action: 'stock', item: 'arepa', qty: 1, price: 10 })
    res.assertStatus(403)
    res = await act(ana, { action: 'stock', item: 'arepa', qty: 5, price: 500 })
    res.assertStatus(422) // precio absurdo
    res = await act(ana, { action: 'stock', item: 'arepa', qty: 5, price: 20 })
    res.assertStatus(200)
    assert.isTrue((res.body() as any).object.state.open)

    res = await act(beto, { action: 'buy', item: 'arepa', qty: 2 })
    res.assertStatus(200)
    assert.equal((res.body() as any).inventory.items.arepa, 2)
    assert.equal(stat(res.body(), 'money'), 60)
    assert.isUndefined((res.body() as any).detail.till) // la caja solo la ve la dueña

    res = await act(ana, { action: 'collect' })
    res.assertStatus(200)
    assert.isAtLeast(stat(res.body(), 'money'), 140) // 100 + 40 de ventas (+ logros)
    res = await act(ana, { action: 'pickup' })
    res.assertStatus(422) // no está vacío
  })

  test('la historia avanza con lo que hace el jugador y da logros', async ({ client, assert }) => {
    const user = await makeUser('Historia')
    stand(user, [21, 21])
    await client.get('/api/v1/game/state').loginAs(user)

    // Paso 1 del tutorial: caminar (lo cuenta el servidor en tiempo real).
    await game.track(user.id, 'distance_m', 30)
    const walked = notices.find((n) => n.userId === user.id)
    assert.exists(walked)
    assert.isTrue(walked!.events.some((e) => e.type === 'dialog'))

    // Paso 2: visitar un lugar. El siguiente paso regala empanadas.
    let res: any = await client
      .post('/api/v1/game/places/visit')
      .json({ poi: ref(POIS.panaderia) })
      .loginAs(user)
    let body = res.body() as any
    assert.equal(body.inventory.items.empanada, 2)
    assert.equal(body.story.goals[0].text, 'Cómete una empanada')

    // Hablar con un personaje solo cuando la historia lo pide.
    res = await client
      .post('/api/v1/game/story/talk')
      .json({ poi: ref(POIS.panaderia) })
      .loginAs(user)
    res.assertStatus(422)

    // Con el tutorial saltado, Don Chepe atiende en la tienda.
    for (let i = 0; i < 6; i++) await game.dev(user.id, 'skip', {})
    res = await client.get('/api/v1/game/state').loginAs(user)
    body = res.body() as any
    assert.equal(body.story.chapter.key, 'rebusque')
    assert.include(body.achievements, 'historia_1')
    assert.isAbove(stat(body, 'money'), 150)

    stand(user, POIS.tienda.cell)
    res = await client
      .post('/api/v1/game/story/talk')
      .json({ poi: ref(POIS.tienda) })
      .loginAs(user)
    res.assertStatus(200)
    body = res.body() as any
    assert.equal((eventsOf(body, 'dialog')[0] as any).npc, 'chepe')
    assert.lengthOf(body.story.goals, 3) // ya está en el paso de trabajar

    // Por teléfono no contesta si hay un lugar cerca.
    res = await client.post('/api/v1/game/story/talk').json({}).loginAs(user)
    res.assertStatus(422)
  })
})
