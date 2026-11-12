import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Amistades y solicitudes de amistad. Una sola fila por pareja de jugadores
 * (en cualquier sentido): `pending` mientras el destinatario no responde,
 * `accepted` cuando son amigos. Rechazar o eliminar borra la fila.
 */
export default class extends BaseSchema {
  protected tableName = 'friendships'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.increments('id')
      table
        .integer('requester_id')
        .unsigned()
        .notNullable()
        .references('users.id')
        .onDelete('CASCADE')
      table
        .integer('addressee_id')
        .unsigned()
        .notNullable()
        .references('users.id')
        .onDelete('CASCADE')
      table.string('status', 16).notNullable().defaultTo('pending')
      table.timestamp('created_at').notNullable()
      table.timestamp('updated_at').notNullable()
      table.index(['addressee_id', 'status'])
      table.index(['requester_id', 'status'])
    })
    // Una fila por pareja sin importar quién la envió.
    this.schema.raw(
      'CREATE UNIQUE INDEX friendships_pair_unique ON friendships ' +
        '(LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id))'
    )
    this.schema.raw(
      'ALTER TABLE friendships ADD CONSTRAINT friendships_not_self CHECK (requester_id <> addressee_id)'
    )
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
