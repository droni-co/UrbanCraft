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
  BUILDING: 8,
} as const

export const Prop = {
  TREE: 0,
  PINE: 1,
  ROCK: 2,
  BUSH: 3,
} as const

/** Valor de "sin prop" en el arreglo de props de un chunk. */
export const NO_PROP = 255

export type GroundId = (typeof Ground)[keyof typeof Ground]
export type PropId = (typeof Prop)[keyof typeof Prop]

export const GROUND_NAMES = Object.keys(Ground)
export const PROP_NAMES = Object.keys(Prop)

export const UNWALKABLE_GROUND: ReadonlySet<number> = new Set([Ground.WATER, Ground.BUILDING])
