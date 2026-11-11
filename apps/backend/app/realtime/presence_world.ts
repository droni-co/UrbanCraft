import { metersPerUnit, worldToLat } from '#map/geo'
import type { MoveState } from '#realtime/protocol'

export interface Presence {
  id: number
  nickname: string
  level: number
  /** Personaje elegido (null = el por defecto del juego). */
  skin: string | null
  x: number
  y: number
  dir: number
  move: MoveState
  /** false = modo fantasma: no aparece para los demás. */
  visible: boolean
  /** Ya envió su primera posición. */
  placed: boolean
  lastStateAt: number
  lastSpawnAt: number
}

/**
 * Jugadores conectados y su posición, con un índice espacial por cubetas
 * para responder "quién está cerca" sin recorrer a todos.
 * Lógica pura (sin red): ver GameRealtimeServer.
 */
export class PresenceWorld {
  #players = new Map<number, Presence>()
  #buckets = new Map<string, Set<number>>()
  #bucketOf = new Map<number, string>()

  constructor(
    private bucketCells: number,
    private cellZoom: number
  ) {}

  get size() {
    return this.#players.size
  }

  get(id: number) {
    return this.#players.get(id)
  }

  all() {
    return this.#players.values()
  }

  join(p: Omit<Presence, 'x' | 'y' | 'dir' | 'move' | 'placed' | 'lastStateAt' | 'lastSpawnAt'>) {
    this.leave(p.id)
    const presence: Presence = {
      ...p,
      x: 0,
      y: 0,
      dir: 2,
      move: 0,
      placed: false,
      lastStateAt: 0,
      lastSpawnAt: 0,
    }
    this.#players.set(p.id, presence)
    return presence
  }

  leave(id: number) {
    const key = this.#bucketOf.get(id)
    if (key) this.#buckets.get(key)?.delete(id)
    this.#bucketOf.delete(id)
    this.#players.delete(id)
  }

  /** Mueve a un jugador (actualiza el índice si cambió de cubeta). */
  move(id: number, x: number, y: number) {
    const p = this.#players.get(id)
    if (!p) return
    p.x = x
    p.y = y
    p.placed = true
    const key = this.#key(x, y)
    const previous = this.#bucketOf.get(id)
    if (previous === key) return
    if (previous) this.#buckets.get(previous)?.delete(id)
    let bucket = this.#buckets.get(key)
    if (!bucket) {
      bucket = new Set()
      this.#buckets.set(key, bucket)
    }
    bucket.add(id)
    this.#bucketOf.set(id, key)
  }

  /** Jugadores visibles a menos de `radius` celdas de (x, y), sin contar a `exceptId`. */
  within(x: number, y: number, radius: number, exceptId?: number): Presence[] {
    const out: Presence[] = []
    const r2 = radius * radius
    const b = this.bucketCells
    for (let by = Math.floor((y - radius) / b); by <= Math.floor((y + radius) / b); by++) {
      for (let bx = Math.floor((x - radius) / b); bx <= Math.floor((x + radius) / b); bx++) {
        for (const id of this.#buckets.get(`${bx},${by}`) ?? []) {
          if (id === exceptId) continue
          const p = this.#players.get(id)!
          if (!p.visible || !p.placed) continue
          const dx = p.x - x
          const dy = p.y - y
          if (dx * dx + dy * dy <= r2) out.push(p)
        }
      }
    }
    return out
  }

  /** Metros por celda en la latitud de la celda global y. */
  metersPerCell(y: number) {
    const lat = worldToLat(y, this.cellZoom)
    return metersPerUnit(lat, this.cellZoom)
  }

  #key(x: number, y: number) {
    return `${Math.floor(x / this.bucketCells)},${Math.floor(y / this.bucketCells)}`
  }
}

/** Redondea una coordenada a una grilla de `step` celdas (privacidad del radar). */
export function snap(v: number, step: number) {
  return step <= 1 ? Math.round(v) : Math.round(v / step) * step
}
