/**
 * Números del juego: distancias, territorio, objetos del mapa y encargos.
 * Todo lo que se quiera equilibrar está aquí.
 */

export const RULES = {
  /** Celdas (≈ 2,4 m) a las que hay que estar de un lugar u objeto para usarlo. */
  nearCells: 7,
  /** Radio (en chunks) en el que se buscan lugares para encargos e historia. */
  searchChunks: 4,

  /** Con el hambre en cero el trabajo rinde la mitad. */
  hungryFactor: 0.5,

  discover: { xp: 12, influence: 6 },
  work: { xp: 8, hunger: 6, influence: 3, cooldownMinutes: 10, globalCooldownSeconds: 30 },
  buy: { influencePerMoney: 0.1, maxInfluence: 3 },
  gather: { xp: 1 },
  craft: { stationInfluence: 1 },

  jobs: {
    offered: 4,
    maxActive: 3,
    offerMinutes: 20,
    activeHours: 24,
    refreshCooldownSeconds: 60,
    influence: 8,
    /** Reparto: base + por celda de distancia. */
    delivery: { money: 22, moneyPerCell: 0.3, xp: 12, xpPerCell: 0.07, minCells: 30 },
    errand: { money: 25, markup: 1.5, xp: 18 },
    tour: { money: 28, xp: 32, stops: 3 },
  },

  territory: {
    /** Lado de un sector, en chunks (2 → unos 300 m). */
    sectorChunks: 2,
    ranks: [
      { name: 'Desconocido', points: 0, discount: 0 },
      { name: 'Visitante', points: 20, discount: 0 },
      { name: 'Vecino', points: 60, discount: 0.05 },
      { name: 'Conocido', points: 150, discount: 0.08 },
      { name: 'Referente', points: 400, discount: 0.12 },
      { name: 'Leyenda', points: 1000, discount: 0.15 },
    ],
    /** Para ser dueño: bandera plantada, al menos estos puntos y más que los demás con bandera. */
    ownPoints: 150,
    /** La influencia de un sector se reduce a la mitad cada tantos días sin actividad. */
    halfLifeDays: 30,
    /** Con bandera propia en el sector, la influencia que se gana se multiplica. */
    flagBonus: 1.25,
    /** Renta diaria por sector dominado (+ extra por cada objeto propio, con tope). */
    rent: { perSector: 30, perObject: 4, maxObjects: 8, maxDays: 3 },
  },

  objects: {
    /** Objetos por jugador: base + por nivel, con tope. */
    perPlayer: { base: 8, perLevel: 2, max: 40 },
    perChunk: 30,
    /** Días sin que el dueño lo toque hasta que desaparece. */
    expireDays: 21,
    influence: 4,
    /** Celdas mínimas a un lugar sensible (templos, salud, educación). */
    respectCells: 3,
    matera: { waterHours: 20, waterXp: 4, ownerInfluence: 2, flowerHours: 20 },
    caja: { stacks: 6, stack: 20, takesPerDay: 3 },
    puesto: {
      products: 6,
      stack: 30,
      /** Precio máximo: veces el precio base. */
      maxPriceFactor: 4,
      /** Clientes del barrio: cada tantos minutos puede venderse una unidad. */
      saleMinutes: 8,
      maxSalesPerVisit: 60,
    },
  },

  daily: { money: 20, xp: 15, streakBonus: 5, maxStreakBonus: 50 },
} as const

/** Frases para los letreros (texto libre no: habría que moderarlo). */
export const SIGN_PHRASES = [
  '¡Bienvenidos al parche!',
  'Aquí se vende fiado… mañana.',
  'Prohibido pasar sin saludar.',
  'Cuidado: vecino chismoso.',
  'Se arreglan problemas. Los suyos no.',
  'Este sector tiene dueño.',
  'Riegue la matera, no sea así.',
  'Hay empanadas. Pregunte.',
  'Zona de siesta. Silencio.',
  'El que madruga encuentra todo cerrado.',
  'Gracias por no botar basura.',
  'Don Gris: aquí no.',
  'Se busca socio con plata.',
  'Por aquí pasó alguien con hambre.',
  'Sonría: lo están mirando los vecinos.',
  'Todo lo bueno queda a dos cuadras.',
]

/** Nombres de sector (se combinan con un hash de sus coordenadas). */
export const SECTOR_NAMES = {
  first: [
    'La Esquina',
    'El Rincón',
    'La Cuadra',
    'El Callejón',
    'La Loma',
    'El Pasaje',
    'La Glorieta',
    'El Atajo',
    'La Bajada',
    'El Cruce',
    'La Vuelta',
    'El Portón',
  ],
  second: [
    'del Mango',
    'Sabrosa',
    'del Tinto',
    'Brava',
    'de los Gatos',
    'del Chisme',
    'Bonita',
    'de la Arepa',
    'del Buen Vecino',
    'Escondida',
    'de las Flores',
    'del Aguacero',
    'Dormilona',
    'de los Domingos',
    'del Afán',
    'Alegre',
  ],
}
