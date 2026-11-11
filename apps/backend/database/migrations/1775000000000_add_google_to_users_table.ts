import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Cuentas con Google: sin contraseña, con el id de Google ("sub") y un apodo
 * de jugador único (sin distinguir mayúsculas).
 */
export default class extends BaseSchema {
  protected tableName = 'users'

  async up() {
    this.schema.alterTable(this.tableName, (table) => {
      table.string('password').nullable().alter()
      table.string('google_id', 255).nullable().unique()
      table.string('avatar_url', 1024).nullable()
      table.string('nickname', 24).nullable()
    })
    this.schema.raw('CREATE UNIQUE INDEX users_nickname_lower_unique ON users (lower(nickname))')
  }

  async down() {
    this.schema.raw('DROP INDEX IF EXISTS users_nickname_lower_unique')
    // Las cuentas sin contraseña (solo Google) no caben en el esquema anterior.
    this.defer(async (db) => {
      await db.from(this.tableName).whereNull('password').delete()
    })
    this.schema.alterTable(this.tableName, (table) => {
      table.dropColumn('nickname')
      table.dropColumn('avatar_url')
      table.dropColumn('google_id')
      table.string('password').notNullable().alter()
    })
  }
}
