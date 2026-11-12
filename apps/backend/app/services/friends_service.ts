import db from '@adonisjs/lucid/services/db'

const TABLE = 'friendships'

export type FriendshipStatus = 'pending' | 'accepted'

/** Relación de un jugador con otro, vista desde el primero. */
export type Relation = 'self' | 'none' | 'friend' | 'incoming' | 'outgoing'

export interface PublicUser {
  id: number
  nickname: string
  skin: string | null
}

export interface FriendView extends PublicUser {
  /** Id de la amistad (fila de friendships). */
  friendshipId: number
  since: Date
}

export interface RequestView {
  /** Id de la solicitud (fila de friendships). */
  id: number
  user: PublicUser
  createdAt: Date
}

interface Row {
  id: number
  requester_id: number
  addressee_id: number
  status: FriendshipStatus
  created_at: Date
  updated_at: Date
}

interface JoinedRow extends Row {
  other_id: number
  other_nickname: string | null
  other_full_name: string | null
  other_skin: string | null
}

/** Errores esperables (el controlador los traduce a respuestas HTTP). */
export class FriendsError extends Error {
  constructor(
    readonly code:
      | 'user_not_found'
      | 'self'
      | 'already_friends'
      | 'already_requested'
      | 'request_not_found'
      | 'not_friends'
  ) {
    super(code)
  }
}

/**
 * Amigos y solicitudes de amistad. Una fila por pareja (ver la migración
 * create_friendships_table): rechazar o eliminar borra la fila, así se puede
 * volver a enviar una solicitud más adelante.
 */
export class FriendsService {
  /** Busca un jugador por su apodo exacto (sin distinguir mayúsculas). */
  async findByNickname(nickname: string): Promise<PublicUser | null> {
    const row = await db
      .from('users')
      .select('id', 'nickname', 'full_name', 'skin')
      .whereRaw('lower(nickname) = lower(?)', [nickname.trim()])
      .first()
    return row ? publicUser(row.id, row.nickname, row.full_name, row.skin) : null
  }

  async relation(userId: number, otherId: number): Promise<Relation> {
    if (userId === otherId) return 'self'
    const row = await this.#pair(userId, otherId)
    if (!row) return 'none'
    if (row.status === 'accepted') return 'friend'
    return row.requester_id === userId ? 'outgoing' : 'incoming'
  }

  /**
   * Envía una solicitud al jugador con ese apodo. Si él ya te había enviado
   * una, se acepta directamente (los dos querían ser amigos).
   */
  async sendRequest(
    userId: number,
    nickname: string
  ): Promise<{ status: 'sent' | 'accepted'; user: PublicUser; friendshipId: number }> {
    const target = await this.findByNickname(nickname)
    if (!target) throw new FriendsError('user_not_found')
    if (target.id === userId) throw new FriendsError('self')

    return db
      .transaction(async (trx) => {
        const existing = (await trx
          .from(TABLE)
          .where((q) => q.where({ requester_id: userId, addressee_id: target.id }))
          .orWhere((q) => q.where({ requester_id: target.id, addressee_id: userId }))
          .forUpdate()
          .first()) as Row | null
        const now = new Date()
        if (existing?.status === 'accepted') throw new FriendsError('already_friends')
        if (existing && existing.requester_id === userId)
          throw new FriendsError('already_requested')
        if (existing) {
          await trx
            .from(TABLE)
            .where('id', existing.id)
            .update({ status: 'accepted', updated_at: now })
          return { status: 'accepted' as const, user: target, friendshipId: existing.id }
        }
        const [inserted] = await trx
          .insertQuery()
          .table(TABLE)
          .insert({
            requester_id: userId,
            addressee_id: target.id,
            status: 'pending',
            created_at: now,
            updated_at: now,
          })
          .returning('id')
        return { status: 'sent' as const, user: target, friendshipId: idOf(inserted) }
      })
      .catch((error) => {
        // Dos solicitudes simultáneas entre la misma pareja: gana la primera.
        if (error?.code === '23505') throw new FriendsError('already_requested')
        throw error
      })
  }

  /** Acepta una solicitud recibida. Devuelve el id de quien la envió. */
  async accept(userId: number, requestId: number) {
    const row = await this.#incoming(userId, requestId)
    await db.from(TABLE).where('id', row.id).update({ status: 'accepted', updated_at: new Date() })
    return row.requester_id
  }

  /** Rechaza una solicitud recibida (o cancela una enviada). */
  async reject(userId: number, requestId: number) {
    const deleted = await db
      .from(TABLE)
      .where('id', requestId)
      .where('status', 'pending')
      .where((q) => q.where('addressee_id', userId).orWhere('requester_id', userId))
      .delete()
    if (!deleted) throw new FriendsError('request_not_found')
  }

  /** Deja de ser amigo de otro jugador. */
  async remove(userId: number, friendId: number) {
    const row = await this.#pair(userId, friendId)
    if (!row || row.status !== 'accepted') throw new FriendsError('not_friends')
    await db.from(TABLE).where('id', row.id).delete()
  }

  async areFriends(userId: number, otherId: number) {
    return (await this.relation(userId, otherId)) === 'friend'
  }

  /** Ids de los amigos (aceptados) de un jugador. */
  async friendIds(userId: number): Promise<number[]> {
    const rows = (await db
      .from(TABLE)
      .where('status', 'accepted')
      .where((q) => q.where('requester_id', userId).orWhere('addressee_id', userId))
      .select('requester_id', 'addressee_id')) as Pick<Row, 'requester_id' | 'addressee_id'>[]
    return rows.map((r) => (r.requester_id === userId ? r.addressee_id : r.requester_id))
  }

  /** Amigos y solicitudes (recibidas y enviadas) de un jugador. */
  async overview(userId: number) {
    const rows = (await db
      .from(`${TABLE} as f`)
      .joinRaw(
        'JOIN users AS u ON u.id = CASE WHEN f.requester_id = ? THEN f.addressee_id ELSE f.requester_id END',
        [userId]
      )
      .where((q) => q.where('f.requester_id', userId).orWhere('f.addressee_id', userId))
      .select(
        'f.*',
        'u.id as other_id',
        'u.nickname as other_nickname',
        'u.full_name as other_full_name',
        'u.skin as other_skin'
      )) as JoinedRow[]

    const friends: FriendView[] = []
    const incoming: RequestView[] = []
    const outgoing: RequestView[] = []
    for (const row of rows) {
      const user = publicUser(row.other_id, row.other_nickname, row.other_full_name, row.other_skin)
      if (row.status === 'accepted') {
        friends.push({ ...user, friendshipId: row.id, since: row.updated_at })
      } else {
        const view = { id: row.id, user, createdAt: row.created_at }
        if (row.addressee_id === userId) incoming.push(view)
        else outgoing.push(view)
      }
    }
    friends.sort((a, b) => a.nickname.localeCompare(b.nickname))
    incoming.sort((a, b) => +b.createdAt - +a.createdAt)
    outgoing.sort((a, b) => +b.createdAt - +a.createdAt)
    return { friends, incoming, outgoing }
  }

  async #pair(a: number, b: number) {
    return (await db
      .from(TABLE)
      .where((q) => q.where({ requester_id: a, addressee_id: b }))
      .orWhere((q) => q.where({ requester_id: b, addressee_id: a }))
      .first()) as Row | null
  }

  async #incoming(userId: number, requestId: number) {
    const row = (await db
      .from(TABLE)
      .where({ id: requestId, addressee_id: userId, status: 'pending' })
      .first()) as Row | null
    if (!row) throw new FriendsError('request_not_found')
    return row
  }
}

function publicUser(
  id: number,
  nickname: string | null,
  fullName: string | null,
  skin: string | null
): PublicUser {
  return { id, nickname: nickname ?? fullName ?? 'Jugador', skin: skin ?? null }
}

function idOf(inserted: unknown) {
  return Number(typeof inserted === 'object' && inserted !== null ? (inserted as any).id : inserted)
}
