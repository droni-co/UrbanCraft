import { gunzipSync } from 'node:zlib'
import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'
import { GROUND_NAMES, NO_PROP, PROP_NAMES } from '#map/catalog'
import { MapChunkService } from '#services/map_chunk_service'

const INTEGER = /^\d{1,9}$/

@inject()
export default class MapController {
  constructor(private chunks: MapChunkService) {}

  /**
   * Parámetros del mapa que el cliente necesita para calcular chunks/celdas.
   * El catálogo permite al cliente verificar que sus ids de tiles coinciden.
   */
  config({ response }: HttpContext) {
    const c = this.chunks.config
    response.header('Cache-Control', 'public, max-age=300')
    return {
      chunkZoom: c.chunkZoom,
      cellZoom: c.cellZoom,
      chunkSize: 2 ** (c.cellZoom - c.chunkZoom),
      sourceZoom: c.sourceZoom,
      generatorVersion: c.generatorVersion,
      playRadiusMeters: c.playRadiusMeters,
      attribution: c.attribution,
      catalog: { ground: GROUND_NAMES, props: PROP_NAMES, noProp: NO_PROP },
    }
  }

  /**
   * GET /api/v1/map/chunks/:z/:x/:y[?v=generatorVersion]
   *
   * 200: chunk listo (JSON, enviado gzip si el cliente lo acepta). Con ?v= igual a
   *      la versión actual se marca immutable, ideal para un CDN.
   * 202: se está generando; reintentar tras Retry-After segundos. El cuerpo dice
   *      cómo va (stage, ahead, elapsed, expected, attempts: ver ChunkProgress).
   * 429: demasiadas zonas nuevas pedidas; reintentar más tarde.
   * 503: no se pudieron obtener datos de la zona.
   */
  async chunk({ params, request, response }: HttpContext) {
    if (![params.z, params.x, params.y].every((v) => INTEGER.test(String(v)))) {
      return response.unprocessableEntity({ error: 'Coordenadas de chunk inválidas' })
    }
    const [z, x, y] = [Number(params.z), Number(params.x), Number(params.y)]
    if (!this.chunks.isValidChunk(z, x, y)) {
      return response.unprocessableEntity({
        error: `Chunk inválido: z debe ser ${this.chunks.config.chunkZoom} y x/y estar en rango`,
      })
    }

    const result = await this.chunks.getChunk(z, x, y, request.ip())

    if (result.state !== 'ready') {
      response.header('Cache-Control', 'no-store')
      if (result.state === 'failed') {
        return response.serviceUnavailable({ status: 'failed', error: result.error })
      }
      response.header('Retry-After', String(result.retryAfterSeconds))
      if (result.state === 'throttled') {
        return response.tooManyRequests({
          status: result.state,
          retryAfter: result.retryAfterSeconds,
        })
      }
      return response.accepted({
        status: result.state,
        retryAfter: result.retryAfterSeconds,
        ...result.progress,
      })
    }

    const { data, etag } = result.chunk
    const immutable = request.input('v') === String(this.chunks.config.generatorVersion)
    response.header('ETag', etag)
    response.header('Vary', 'Accept-Encoding')
    response.header(
      'Cache-Control',
      immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=3600'
    )

    if (request.header('if-none-match') === etag) {
      return response.notModified()
    }

    response.header('Content-Type', 'application/json; charset=utf-8')
    if (/\bgzip\b/.test(request.header('accept-encoding') ?? '')) {
      response.header('Content-Encoding', 'gzip')
      return response.send(data)
    }
    return response.send(gunzipSync(data))
  }
}
