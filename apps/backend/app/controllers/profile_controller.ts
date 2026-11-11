import UserTransformer from '#transformers/user_transformer'
import type { HttpContext } from '@adonisjs/core/http'
import { updateProfileValidator } from '#validators/user'
import { isNicknameTaken } from '#services/oauth_login_service'
import { GameRealtimeServer } from '#realtime/game_server'
import app from '@adonisjs/core/services/app'

export default class ProfileController {
  async show({ auth, serialize }: HttpContext) {
    return serialize(UserTransformer.transform(auth.getUserOrFail()))
  }

  /**
   * PATCH /api/v1/account/profile { nickname?, skin? } · 409 si el apodo está en uso.
   * Los jugadores cercanos ven el cambio al momento (multijugador).
   */
  async update({ auth, request, response, serialize }: HttpContext) {
    const user = auth.getUserOrFail()
    const { nickname, skin } = await request.validateUsing(updateProfileValidator)
    if (nickname !== undefined) {
      if (await isNicknameTaken(nickname, user.id)) {
        return response.conflict({ error: 'nickname_taken', message: 'Ese apodo ya está en uso' })
      }
      user.nickname = nickname
    }
    if (skin !== undefined) user.skin = skin
    await user.save()

    const realtime = await app.container.make(GameRealtimeServer)
    realtime.updateProfile(user.id, { nickname: user.nickname ?? undefined, skin: user.skin })
    return serialize(UserTransformer.transform(user))
  }
}
