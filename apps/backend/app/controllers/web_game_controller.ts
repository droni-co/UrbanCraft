import { createReadStream } from 'node:fs'
import { readFile, stat } from 'node:fs/promises'
import { extname, join, resolve, sep } from 'node:path'
import app from '@adonisjs/core/services/app'
import env from '#start/env'
import type { HttpContext } from '@adonisjs/core/http'

/** Tipos de los archivos que genera el export web de Godot. */
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
}

/**
 * Versión web del juego en /play (export web de Godot, ver docs/exportar.md).
 *
 * Los archivos están en WEB_GAME_DIR (por defecto public/play). Si existe
 * `archivo.gz` y el navegador acepta gzip, se manda ese (el .wasm baja de
 * ~35 MB a ~8 MB). Siempre se revalida con ETag: los nombres de los archivos
 * no cambian entre versiones, así que no se pueden cachear "para siempre".
 */
export default class WebGameController {
  #root = resolve(env.get('WEB_GAME_DIR') || app.makePath('public/play'))

  /** GET /play y /play/: index.html con <base href="/play/"> (las rutas relativas funcionan con o sin barra final). */
  async index({ response }: HttpContext) {
    return this.#sendIndex(response)
  }

  async #sendIndex(response: HttpContext['response']) {
    let html: string
    try {
      html = await readFile(join(this.#root, 'index.html'), 'utf8')
    } catch {
      return response
        .status(404)
        .header('Content-Type', 'text/plain; charset=utf-8')
        .send('La versión web del juego no está publicada en este servidor (pnpm game:export:web).')
    }
    response.header('Content-Type', TYPES['.html'])
    response.header('Cache-Control', 'no-cache')
    return response.send(html.replace(/<head>/i, '<head><base href="/play/">'))
  }

  /** GET /play/* */
  async file({ request, response, params }: HttpContext) {
    const segments: string[] = params['*'] ?? []
    if (segments.length === 0 || (segments.length === 1 && segments[0] === 'index.html')) {
      return this.#sendIndex(response)
    }
    const path = resolve(this.#root, ...segments)
    if (!path.startsWith(this.#root + sep)) return response.notFound()

    const acceptsGzip = /\bgzip\b/.test(request.header('accept-encoding') ?? '')
    let served = path
    let stats = acceptsGzip ? await stat(`${path}.gz`).catch(() => null) : null
    if (stats?.isFile()) {
      served = `${path}.gz`
      response.header('Content-Encoding', 'gzip')
    } else {
      stats = await stat(path).catch(() => null)
      if (!stats?.isFile()) return response.notFound()
    }

    const etag = `W/"${stats.size.toString(16)}-${stats.mtimeMs.toString(16)}"`
    response.header(
      'Content-Type',
      TYPES[extname(path).toLowerCase()] ?? 'application/octet-stream'
    )
    response.header('Vary', 'Accept-Encoding')
    response.header('Cache-Control', 'no-cache')
    response.header('ETag', etag)
    response.header('Last-Modified', stats.mtime.toUTCString())
    if (request.header('if-none-match') === etag) return response.status(304).send('')
    response.header('Content-Length', stats.size)
    return response.stream(createReadStream(served))
  }
}
