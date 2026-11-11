import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Stats del jugador como clave-valor: agregar un stat nuevo (config/player_stats.ts)
 * no requiere migración. Sin fila = valor inicial del catálogo.
 */
export default class extends BaseSchema {
  protected tableName = 'player_stats'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.integer('user_id').unsigned().notNullable().references('users.id').onDelete('CASCADE')
      table.string('key', 32).notNullable()
      table.double('value').notNullable()
      table.timestamp('updated_at').notNullable()
      table.primary(['user_id', 'key'])
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
