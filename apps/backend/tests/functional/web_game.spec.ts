import { test } from '@japa/runner'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { gzipSync } from 'node:zlib'
import env from '#start/env'

let dir: string
let previous: string | undefined

/**
 * La versión web del juego en /play. El controlador lee WEB_GAME_DIR al
 * crearse (una instancia por petición), así que basta con cambiar la variable.
 */
test.group('Versión web (/play)', (group) => {
  group.each.setup(async () => {
    previous = env.get('WEB_GAME_DIR')
    dir = await mkdtemp(join(tmpdir(), 'uc-play-'))
    await writeFile(join(dir, 'index.html'), '<html><head><title>UC</title></head></html>')
    await writeFile(join(dir, 'index.wasm'), Buffer.alloc(1000, 1))
    await writeFile(join(dir, 'index.wasm.gz'), gzipSync(Buffer.alloc(1000, 1)))
    await writeFile(join(dir, 'index.pck'), 'pck')
    await mkdir(join(dir, 'sub'))
    env.set('WEB_GAME_DIR', dir)
  })
  group.each.teardown(async () => {
    env.set('WEB_GAME_DIR', previous ?? '')
    await rm(dir, { recursive: true, force: true })
  })

  test('/play y /play/ sirven el index con <base href="/play/">', async ({ client, assert }) => {
    for (const url of ['/play', '/play/', '/play/index.html']) {
      const res = await client.get(url)
      res.assertStatus(200)
      res.assertHeader('content-type', 'text/html; charset=utf-8')
      assert.include(res.text(), '<head><base href="/play/"><title>')
    }
  })

  test('manda el .gz si el navegador acepta gzip, con el tipo del original', async ({
    client,
    assert,
  }) => {
    const res = await client.get('/play/index.wasm').header('accept-encoding', 'gzip, br')
    res.assertStatus(200)
    res.assertHeader('content-type', 'application/wasm')
    res.assertHeader('content-encoding', 'gzip')
    assert.equal(res.header('vary'), 'Accept-Encoding')

    const plain = await client.get('/play/index.pck').header('accept-encoding', 'identity')
    plain.assertStatus(200)
    assert.isUndefined(plain.header('content-encoding'))
    assert.equal(plain.header('content-length'), '3')
  })

  test('revalida con ETag (304)', async ({ client }) => {
    const first = await client.get('/play/index.pck')
    const res = await client
      .get('/play/index.pck')
      .header('if-none-match', first.header('etag') ?? '')
    res.assertStatus(304)
  })

  test('404 si no existe o intenta salir de la carpeta', async ({ client }) => {
    for (const url of ['/play/nope.js', '/play/sub', '/play/../.env', '/play/%2e%2e/.env']) {
      const res = await client.get(url)
      res.assertStatus(404)
    }
  })

  test('sin build publicado responde 404 con un mensaje', async ({ client }) => {
    env.set('WEB_GAME_DIR', join(dir, 'vacia'))
    const res = await client.get('/play')
    res.assertStatus(404)
  })
})
