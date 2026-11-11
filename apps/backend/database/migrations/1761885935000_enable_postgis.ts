import { BaseSchema } from '@adonisjs/lucid/schema'

/**
 * Habilita PostGIS para consultas geoespaciales
 * (spawns de criaturas, puntos de interés, jugadores cercanos, etc.)
 */
export default class extends BaseSchema {
  async up() {
    this.schema.raw('CREATE EXTENSION IF NOT EXISTS postgis')
  }

  async down() {
    this.schema.raw('DROP EXTENSION IF EXISTS postgis')
  }
}
