import { inject } from '@adonisjs/core'
import vine from '@vinejs/vine'
import app from '@adonisjs/core/services/app'
import type { HttpContext } from '@adonisjs/core/http'
import { FriendsError, FriendsService } from '#services/friends_service'
import { GameRealtimeServer } from '#realtime/game_server'

const nicknameValidator = vine.create({
  nickname: vine.string().trim().minLength(1).maxLength(20),
})

const ERRORS: Record<FriendsError['code'], { status: number; message: string }> = {
  user_not_found: { status: 404, message: 'No hay ningún jugador con ese apodo' },
  self: { status: 422, message: 'No puedes enviarte una solicitud a ti mismo' },
  already_friends: { status: 409, message: 'Ya son amigos' },
  already_requested: { status: 409, message: 'Ya le enviaste una solicitud' },
  request_not_found: { status: 404, message: 'La solicitud ya no existe' },
  not_friends: { status: 404, message: 'No son amigos' },
}

/**
 * Amigos (todo bajo /api/v1/friends, con sesión):
 *   GET    /                         → { friends, incoming, outgoing }
 *   GET    /search?nickname=X        → { user: { id, nickname, skin, relation } } · 404
 *   POST   /requests { nickname }    → { status: 'sent' | 'accepted', user }
 *   POST   /requests/:id/accept      → acepta una solicitud recibida
 *   DELETE /requests/:id             → rechaza una recibida o cancela una enviada
 *   DELETE /:userId                  → deja de ser amigos
 *   GET    /:userId/location         → { lat, lon } de un amigo conectado · 409 si no
 *
 * El destinatario conectado recibe un aviso por el WebSocket ({ t: 'friends' }).
 */
@inject()
export default class FriendsController {
  constructor(private friends: FriendsService) {}

  async index({ auth, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const realtime = await realtimeServer()
    const { friends, incoming, outgoing } = await this.friends.overview(auth.getUserOrFail().id)
    return {
      friends: friends.map((f) => ({ ...f, online: realtime.isOnline(f.id) })),
      incoming,
      outgoing,
    }
  }

  async search({ auth, request, response }: HttpContext) {
    const { nickname } = await nicknameValidator.validate(request.qs())
    const user = await this.friends.findByNickname(nickname)
    if (!user) return this.#error(response, new FriendsError('user_not_found'))
    const relation = await this.friends.relation(auth.getUserOrFail().id, user.id)
    return { user: { ...user, relation } }
  }

  async store({ auth, request, response }: HttpContext) {
    const me = auth.getUserOrFail()
    const { nickname } = await request.validateUsing(nicknameValidator)
    try {
      const result = await this.friends.sendRequest(me.id, nickname)
      const realtime = await realtimeServer()
      if (result.status === 'accepted') realtime.friendshipChanged(me.id, result.user.id, true)
      realtime.notifyFriends(
        result.user.id,
        result.status === 'sent' ? 'request' : 'accepted',
        displayName(me)
      )
      return response.status(result.status === 'sent' ? 201 : 200).send({
        status: result.status,
        user: result.user,
      })
    } catch (error) {
      return this.#error(response, error)
    }
  }

  async accept({ auth, params, response }: HttpContext) {
    const me = auth.getUserOrFail()
    try {
      const requesterId = await this.friends.accept(me.id, Number(params.id))
      const realtime = await realtimeServer()
      realtime.friendshipChanged(me.id, requesterId, true)
      realtime.notifyFriends(requesterId, 'accepted', displayName(me))
      return { status: 'accepted' }
    } catch (error) {
      return this.#error(response, error)
    }
  }

  async reject({ auth, params, response }: HttpContext) {
    try {
      await this.friends.reject(auth.getUserOrFail().id, Number(params.id))
      return response.noContent()
    } catch (error) {
      return this.#error(response, error)
    }
  }

  async destroy({ auth, params, response }: HttpContext) {
    try {
      const me = auth.getUserOrFail()
      const friendId = Number(params.userId)
      await this.friends.remove(me.id, friendId)
      const realtime = await realtimeServer()
      realtime.friendshipChanged(me.id, friendId, false)
      return response.noContent()
    } catch (error) {
      return this.#error(response, error)
    }
  }

  /**
   * Dónde está un amigo, para teletransportarse junto a él. Solo amigos
   * aceptados y solo si está conectado y visible (el modo fantasma lo oculta).
   */
  async location({ auth, params, response }: HttpContext) {
    response.header('Cache-Control', 'no-store')
    const friendId = Number(params.userId)
    if (!(await this.friends.areFriends(auth.getUserOrFail().id, friendId))) {
      return this.#error(response, new FriendsError('not_friends'))
    }
    const realtime = await realtimeServer()
    const position = realtime.locate(friendId)
    if (!position) {
      return response.conflict({
        error: 'friend_offline',
        message: 'Tu amigo no está conectado en este momento',
      })
    }
    return position
  }

  #error(response: HttpContext['response'], error: unknown) {
    if (!(error instanceof FriendsError)) throw error
    const { status, message } = ERRORS[error.code]
    return response.status(status).send({ error: error.code, message })
  }
}

function realtimeServer() {
  return app.container.make(GameRealtimeServer)
}

function displayName(user: { nickname: string | null; fullName: string | null }) {
  return user.nickname ?? user.fullName ?? 'Jugador'
}
