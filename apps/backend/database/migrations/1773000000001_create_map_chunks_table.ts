import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Chunks ya generados (inmutables por versión del generador). Todos los
 * jugadores que pisan la misma zona reciben exactamente este contenido.
 */
export default class extends BaseSchema {
  protected tableName = 'map_chunks'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.bigIncrements('id')
      table.smallint('z').notNullable()
      table.integer('x').notNullable()
      table.integer('y').notNullable()
      table.integer('generator_version').notNullable()
      table
        .bigInteger('source_tile_id')
        .nullable()
        .references('id')
        .inTable('osm_source_tiles')
        .onDelete('SET NULL')
      table.binary('data').notNullable()
      table.string('etag', 64).notNullable()
      table.integer('byte_size').notNullable()
      table.timestamp('created_at', { useTz: true }).notNullable()

      table.unique(['z', 'x', 'y', 'generator_version'])
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
