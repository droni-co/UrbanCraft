/**
 * Catálogo de stats del jugador. Para agregar uno nuevo basta con una entrada
 * aquí (no hace falta migración): se guarda en player_stats (user_id, key,
 * value) y el juego lo dibuja en el HUD a partir de este catálogo.
 *
 * Tipos (kind):
 * - meter:   barra entre min y max (hambre, energía, salud…).
 * - level:   experiencia acumulada → nivel con curva (ver levelCurve).
 * - counter: número entero sin máximo (dinero…).
 *
 * El servidor es la única fuente de verdad: el cliente solo los lee. Los
 * cambios llegan por acciones del juego (comer, misiones…) en el servidor.
 */

export type StatKind = 'meter' | 'level' | 'counter'

export interface StatDefinition {
  key: string
  label: string
  kind: StatKind
  /** Valor con el que empieza un jugador nuevo. */
  initial: number
  min: number
  /** null = sin máximo. */
  max: number | null
  /** Se guarda como entero (dinero, xp). */
  integer: boolean
  /**
   * Cuánto baja por minuto de juego activo (solo meter). Se aplica con el
   * latido del cliente; el tiempo desconectado no cuenta.
   */
  decayPerMinute?: number
  /** Mostrar en el HUD (debajo del menú) y en qué orden. */
  hud: boolean
  order: number
  /** Nombre del icono en apps/game/assets/art/ui/icons/<icon>.png */
  icon: string
  /** Color principal de la barra o el número (hex). */
  color: string
}

const playerStatsConfig = {
  stats: [
    {
      key: 'hunger',
      label: 'Hambre',
      kind: 'meter',
      initial: 100,
      min: 0,
      max: 100,
      integer: false,
      // 100 → 0 en ~3 h 20 min de juego activo.
      decayPerMinute: 0.5,
      hud: true,
      order: 10,
      icon: 'hunger',
      color: '#e8a33d',
    },
    {
      key: 'xp',
      label: 'Experiencia',
      kind: 'level',
      initial: 0,
      min: 0,
      max: null,
      integer: true,
      hud: true,
      order: 20,
      icon: 'xp',
      color: '#7cc4ff',
    },
    {
      key: 'money',
      label: 'Dinero',
      kind: 'counter',
      initial: 100,
      min: 0,
      max: null,
      integer: true,
      hud: true,
      order: 30,
      icon: 'money',
      color: '#ffd75e',
    },
  ] satisfies StatDefinition[] as StatDefinition[],

  /**
   * Curva de niveles: pasar del nivel N al N+1 cuesta base * N^exponent de xp.
   * Con base 100 y exponente 1.5: 100, 283, 520, 800… (cada vez un poco más).
   */
  levelCurve: { base: 100, exponent: 1.5, maxLevel: 100 },

  /** Latido del cliente: cada cuánto y cuánto tiempo como máximo cuenta un latido. */
  heartbeat: { intervalSeconds: 60, maxGapSeconds: 120 },
}

export type PlayerStatsConfig = typeof playerStatsConfig
export default playerStatsConfig
