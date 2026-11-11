import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Datos OSM crudos (normalizados y comprimidos) por source tile, y cola de
 * trabajos de generación (status/attempts/next_attempt_at/locked_at).
 */
export default class extends BaseSchema {
  protected tableName = 'osm_source_tiles'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.bigIncrements('id')
      table.smallint('z').notNullable()
      table.integer('x').notNullable()
      table.integer('y').notNullable()
      table
        .string('status', 16)
        .notNullable()
        .defaultTo('queued')
        .checkIn(['queued', 'fetching', 'ready', 'failed'], 'osm_source_tiles_status_check')
      table.integer('attempts').notNullable().defaultTo(0)
      table.timestamp('next_attempt_at', { useTz: true }).notNullable().defaultTo(this.now())
      table.timestamp('locked_at', { useTz: true }).nullable()
      table.text('last_error').nullable()
      table.string('provider', 32).nullable()
      table.timestamp('osm_timestamp', { useTz: true }).nullable()
      table.integer('feature_count').nullable()
      table.binary('data').nullable()
      table.integer('rasterized_version').notNullable().defaultTo(0)
      table.timestamp('fetched_at', { useTz: true }).nullable()
      table.timestamp('created_at', { useTz: true }).notNullable()
      table.timestamp('updated_at', { useTz: true }).notNullable()

      table.unique(['z', 'x', 'y'])
      table.index(['status', 'next_attempt_at'])
    })
    this.schema.raw(
      `ALTER TABLE ${this.tableName} ADD COLUMN bounds geometry(Polygon, 4326) NOT NULL`
    )
    this.schema.raw(
      `CREATE INDEX ${this.tableName}_bounds_gist ON ${this.tableName} USING GIST (bounds)`
    )
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
