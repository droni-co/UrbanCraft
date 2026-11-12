import type { IncomingMessage, Server as HttpServer } from 'node:http'
import type { Duplex } from 'node:stream'
import { Secret } from '@adonisjs/core/helpers'
import { WebSocketServer, WebSocket } from 'ws'
import User from '#models/user'
import type { RealtimeConfig } from '#config/realtime'
import { type PlayerStatsService } from '#services/player_stats_service'
import { type FriendsService } from '#services/friends_service'
import { PresenceWorld, snap, type Presence } from '#realtime/presence_world'
import { parseClientMessage, round2, type ClientMessage, type RtcKind } from '#realtime/protocol'
import { worldToLat, worldToLon } from '#map/geo'

interface Client {
  ws: WebSocket
  presence: Presence
  /** ids de los que ya se le mandó nickname/nivel. */
  known: Set<number>
  /** El último snap iba vacío (no se repiten snaps vacíos). */
  lastSnapEmpty: boolean
  lastSeen: number
  windowStart: number
  windowCount: number
  lastActAt: number
  /** Ids de sus amigos (para el chat); se actualiza con friendshipChanged(). */
  friends: Set<number>
  /** Mensajes de chat disponibles (se recuperan con el tiempo, ver chatRefillMs). */
  chatTokens: number
  chatRefilledAt: number
  /** En la voz con amigos. */
  voice: boolean
}

/** Códigos de cierre propios (4000–4999). */
export const CLOSE = {
  authTimeout: 4000,
  replaced: 4001,
  unauthorized: 4003,
  badMessage: 4004,
  rateLimit: 4008,
  idle: 4010,
} as const

const MIN_ACT_INTERVAL_MS = 250

/**
 * Servidor del multijugador: WebSocket en config.path sobre el mismo servidor
 * HTTP de Adonis (start/realtime.ts lo engancha).
 *
 * Cada jugador manda su posición; el servidor la valida (velocidad máxima) y
 * en cada tick le manda a cada uno los jugadores cercanos ("snap") y, una vez
 * por segundo, los de su radio de alcance con la posición redondeada ("radar").
 * Estado en memoria: con varias instancias haría falta Redis (ver docs/multijugador.md).
 */
export class GameRealtimeServer {
  readonly world: PresenceWorld
  #wss: WebSocketServer
  #clients = new Map<number, Client>()
  #attached = new WeakSet<HttpServer>()
  #timer?: NodeJS.Timeout
  #tick = 0
  private cellZoom: number
  /** Lado de un chunk del mapa, en celdas (64). */
  #chunkCells: number

  constructor(
    private config: RealtimeConfig,
    map: { cellZoom: number; chunkZoom: number },
    private stats: PlayerStatsService,
    private friends: FriendsService,
    private now: () => number = Date.now
  ) {
    this.cellZoom = map.cellZoom
    this.#chunkCells = 2 ** (map.cellZoom - map.chunkZoom)
    this.world = new PresenceWorld(config.bucketCells, map.cellZoom)
    this.#wss = new WebSocketServer({ noServer: true, maxPayload: config.maxMessageBytes })
    this.#wss.on('connection', (ws) => this.#onConnection(ws))
  }

  get connected() {
    return this.#clients.size
  }

  /** Engancha el upgrade de WebSocket al servidor HTTP (idempotente). */
  attach(server: HttpServer | undefined) {
    if (!server || this.#attached.has(server)) return
    this.#attached.add(server)
    server.on('upgrade', (req: IncomingMessage, socket: Duplex, head: Buffer) => {
      const path = (req.url ?? '').split('?')[0]
      if (path !== this.config.path) return
      this.#wss.handleUpgrade(req, socket, head, (ws) => this.#wss.emit('connection', ws, req))
    })
  }

  async close() {
    this.#stopTimer()
    for (const ws of this.#wss.clients) ws.close(1001, 'server_shutdown')
    this.#clients.clear()
    await new Promise<void>((resolve) => this.#wss.close(() => resolve()))
  }

  // --- Conexión ----------------------------------------------------------------

  #onConnection(ws: WebSocket) {
    let client: Client | null = null
    let authenticating = false
    const authTimer = setTimeout(() => {
      if (!client) ws.close(CLOSE.authTimeout, 'auth_timeout')
    }, this.config.authTimeoutMs)

    ws.on('message', async (data, isBinary) => {
      if (isBinary) return ws.close(CLOSE.badMessage, 'binary_not_supported')
      const msg = parseClientMessage(data.toString())
      if (!client) {
        if (authenticating) return
        if (msg?.t !== 'auth') return ws.close(CLOSE.unauthorized, 'auth_required')
        authenticating = true
        client = await this.#authenticate(ws, msg.token)
        clearTimeout(authTimer)
        return
      }
      if (!this.#allowMessage(client)) return
      if (!msg) return this.#send(client, { t: 'error', e: 'bad_message' })
      this.#handle(client, msg)
    })

    ws.on('close', () => {
      clearTimeout(authTimer)
      if (client && this.#clients.get(client.presence.id) === client) {
        this.#setVoice(client, false)
        this.#clients.delete(client.presence.id)
        this.world.leave(client.presence.id)
        if (this.#clients.size === 0) this.#stopTimer()
      }
    })
    ws.on('error', () => ws.terminate())
  }

  async #authenticate(ws: WebSocket, token: string): Promise<Client | null> {
    const accessToken = await User.accessTokens.verify(new Secret(token)).catch(() => null)
    const user = accessToken ? await User.find(accessToken.tokenableId) : null
    if (!user) {
      ws.close(CLOSE.unauthorized, 'invalid_token')
      return null
    }
    const friendIds = await this.friends.friendIds(user.id).catch(() => [])
    if (ws.readyState !== WebSocket.OPEN) return null

    // Una sola conexión por cuenta: la nueva reemplaza a la anterior.
    const previous = this.#clients.get(user.id)
    if (previous) {
      this.#clients.delete(user.id)
      this.#setVoice(previous, false)
      previous.ws.close(CLOSE.replaced, 'replaced')
    }

    const presence = this.world.join({
      id: user.id,
      nickname: user.nickname ?? user.fullName ?? 'Jugador',
      level: await this.#level(user.id),
      skin: user.skin ?? null,
      visible: true,
    })
    const now = this.now()
    const client: Client = {
      ws,
      presence,
      known: new Set(),
      lastSnapEmpty: true,
      lastSeen: now,
      windowStart: now,
      windowCount: 0,
      lastActAt: 0,
      friends: new Set(friendIds),
      chatTokens: this.config.chatBurst,
      chatRefilledAt: now,
      voice: false,
    }
    this.#clients.set(user.id, client)
    this.#send(client, {
      t: 'welcome',
      id: user.id,
      tickMs: this.config.tickMs,
      nearbyRadius: this.config.nearbyRadiusCells,
      radarRadiusMeters: this.config.radarRadiusMeters,
      ice: this.config.voiceIceServers,
    })
    this.#startTimer()
    return client
  }

  /**
   * Cambió el perfil (apodo, personaje): se actualiza la presencia y se vuelve
   * a mandar su info a quienes lo tienen cerca en el próximo snap.
   */
  updateProfile(userId: number, changes: { nickname?: string; skin?: string | null }) {
    const p = this.world.get(userId)
    if (!p) return
    if (changes.nickname !== undefined) p.nickname = changes.nickname
    if (changes.skin !== undefined) p.skin = changes.skin
    for (const client of this.#clients.values()) client.known.delete(userId)
  }

  /** Conectado y visible (en modo fantasma aparece como desconectado). */
  isOnline(userId: number) {
    const p = this.#clients.has(userId) ? this.world.get(userId) : undefined
    return Boolean(p && p.visible)
  }

  /**
   * Posición actual de un jugador en lat/lon, para teletransportarse junto a él.
   * null si no está conectado, está en modo fantasma o aún no apareció en el mapa.
   */
  locate(userId: number): { lat: number; lon: number } | null {
    const p = this.#clients.has(userId) ? this.world.get(userId) : undefined
    if (!p || !p.visible || !p.placed) return null
    return { lat: worldToLat(p.y, this.cellZoom), lon: worldToLon(p.x, this.cellZoom) }
  }

  /** Avisa a un jugador conectado de un cambio en sus amigos o solicitudes. */
  notifyFriends(userId: number, event: 'request' | 'accepted', from: string) {
    const client = this.#clients.get(userId)
    if (client) this.#send(client, { t: 'friends', e: event, n: from })
  }

  /** Se hicieron (o dejaron de ser) amigos: el chat los conecta (o deja de hacerlo). */
  friendshipChanged(a: number, b: number, areFriends: boolean) {
    for (const [me, other] of [
      [a, b],
      [b, a],
    ]) {
      const friends = this.#clients.get(me)?.friends
      if (areFriends) friends?.add(other)
      else friends?.delete(other)
    }
    // Si los dos están en la voz, se conectan (o se cortan) al momento.
    const ca = this.#clients.get(a)
    const cb = this.#clients.get(b)
    if (ca?.voice && cb?.voice) {
      this.#send(ca, this.#voiceMessage(cb, areFriends))
      this.#send(cb, this.#voiceMessage(ca, areFriends))
    }
  }

  async #level(userId: number) {
    try {
      const stats = await this.stats.snapshot(userId)
      return stats.find((s) => s.kind === 'level')?.level?.level ?? 1
    } catch {
      return 1
    }
  }

  /** Límite de mensajes por segundo: el exceso se descarta; muy por encima, se cierra. */
  #allowMessage(client: Client) {
    const now = this.now()
    client.lastSeen = now
    if (now - client.windowStart >= 1000) {
      client.windowStart = now
      client.windowCount = 0
    }
    client.windowCount++
    if (client.windowCount > this.config.maxMessagesPerSecond * 3) {
      client.ws.close(CLOSE.rateLimit, 'rate_limit')
      return false
    }
    return client.windowCount <= this.config.maxMessagesPerSecond
  }

  // --- Mensajes ----------------------------------------------------------------

  #handle(client: Client, msg: ClientMessage) {
    switch (msg.t) {
      case 'state':
        return this.#onState(client, msg)
      case 'act':
        return this.#onAct(client, msg.k)
      case 'vis':
        client.presence.visible = msg.v
        if (!msg.v) this.#setVoice(client, false) // el modo fantasma corta la voz
        return
      case 'voice':
        return this.#setVoice(client, msg.on)
      case 'rtc':
        return this.#onRtc(client, msg.to, msg.k, msg.d)
      case 'ping':
        return this.#send(client, { t: 'pong', c: msg.c })
      case 'say':
        return this.#onSay(client, msg.m)
      case 'auth':
        return // ya autenticado
    }
  }

  #onState(client: Client, msg: Extract<ClientMessage, { t: 'state' }>) {
    const p = client.presence
    const now = this.now()
    const jump = !p.placed || msg.spawn
    if (jump) {
      // Aparecer / teletransportarse: salto libre, pero no más de uno cada tanto.
      const wait = p.lastSpawnAt + this.config.minSpawnIntervalMs - now
      if (p.placed && wait > 0) {
        return this.#send(client, { t: 'reject', r: 'spawn', retry: wait })
      }
      p.lastSpawnAt = now
    } else {
      // Anti-trampas: distancia máxima según el tiempo desde el último estado aceptado.
      const dt = Math.max(now - p.lastStateAt, this.config.tickMs) / 1000
      const allowed = this.config.maxSpeedCellsPerSecond * dt + 1
      if (Math.hypot(msg.x - p.x, msg.y - p.y) > allowed) {
        return this.#send(client, {
          t: 'reject',
          r: 'speed',
          retry: this.config.minSpawnIntervalMs,
        })
      }
    }
    p.lastStateAt = now
    p.dir = msg.d
    p.move = msg.m
    this.world.move(p.id, msg.x, msg.y)
  }

  #onAct(client: Client, kind: string) {
    const p = client.presence
    const now = this.now()
    if (!p.placed || !p.visible || now - client.lastActAt < MIN_ACT_INTERVAL_MS) return
    client.lastActAt = now
    for (const other of this.world.within(p.x, p.y, this.config.nearbyRadiusCells, p.id)) {
      const target = this.#clients.get(other.id)
      if (target) this.#send(target, { t: 'act', id: p.id, k: kind })
    }
  }

  /**
   * Chat: llega a quien habla (confirmación), a sus amigos conectados y a los
   * jugadores de su zona (su chunk y los vecinos, ver chatChunkRadius). En modo
   * fantasma o antes de aparecer en el mapa, solo a sus amigos.
   */
  #onSay(client: Client, text: string) {
    const now = this.now()
    const refill = Math.floor((now - client.chatRefilledAt) / this.config.chatRefillMs)
    if (refill > 0) {
      client.chatTokens = Math.min(this.config.chatBurst, client.chatTokens + refill)
      client.chatRefilledAt =
        client.chatTokens === this.config.chatBurst
          ? now
          : client.chatRefilledAt + refill * this.config.chatRefillMs
    }
    if (client.chatTokens <= 0) {
      const retry = client.chatRefilledAt + this.config.chatRefillMs - now
      return this.#send(client, { t: 'reject', r: 'chat', retry })
    }
    client.chatTokens--

    const me = client.presence
    const recipients = new Set<number>([me.id])
    for (const id of client.friends) if (this.#clients.has(id)) recipients.add(id)
    if (me.visible && me.placed) {
      for (const p of this.#chatZone(me)) recipients.add(p.id)
    }
    for (const id of recipients) {
      const target = this.#clients.get(id)
      if (!target) continue
      this.#send(target, {
        t: 'chat',
        id: me.id,
        n: me.nickname,
        m: text,
        f: client.friends.has(id) ? 1 : 0,
      })
    }
  }

  // --- Voz con amigos ----------------------------------------------------------

  /**
   * Entra o sale de la voz. Se avisa a los amigos conectados que están en la
   * voz y, al entrar, se le dice quiénes ya estaban: cada pareja se conecta
   * directo por WebRTC (inicia la oferta el de id menor). En modo fantasma no
   * se puede entrar.
   */
  #setVoice(client: Client, on: boolean) {
    if (on && !client.presence.visible) {
      return this.#send(client, { t: 'voice', id: client.presence.id, n: '', on: false })
    }
    if (client.voice === on) return
    client.voice = on
    for (const friend of this.#voiceFriends(client)) {
      this.#send(friend, this.#voiceMessage(client, on))
      if (on) this.#send(client, this.#voiceMessage(friend, true))
    }
  }

  #voiceFriends(client: Client) {
    const out: Client[] = []
    for (const id of client.friends) {
      const friend = this.#clients.get(id)
      if (friend?.voice) out.push(friend)
    }
    return out
  }

  #voiceMessage(of: Client, on: boolean) {
    return { t: 'voice', id: of.presence.id, n: of.presence.nickname, on }
  }

  /** Señalización WebRTC: solo entre amigos que están los dos en la voz. */
  #onRtc(client: Client, to: number, kind: RtcKind, data: string) {
    const target = this.#clients.get(to)
    if (!client.voice || !target?.voice || !client.friends.has(to)) return
    this.#send(target, { t: 'rtc', from: client.presence.id, k: kind, d: data })
  }

  /** Jugadores visibles cuyo chunk está a ≤ chatChunkRadius chunks del de `me`. */
  #chatZone(me: Presence): Presence[] {
    const size = this.#chunkCells
    const r = this.config.chatChunkRadius
    const cx = Math.floor(me.x / size)
    const cy = Math.floor(me.y / size)
    // Círculo que cubre el cuadrado de chunks (centro del chunk propio ± (r + ½) chunks).
    const half = (r + 0.5) * size
    const candidates = this.world.within((cx + 0.5) * size, (cy + 0.5) * size, half * Math.SQRT2)
    return candidates.filter(
      (p) =>
        p.id !== me.id &&
        Math.abs(Math.floor(p.x / size) - cx) <= r &&
        Math.abs(Math.floor(p.y / size) - cy) <= r
    )
  }

  // --- Tick --------------------------------------------------------------------

  #startTimer() {
    if (this.#timer) return
    this.#timer = setInterval(() => this.tick(), this.config.tickMs)
    this.#timer.unref()
  }

  #stopTimer() {
    if (this.#timer) clearInterval(this.#timer)
    this.#timer = undefined
  }

  /** Un tick: snapshots de cercanos, y cada radarEveryTicks el radar. Público para pruebas. */
  tick() {
    this.#tick++
    const withRadar = this.#tick % this.config.radarEveryTicks === 0
    const now = this.now()
    for (const client of this.#clients.values()) {
      if (now - client.lastSeen > this.config.idleTimeoutMs) {
        client.ws.close(CLOSE.idle, 'idle')
        continue
      }
      const me = client.presence
      if (!me.placed) continue
      const nearby = this.world.within(me.x, me.y, this.config.nearbyRadiusCells, me.id)
      this.#sendSnap(client, nearby)
      if (withRadar) this.#sendRadar(client, nearby)
    }
  }

  #sendSnap(client: Client, nearby: Presence[]) {
    if (nearby.length === 0 && client.lastSnapEmpty) return
    client.lastSnapEmpty = nearby.length === 0
    const info: Record<number, { n: string; lv: number; s: string | null }> = {}
    let hasInfo = false
    for (const p of nearby) {
      if (client.known.has(p.id)) continue
      client.known.add(p.id)
      info[p.id] = { n: p.nickname, lv: p.level, s: p.skin }
      hasInfo = true
    }
    this.#send(client, {
      t: 'snap',
      p: nearby.map((p) => [p.id, round2(p.x), round2(p.y), p.dir, p.move]),
      ...(hasInfo ? { info } : {}),
    })
  }

  /**
   * Radar: los demás jugadores dentro de radarRadiusMeters, sin id y con la
   * posición redondeada a radarPrecisionMeters (no sirve para seguir a alguien
   * con precisión). Los cercanos ya van en el snap y no se repiten.
   */
  #sendRadar(client: Client, nearby: Presence[]) {
    const me = client.presence
    const metersPerCell = this.world.metersPerCell(me.y)
    const radius = this.config.radarRadiusMeters / metersPerCell
    const step = this.config.radarPrecisionMeters / metersPerCell
    const skip = new Set(nearby.map((p) => p.id))
    const points: [number, number][] = []
    for (const p of this.world.within(me.x, me.y, radius, me.id)) {
      if (!skip.has(p.id)) points.push([snap(p.x, step), snap(p.y, step)])
    }
    this.#send(client, { t: 'radar', p: points })
  }

  #send(client: Client, payload: object) {
    if (client.ws.readyState === WebSocket.OPEN) client.ws.send(JSON.stringify(payload))
  }
}
