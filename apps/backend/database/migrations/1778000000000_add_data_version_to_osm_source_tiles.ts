import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Versión de los datos OSM guardados (qué etiquetas y elementos se pidieron).
 * Si config/map.ts dataVersion es mayor, el tile se vuelve a pedir al proveedor
 * en lugar de rasterizar con datos viejos a los que les faltan cosas.
 */
export default class extends BaseSchema {
  protected tableName = 'osm_source_tiles'

  async up() {
    this.schema.alterTable(this.tableName, (table) => {
      table.integer('data_version').notNullable().defaultTo(1)
    })
  }

  async down() {
    this.schema.alterTable(this.tableName, (table) => {
      table.dropColumn('data_version')
    })
  }
}
