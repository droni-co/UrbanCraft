import type { HttpContext } from '@adonisjs/core/http'

const LOOPBACK = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1'])
const PROXY_HEADERS = [
  'x-forwarded-for',
  'x-real-ip',
  'forwarded',
  'cf-connecting-ip',
  'true-client-ip',
]

/**
 * true solo si la petición sale de esta misma máquina: la conexión TCP es
 * loopback y no pasó por un proxy o túnel (que también conectan por
 * 127.0.0.1 pero añaden cabeceras de reenvío).
 */
export function isLocalRequest(request: HttpContext['request']) {
  const socketIp = request.request.socket.remoteAddress ?? ''
  if (!LOOPBACK.has(socketIp)) return false
  const headers = request.headers()
  return PROXY_HEADERS.every((name) => headers[name] === undefined)
}
