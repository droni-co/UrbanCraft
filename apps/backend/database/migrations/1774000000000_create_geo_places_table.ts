import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Caché de geocodificación inversa (ciudad/país) por tile. Se comparte entre
 * todos los jugadores de la zona y evita repetir consultas a Nominatim.
 * `data` es null cuando el punto no pertenece a ninguna ciudad (mar abierto).
 */
export default class extends BaseSchema {
  protected tableName = 'geo_places'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.bigIncrements('id')
      table.smallint('z').notNullable()
      table.integer('x').notNullable()
      table.integer('y').notNullable()
      table.string('language', 8).notNullable()
      table.jsonb('data').nullable()
      table.string('provider', 32).notNullable()
      table.timestamp('fetched_at', { useTz: true }).notNullable()

      table.unique(['z', 'x', 'y', 'language'])
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
