/**
 * Logros. Cada familia mira un contador del jugador (player_counters) y tiene
 * varios niveles: bronce, plata, oro y diamante. Para agregar un logro basta
 * con una familia nueva aquí (y, si hace falta, sumar su contador donde ocurra
 * la acción: GameStore.count).
 *
 * `emblem` es el dibujo de la medalla: apps/game/assets/art/medals/<emblem>.png.
 */

export interface AchievementFamily {
  key: string
  emblem: string
  counter: string
  /** Qué hay que hacer; «{n}» es la cantidad del nivel. */
  desc: string
  /** [cantidad, nombre] de cada nivel, de menor a mayor. */
  tiers: [number, string][]
}

export interface AchievementDefinition {
  key: string
  family: string
  emblem: string
  counter: string
  name: string
  desc: string
  /** 1 bronce · 2 plata · 3 oro · 4 diamante. */
  tier: number
  count: number
  reward: { xp: number; money: number }
}

const FAMILIES: AchievementFamily[] = [
  {
    key: 'caminar',
    emblem: 'zapato',
    counter: 'distance_m',
    desc: 'Camina {n} metros',
    tiers: [
      [1000, 'Estirando las piernas'],
      [10000, 'Pata de perro'],
      [42000, 'Maratonista de barrio'],
      [150000, 'Suelas gastadas'],
    ],
  },
  {
    key: 'lugares',
    emblem: 'lupa',
    counter: 'pois_discovered',
    desc: 'Visita {n} lugares distintos',
    tiers: [
      [5, 'Chismoso'],
      [25, 'Metido'],
      [75, 'Conoce a todo el mundo'],
      [200, 'Guía oficial'],
    ],
  },
  {
    key: 'comederos',
    emblem: 'cubiertos',
    counter: 'disc_food',
    desc: 'Visita {n} lugares de comida',
    tiers: [
      [3, 'Antojado'],
      [15, 'Buen diente'],
      [40, 'Crítico gastronómico'],
    ],
  },
  {
    key: 'tiendas',
    emblem: 'bolsa',
    counter: 'disc_shop',
    desc: 'Visita {n} tiendas',
    tiers: [
      [3, 'Solo estoy mirando'],
      [15, 'Vitrinero'],
      [40, 'Cliente frecuente'],
    ],
  },
  {
    key: 'cultura',
    emblem: 'mascaras',
    counter: 'disc_culture',
    desc: 'Visita {n} lugares de cultura',
    tiers: [
      [3, 'Culto de a ratos'],
      [12, 'Con mundo'],
      [30, 'Patrimonio viviente'],
    ],
  },
  {
    key: 'transporte',
    emblem: 'bus',
    counter: 'disc_transport',
    desc: 'Visita {n} lugares de transporte',
    tiers: [
      [1, 'Con pasaje'],
      [5, 'Se sabe las rutas'],
      [15, 'Ayudante de bus'],
    ],
  },
  {
    key: 'sectores',
    emblem: 'mapa',
    counter: 'sectors_visited',
    desc: 'Deja huella en {n} sectores',
    tiers: [
      [3, 'Sale de la cuadra'],
      [10, 'Andariego'],
      [25, 'Media ciudad'],
      [60, 'Ciudadano del mundo'],
    ],
  },
  {
    key: 'domicilios',
    emblem: 'domicilio',
    counter: 'jobs_delivery',
    desc: 'Entrega {n} domicilios',
    tiers: [
      [1, 'Primer domicilio'],
      [10, 'Llega caliente'],
      [50, 'Rey del pedal'],
      [150, 'Ni el aguacero lo para'],
    ],
  },
  {
    key: 'mandados',
    emblem: 'maletin',
    counter: 'jobs_errand',
    desc: 'Haz {n} mandados',
    tiers: [
      [1, 'Hágame un favor'],
      [10, 'Mandadero de confianza'],
      [50, 'Lo que pidan'],
    ],
  },
  {
    key: 'encargos',
    emblem: 'trofeo',
    counter: 'jobs_completed',
    desc: 'Completa {n} encargos',
    tiers: [
      [5, 'Cumplido'],
      [30, 'Recomendado'],
      [100, 'Indispensable'],
      [300, 'El que resuelve'],
    ],
  },
  {
    key: 'turnos',
    emblem: 'maletin',
    counter: 'work_shifts',
    desc: 'Trabaja {n} turnos',
    tiers: [
      [1, 'Primer día'],
      [20, 'Empleado del mes'],
      [100, 'Todero'],
    ],
  },
  {
    key: 'plata',
    emblem: 'monedas',
    counter: 'money_earned',
    desc: 'Gana ${n} en total',
    tiers: [
      [500, 'Plata de bolsillo'],
      [5000, 'Ya alcanza para el arriendo'],
      [25000, 'Con solvencia'],
      [100000, 'Magnate de barrio'],
    ],
  },
  {
    key: 'ahorro',
    emblem: 'alcancia',
    counter: 'money_max',
    desc: 'Ten ${n} al mismo tiempo',
    tiers: [
      [1000, 'Marranito lleno'],
      [5000, 'Ahorrador'],
      [20000, 'Debajo del colchón'],
    ],
  },
  {
    key: 'compras',
    emblem: 'bolsa',
    counter: 'purchases',
    desc: 'Haz {n} compras',
    tiers: [
      [10, 'Mercado chiquito'],
      [100, 'Mueve la economía'],
      [500, 'Le fían'],
    ],
  },
  {
    key: 'fabricar',
    emblem: 'herramientas',
    counter: 'items_crafted',
    desc: 'Fabrica {n} cosas',
    tiers: [
      [1, 'Hecho a mano'],
      [25, 'Maña le sobra'],
      [100, 'Maestro'],
      [300, 'Fábrica con piernas'],
    ],
  },
  {
    key: 'cocinar',
    emblem: 'chef',
    counter: 'food_cooked',
    desc: 'Asa {n} comidas en una parrilla',
    tiers: [
      [1, 'No se quemó'],
      [15, 'Sazón propia'],
      [60, 'Parrillero mayor'],
    ],
  },
  {
    key: 'rebuscar',
    emblem: 'arbol',
    counter: 'items_gathered',
    desc: 'Rebusca {n} materiales',
    tiers: [
      [10, 'Recursivo'],
      [100, 'Rebuscador'],
      [500, 'Nada se le escapa'],
      [2000, 'Reciclador legendario'],
    ],
  },
  {
    key: 'comer',
    emblem: 'corazon',
    counter: 'food_eaten',
    desc: 'Come {n} veces',
    tiers: [
      [1, 'Barriga llena'],
      [25, 'Buen comer'],
      [100, 'Corazón contento'],
    ],
  },
  {
    key: 'construir',
    emblem: 'casa',
    counter: 'objects_placed',
    desc: 'Coloca {n} objetos en el mapa',
    tiers: [
      [1, 'Puso su granito'],
      [10, 'Decorador de andenes'],
      [40, 'Urbanista aficionado'],
    ],
  },
  {
    key: 'regar',
    emblem: 'matera',
    counter: 'waterings',
    desc: 'Riega materas {n} veces',
    tiers: [
      [1, 'Mano verde'],
      [20, 'Jardinero del andén'],
      [100, 'Protegido de la abuela Tulia'],
    ],
  },
  {
    key: 'ventas',
    emblem: 'puesto',
    counter: 'stall_sales',
    desc: 'Vende {n} unidades en tus puestos',
    tiers: [
      [1, 'Primera venta'],
      [25, 'Negociante'],
      [200, 'Comerciante de respeto'],
      [1000, 'Franquicia'],
    ],
  },
  {
    key: 'trueque',
    emblem: 'regalo',
    counter: 'trueque_dejados',
    desc: 'Deja {n} objetos en cajas de trueque',
    tiers: [
      [1, 'Generoso'],
      [10, 'Buen vecino'],
      [50, 'Mano abierta'],
    ],
  },
  {
    key: 'estudiar',
    emblem: 'birrete',
    counter: 'studies',
    desc: 'Estudia {n} veces',
    tiers: [
      [1, 'Con cuaderno nuevo'],
      [10, 'Aplicado'],
      [40, 'Come libros'],
    ],
  },
  {
    key: 'entrenar',
    emblem: 'balon',
    counter: 'trainings',
    desc: 'Entrena {n} veces',
    tiers: [
      [1, 'Calentando'],
      [10, 'En forma'],
      [40, 'Crack del barrio'],
    ],
  },
  {
    key: 'nivel',
    emblem: 'estrella',
    counter: 'level',
    desc: 'Llega al nivel {n}',
    tiers: [
      [3, 'Va cogiendo vuelo'],
      [6, 'Con experiencia'],
      [12, 'Veterano'],
      [20, 'Maestro de la calle'],
    ],
  },
  {
    key: 'dominio',
    emblem: 'bandera',
    counter: 'sectors_owned',
    desc: 'Domina {n} sectores a la vez',
    tiers: [
      [1, 'Con bandera propia'],
      [3, 'Cacique de tres cuadras'],
      [6, 'Media comuna'],
      [10, 'Alcalde sin elecciones'],
    ],
  },
  {
    key: 'respeto',
    emblem: 'corona',
    counter: 'rank4_sectors',
    desc: 'Sé Referente en {n} sectores',
    tiers: [
      [1, 'Lo saludan por el nombre'],
      [3, 'Don o Doña'],
      [6, 'Institución'],
    ],
  },
  {
    key: 'leyenda',
    emblem: 'corona',
    counter: 'rank5_sectors',
    desc: 'Sé Leyenda en {n} sectores',
    tiers: [
      [1, 'Leyenda viva'],
      [3, 'Mito urbano'],
    ],
  },
  {
    key: 'historia',
    emblem: 'libro',
    counter: 'chapters',
    desc: 'Completa {n} capítulos de la historia',
    tiers: [
      [1, 'Ya no es turista'],
      [3, 'Con historia'],
      [6, 'Protagonista'],
      [9, 'Dueño del barrio'],
    ],
  },
  {
    key: 'amigos',
    emblem: 'manos',
    counter: 'friends',
    desc: 'Ten {n} amigos',
    tiers: [
      [1, 'No está solo'],
      [3, 'El parche'],
      [10, 'Popular'],
    ],
  },
  {
    key: 'chat',
    emblem: 'chat',
    counter: 'chat_messages',
    desc: 'Envía {n} mensajes de chat',
    tiers: [
      [1, 'Rompió el hielo'],
      [50, 'Conversador'],
      [500, 'Lengua suelta'],
    ],
  },
  {
    key: 'saludar',
    emblem: 'saludo',
    counter: 'waves',
    desc: 'Saluda {n} veces',
    tiers: [
      [1, 'Bien educado'],
      [25, 'Saluda hasta a los postes'],
      [100, 'Candidato en campaña'],
    ],
  },
  {
    key: 'noche',
    emblem: 'luna',
    counter: 'night_actions',
    desc: 'Completa {n} encargos o turnos de noche',
    tiers: [
      [1, 'Trasnochador'],
      [10, 'Búho'],
      [50, 'Dueño de la noche'],
    ],
  },
  {
    key: 'madrugar',
    emblem: 'amanecer',
    counter: 'early_actions',
    desc: 'Completa {n} encargos o turnos al amanecer',
    tiers: [
      [1, 'Madrugador'],
      [10, 'Al que madruga…'],
      [30, 'Le gana al sol'],
    ],
  },
  {
    key: 'racha',
    emblem: 'racha',
    counter: 'streak_max',
    desc: 'Juega {n} días seguidos',
    tiers: [
      [3, 'Tres al hilo'],
      [7, 'Semana completa'],
      [30, 'De la casa'],
    ],
  },
  {
    key: 'coleccion',
    emblem: 'trofeo',
    counter: 'achievements',
    desc: 'Consigue {n} logros',
    tiers: [
      [10, 'Coleccionista'],
      [30, 'Vitrina llena'],
      [60, 'Lo tiene casi todo'],
      [90, 'Completista'],
    ],
  },
]

/** 1250 → "1.250". */
function formatCount(n: number) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '.')
}

/** Con cantidad 1 la frase va en singular: «Domina 1 sector», «Riega materas 1 vez». */
const SINGULAR: [RegExp, string][] = [
  [/\b1 sectores\b/, '1 sector'],
  [/\b1 objetos\b/, '1 objeto'],
  [/\b1 lugares\b/, '1 lugar'],
  [/\b1 domicilios\b/, '1 domicilio'],
  [/\b1 mandados\b/, '1 mandado'],
  [/\b1 turnos\b/, '1 turno'],
  [/\b1 cosas\b/, '1 cosa'],
  [/\b1 comidas\b/, '1 comida'],
  [/\b1 veces\b/, '1 vez'],
  [/\b1 unidades\b/, '1 unidad'],
  [/\b1 capítulos\b/, '1 capítulo'],
  [/\b1 amigos\b/, '1 amigo'],
  [/\b1 mensajes\b/, '1 mensaje'],
  [/\b1 materiales\b/, '1 material'],
  [/\b1 encargos o turnos\b/, '1 encargo o turno'],
]

function describe(template: string, count: number) {
  let text = template.replace('{n}', formatCount(count))
  if (count === 1) for (const [plural, singular] of SINGULAR) text = text.replace(plural, singular)
  return text
}

const TIER_REWARD = [
  { xp: 20, money: 10 },
  { xp: 60, money: 40 },
  { xp: 150, money: 120 },
  { xp: 400, money: 400 },
]

export const ACHIEVEMENTS: AchievementDefinition[] = FAMILIES.flatMap((family) =>
  family.tiers.map(([count, name], index) => {
    // Las familias de 2 o 3 niveles terminan en oro: bronce, plata, oro.
    const tier = index + 1
    return {
      key: `${family.key}_${tier}`,
      family: family.key,
      emblem: family.emblem,
      counter: family.counter,
      name,
      desc: describe(family.desc, count),
      tier,
      count,
      reward: TIER_REWARD[index],
    }
  })
)

export const ACHIEVEMENTS_BY_COUNTER = new Map<string, AchievementDefinition[]>()
for (const achievement of ACHIEVEMENTS) {
  const list = ACHIEVEMENTS_BY_COUNTER.get(achievement.counter) ?? []
  list.push(achievement)
  ACHIEVEMENTS_BY_COUNTER.set(achievement.counter, list)
}
