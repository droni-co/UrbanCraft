/**
 * Recetas de fabricación. `station` es el objeto del mapa que hay que tener
 * cerca (propio o de otro jugador): null = se hace a mano en cualquier parte.
 */

export interface RecipeDefinition {
  key: string
  output: string
  qty: number
  inputs: Record<string, number>
  station: 'mesa' | 'parrilla' | null
  /** Nivel mínimo del jugador. */
  level: number
  /** Herramienta que hay que tener (no se gasta). */
  tool?: string
  xp: number
}

const recipe = (
  key: string,
  station: RecipeDefinition['station'],
  level: number,
  inputs: Record<string, number>,
  xp: number,
  extra: Partial<RecipeDefinition> = {}
): RecipeDefinition => ({ key, output: key, qty: 1, inputs, station, level, xp, ...extra })

export const RECIPES: RecipeDefinition[] = [
  // A mano
  recipe('matera', null, 1, { palo: 4, hoja: 2, semilla: 1 }, 15),
  recipe('cuerda', null, 1, { hoja: 3 }, 4),
  recipe('limonada', null, 1, { agua: 1, fruta: 1 }, 5),
  recipe('sanduche', null, 1, { pan: 1, queso: 1 }, 5),
  recipe('letrero', null, 2, { palo: 2, tabla: 1 }, 12),
  recipe('canasta', null, 2, { hoja: 6, cuerda: 2 }, 20),
  recipe('mesa', null, 3, { tabla: 4, clavos: 6, palo: 2 }, 35, { tool: 'martillo' }),
  recipe('parrilla', null, 3, { chatarra: 4, piedra: 2, carbon: 1 }, 30),

  // En una mesa de trabajo
  recipe('banca', 'mesa', 3, { tabla: 4, clavos: 6 }, 25, { tool: 'martillo' }),
  recipe('caja', 'mesa', 3, { tabla: 5, clavos: 4, chatarra: 1 }, 28, { tool: 'martillo' }),
  recipe('bandera', 'mesa', 4, { palo: 2, tela: 2, pintura: 1 }, 30),
  recipe('farol', 'mesa', 4, { chatarra: 3, botella: 1, carbon: 1 }, 25),
  recipe('puesto', 'mesa', 5, { tabla: 8, clavos: 10, tela: 3, pintura: 1 }, 80, {
    tool: 'martillo',
  }),
  recipe('morral', 'mesa', 6, { tela: 4, cuerda: 3 }, 60),

  // En una parrilla
  recipe('arepa', 'parrilla', 1, { masa: 1 }, 5),
  recipe('empanada', 'parrilla', 1, { masa: 1, carne: 1 }, 7, { qty: 2 }),
  recipe('chorizo', 'parrilla', 2, { carne: 1, carbon: 1 }, 9, { qty: 2 }),
  recipe('arepa_rellena', 'parrilla', 2, { arepa: 1, queso: 1 }, 9),
]

export const RECIPES_BY_KEY = new Map(RECIPES.map((r) => [r.key, r]))
