import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Personaje (skin) elegido por el jugador: nombre del PNG en
 * apps/game/assets/art/characters sin extensión ("player03"). null = el por defecto.
 */
export default class extends BaseSchema {
  protected tableName = 'users'

  async up() {
    this.schema.alterTable(this.tableName, (table) => {
      table.string('skin', 32).nullable()
    })
  }

  async down() {
    this.schema.alterTable(this.tableName, (table) => {
      table.dropColumn('skin')
    })
  }
}
