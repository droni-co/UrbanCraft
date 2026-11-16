import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Mecánicas del juego: inventario, contadores (logros), estado del jugador
 * (historia, cosas del día), lugares visitados, encargos, influencia por
 * sector y objetos que los jugadores dejan en el mapa.
 *
 * Los catálogos (objetos, recetas, logros, historia) viven en app/game/catalog:
 * agregar contenido no necesita migraciones.
 */
export default class extends BaseSchema {
  async up() {
    const user = (table: any) =>
      table.integer('user_id').unsigned().notNullable().references('users.id').onDelete('CASCADE')

    this.schema.createTable('inventory_items', (table) => {
      user(table)
      table.string('item', 32).notNullable()
      table.integer('qty').notNullable()
      table.primary(['user_id', 'item'])
    })

    this.schema.createTable('player_counters', (table) => {
      user(table)
      table.string('key', 48).notNullable()
      table.double('value').notNullable()
      table.primary(['user_id', 'key'])
    })

    // Historia, racha diaria, enfriamientos: un JSON por jugador. La fila se
    // bloquea (FOR UPDATE) en cada acción, así las acciones de un jugador van en fila.
    this.schema.createTable('player_state', (table) => {
      user(table).primary()
      table.jsonb('data').notNullable()
      table.timestamp('updated_at').notNullable()
    })

    this.schema.createTable('player_achievements', (table) => {
      user(table)
      table.string('key', 48).notNullable()
      table.timestamp('unlocked_at').notNullable()
      table.primary(['user_id', 'key'])
    })

    this.schema.createTable('poi_visits', (table) => {
      user(table)
      table.string('poi_id', 32).notNullable()
      table.string('cat', 16).notNullable()
      table.timestamp('first_at').notNullable()
      table.timestamp('last_work_at').nullable()
      table.primary(['user_id', 'poi_id'])
    })

    this.schema.createTable('player_jobs', (table) => {
      table.bigIncrements('id')
      user(table)
      table.string('kind', 16).notNullable()
      /** offered | active */
      table.string('status', 12).notNullable()
      table.jsonb('data').notNullable()
      table.timestamp('expires_at').notNullable()
      table.timestamp('created_at').notNullable()
      table.index(['user_id', 'status'])
    })

    this.schema.createTable('sector_influence', (table) => {
      table.integer('sx').notNullable()
      table.integer('sy').notNullable()
      user(table)
      table.double('points').notNullable()
      table.timestamp('updated_at').notNullable()
      table.primary(['sx', 'sy', 'user_id'])
      table.index(['user_id'])
    })

    this.schema.createTable('world_objects', (table) => {
      table.bigIncrements('id')
      table.integer('owner_id').unsigned().notNullable().references('users.id').onDelete('CASCADE')
      table.string('kind', 24).notNullable()
      /** Celda global. */
      table.integer('x').notNullable()
      table.integer('y').notNullable()
      /** Chunk y sector de la celda (para buscar por zona). */
      table.integer('cx').notNullable()
      table.integer('cy').notNullable()
      table.integer('sx').notNullable()
      table.integer('sy').notNullable()
      table.jsonb('state').notNullable()
      table.timestamp('created_at').notNullable()
      /** Última vez que el dueño lo usó: los abandonados desaparecen. */
      table.timestamp('touched_at').notNullable()
      table.unique(['x', 'y'])
      table.index(['cx', 'cy'])
      table.index(['owner_id'])
      table.index(['sx', 'sy', 'kind'])
    })

    // Árboles, arbustos… que ya rebuscó cada jugador (tardan en recuperarse).
    this.schema.createTable('harvests', (table) => {
      user(table)
      table.integer('x').notNullable()
      table.integer('y').notNullable()
      table.timestamp('at').notNullable()
      table.primary(['user_id', 'x', 'y'])
    })
  }

  async down() {
    for (const name of [
      'harvests',
      'world_objects',
      'sector_influence',
      'player_jobs',
      'poi_visits',
      'player_achievements',
      'player_state',
      'player_counters',
      'inventory_items',
    ]) {
      this.schema.dropTable(name)
    }
  }
}
