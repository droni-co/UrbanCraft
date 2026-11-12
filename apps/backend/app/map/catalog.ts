/**
 * Catálogo de tiles compartido con el cliente.
 *
 * IMPORTANTE: los ids DEBEN coincidir con los enums de
 * apps/game/scripts/world/world_tiles.gd (WorldTiles.Ground / WorldTiles.Prop).
 * El cliente valida los nombres contra GET /api/v1/map/config al iniciar.
 * Agrega valores solo al final para no romper chunks ya generados.
 */

export const Ground = {
  GRASS: 0,
  GRASS_DARK: 1,
  DIRT: 2,
  SAND: 3,
  WATER: 4,
  STONE: 5,
  ASPHALT: 6,
  PAVEMENT: 7,
  /** Edificio genérico (tejas de barro). */
  BUILDING: 8,
  /** Edificios por tipo: así una manzana no es un bloque de un solo color. */
  ROOF_BRICK: 9,
  ROOF_CONCRETE: 10,
  ROOF_DARK: 11,
  ROOF_CIVIC: 12,
  ROOF_INDUSTRIAL: 13,
  /** Paso de cebra (solo sobre asfalto). */
  CROSSWALK: 14,
  RAIL: 15,
  CYCLEWAY: 16,
} as const

export const Prop = {
  TREE: 0,
  PINE: 1,
  ROCK: 2,
  BUSH: 3,
  // Mobiliario urbano (nodos OSM)
  BENCH: 4,
  STREET_LAMP: 5,
  TRAFFIC_LIGHT: 6,
  BUS_STOP: 7,
  FOUNTAIN: 8,
  STATUE: 9,
} as const

/** Valor de "sin prop" en el arreglo de props de un chunk. */
export const NO_PROP = 255

export type GroundId = (typeof Ground)[keyof typeof Ground]
export type PropId = (typeof Prop)[keyof typeof Prop]

export const GROUND_NAMES = Object.keys(Ground)
export const PROP_NAMES = Object.keys(Prop)

export const BUILDING_GROUNDS: ReadonlySet<number> = new Set([
  Ground.BUILDING,
  Ground.ROOF_BRICK,
  Ground.ROOF_CONCRETE,
  Ground.ROOF_DARK,
  Ground.ROOF_CIVIC,
  Ground.ROOF_INDUSTRIAL,
])

export const UNWALKABLE_GROUND: ReadonlySet<number> = new Set([Ground.WATER, ...BUILDING_GROUNDS])
