import { test } from '@japa/runner'
import { gunzipSync } from 'node:zlib'
import app from '@adonisjs/core/services/app'
import db from '@adonisjs/lucid/services/db'
import type { MapConfig } from '#config/map'
import { Ground } from '#map/catalog'
import type { ChunkPayload } from '#map/chunk_codec'
import type { ChunkProgress } from '#services/map_chunk_service'
import { OsmProvider, OsmProviderError } from '#map/providers/osm_provider'
import { MapChunkService } from '#services/map_chunk_service'
import { MapWorker } from '#services/map_worker'
import { FakeOsmProvider, TEST_CHUNK as C, featureSet, line } from '#tests/helpers/map'

/** Versión configurada del generador (los tests no dependen de su valor). */
const VERSION = () => app.config.get<MapConfig>('map').generatorVersion

const url = (z = C.z, x = C.x, y = C.y) => `/api/v1/map/chunks/${z}/${x}/${y}`

async function expectStatus(
  request: PromiseLike<{ assertStatus(status: number): void }>,
  status: number
) {
  const response = await request
  response.assertStatus(status)
}

function setup(provider: FakeOsmProvider, overrides: Partial<MapConfig> = {}) {
  const config = { ...app.config.get<MapConfig>('map'), ...overrides }
  const service = new MapChunkService(config)
  const worker = new MapWorker(service, config.worker)
  app.container.swap(MapChunkService, () => service)
  app.container.swap(OsmProvider, () => provider)
  return { service, worker }
}

const roadProvider = () =>
  new FakeOsmProvider(
    featureSet([
      {
        kind: 'line',
        id: 'w1',
        tags: { highway: 'residential', name: 'Calle de Prueba' },
        coords: line(C, [
          [-5, 10.5],
          [70, 10.5],
        ]),
      },
    ])
  )

test.group('Map chunks API', (group) => {
  group.each.setup(async () => {
    await db.rawQuery('TRUNCATE map_chunks, osm_source_tiles RESTART IDENTITY CASCADE')
    return () => {
      app.container.restore(MapChunkService)
      app.container.restore(OsmProvider)
    }
  })

  test('config expone grilla y catálogo', async ({ client, assert }) => {
    const res = await client.get('/api/v1/map/config')
    res.assertStatus(200)
    assert.equal(res.body().chunkSize, 64)
    assert.equal(res.body().catalog.ground[Ground.BUILDING], 'BUILDING')
  })

  test('coordenadas inválidas -> 422', async ({ client }) => {
    await expectStatus(client.get(url(17)), 422)
    await expectStatus(client.get('/api/v1/map/chunks/18/abc/1'), 422)
    await expectStatus(client.get(url(18, 2 ** 18, 0)), 422)
  })

  test('primer acceso encola (202), el worker genera y luego se sirve (200)', async ({
    client,
    assert,
  }) => {
    const provider = roadProvider()
    const { worker } = setup(provider)

    const pending = await client.get(url())
    pending.assertStatus(202)
    assert.equal(pending.header('retry-after'), '5')
    const progress = pending.body() as Record<string, unknown>
    assert.equal(progress.status, 'pending')
    // Cómo va, para la barra de carga: en cola, nadie delante, hay que descargar.
    assert.equal(progress.stage, 'queued')
    assert.equal(progress.ahead, 0)
    assert.isAbove(progress.expected as number, 5)
    assert.equal(progress.attempts, 0)

    // Un segundo jugador pidiendo otro chunk del mismo source tile no duplica trabajo.
    await expectStatus(client.get(url(C.z, C.x + 1, C.y)), 202)
    const { rows } = await db.rawQuery('SELECT count(*)::int AS n FROM osm_source_tiles')
    assert.equal(rows[0].n, 1)

    assert.isTrue(await worker.processNext())
    assert.isFalse(await worker.processNext())
    assert.lengthOf(provider.calls, 1)

    const chunks = await db.rawQuery('SELECT count(*)::int AS n FROM map_chunks')
    assert.equal(chunks.rows[0].n, 64, 'se generan los 64 chunks del source tile')

    const ready = await client.get(url()).qs({ v: VERSION() })
    ready.assertStatus(200)
    assert.include(ready.header('cache-control'), 'immutable')
    assert.match(ready.header('etag') ?? '', new RegExp(`^"v${VERSION()}-[0-9a-f]{16}"$`))

    const body = ready.body() as unknown as ChunkPayload
    assert.equal(body.size, 64)
    const ground = Buffer.from(body.ground, 'base64')
    assert.lengthOf(ground, 64 * 64)
    assert.equal(ground[10 * 64 + 30], Ground.ASPHALT)
    assert.deepEqual(
      body.labels.map((l) => [l.kind, l.name]),
      [['street', 'Calle de Prueba']]
    )

    const notModified = await client.get(url()).header('If-None-Match', ready.header('etag') ?? '')
    notModified.assertStatus(304)
  })

  test('el progreso dice cuántas zonas hay delante en la cola', async ({ client, assert }) => {
    setup(roadProvider())
    await expectStatus(client.get(url()), 202)
    // Otro source tile (8 chunks más al este): queda detrás del primero.
    const second = await client.get(url(C.z, C.x + 8, C.y))
    second.assertStatus(202)
    const progress = second.body() as unknown as ChunkProgress
    assert.equal(progress.stage, 'queued')
    assert.equal(progress.ahead, 1)
    // El primero sigue sin nadie delante.
    assert.equal(((await client.get(url())).body() as unknown as ChunkProgress).ahead, 0)
  })

  test('envía el chunk comprimido tal cual está guardado', async ({ client, assert }) => {
    const { worker } = setup(roadProvider())
    await client.get(url())
    await worker.processNext()

    const res = await client.get(url()).header('Accept-Encoding', 'gzip')
    res.assertStatus(200)
    assert.equal(res.header('content-encoding'), 'gzip')

    const { rows } = await db.rawQuery('SELECT data FROM map_chunks WHERE x = ? AND y = ?', [
      C.x,
      C.y,
    ])
    assert.equal(JSON.parse(gunzipSync(rows[0].data).toString()).x, C.x)
  })

  test('nueva versión del generador re-rasteriza sin volver a pedir datos', async ({
    client,
    assert,
  }) => {
    const provider = roadProvider()
    const v1 = setup(provider)
    await client.get(url())
    await v1.worker.processNext()

    const v2 = setup(provider, { generatorVersion: VERSION() + 1 })
    await expectStatus(client.get(url()), 202)
    assert.isTrue(await v2.worker.processNext())
    assert.lengthOf(provider.calls, 1, 'reutiliza los datos OSM guardados')

    const res = await client.get(url())
    res.assertStatus(200)
    assert.equal((res.body() as unknown as ChunkPayload).generatorVersion, VERSION() + 1)
  })

  test('errores no reintentables marcan la zona como fallida (503)', async ({ client, assert }) => {
    const provider = new FakeOsmProvider(featureSet([]), new OsmProviderError('bad request', false))
    const { worker } = setup(provider)
    await client.get(url())
    await worker.processNext()

    const res = await client.get(url())
    res.assertStatus(503)
    assert.equal((res.body() as { status: string }).status, 'failed')
  })

  test('errores temporales se reintentan con backoff', async ({ client, assert }) => {
    const provider = new FakeOsmProvider(featureSet([]), new OsmProviderError('HTTP 504', true))
    const { worker } = setup(provider)
    await client.get(url())
    await worker.processNext()

    const { rows } = await db.rawQuery(
      'SELECT status, attempts, next_attempt_at > now() AS later FROM osm_source_tiles'
    )
    assert.deepEqual(rows[0], { status: 'queued', attempts: 1, later: true })
    assert.isFalse(await worker.processNext(), 'no se reintenta antes de tiempo')
    await expectStatus(client.get(url()), 202)
  })

  test('limita cuántas zonas nuevas puede pedir una IP', async ({ client, assert }) => {
    const base = app.config.get<MapConfig>('map')
    setup(roadProvider(), { limits: { ...base.limits, enqueuePerIp: 1 } })
    await expectStatus(client.get(url()), 202)
    const far = await client.get(url(C.z, C.x + 64, C.y))
    far.assertStatus(429)
    assert.exists(far.header('retry-after'))
  })
})
