import type User from '#models/user'
import { BaseTransformer } from '@adonisjs/core/transformers'

export default class UserTransformer extends BaseTransformer<User> {
  toObject() {
    return {
      ...this.#fields(),
      /** Métodos de acceso de la cuenta (sin exponer datos sensibles). */
      hasPassword: Boolean(this.resource.password),
      hasGoogle: Boolean(this.resource.googleId),
    }
  }

  #fields() {
    return this.pick(this.resource, [
      'id',
      'nickname',
      'fullName',
      'email',
      'avatarUrl',
      'skin',
      'createdAt',
      'updatedAt',
      'initials',
    ])
  }
}
