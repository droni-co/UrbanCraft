import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Inicios de sesión OAuth en curso (duran minutos). El juego consulta su
 * estado con loginId + pollSecret (aquí solo se guarda el hash del secreto).
 * El token de acceso NO se guarda: se crea cuando el juego lo recoge.
 */
export default class extends BaseSchema {
  protected tableName = 'oauth_logins'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.uuid('id').primary()
      table.string('provider', 16).notNullable()
      table.string('poll_secret_hash', 64).notNullable()
      /** pending → redirected → complete | failed */
      table.string('status', 16).notNullable().defaultTo('pending')
      table.string('state', 64).nullable().unique()
      table.string('code_verifier', 128).nullable()
      table.string('error', 64).nullable()
      table.integer('user_id').unsigned().nullable().references('users.id').onDelete('CASCADE')
      table.boolean('is_new_user').notNullable().defaultTo(false)
      table.string('ip', 64).nullable()
      table.timestamp('expires_at').notNullable().index()
      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').nullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
