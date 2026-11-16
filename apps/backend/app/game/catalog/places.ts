import type { PoiCategory } from '#map/poi_category'

/**
 * Qué se puede hacer en cada lugar del mapa (los puntos de interés reales de
 * OpenStreetMap). El mapa es el mundo real, así que nada se define por lugar
 * concreto: cada lugar toma un PERFIL según su etiqueta OSM (`kind`) o, si no
 * hay uno específico, según su categoría. Así el juego funciona igual en
 * cualquier ciudad.
 *
 * Qué vende exactamente cada lugar y a qué precio se decide con un hash de su
 * id (ver GameService): es estable, y comparar precios entre tiendas vale la pena.
 */

export interface PlaceService {
  key: string
  label: string
  /** Texto al usarlo. */
  done: string
  cost: number
  xp: number
  /** Hambre que da (negativo) o quita. */
  hunger?: number
  cooldownHours: number
  /** Contador que suma (logros). */
  counter: string
}

export interface PlaceProfile {
  key: string
  /** "Panadería", "Tienda"… (se muestra bajo el nombre real del lugar). */
  label: string
  /** Retrato (apps/game/assets/art/npcs/<portrait>.png) y oficio de quien atiende. */
  portrait: string
  role: string
  names: string[]
  greetings: string[]
  /** Objetos que puede vender (cada lugar ofrece una parte). */
  sells: string[]
  /** Objetos que compra a buen precio (fracción del precio base). */
  wants: Record<string, number>
  /** Turno de trabajo: qué se hace y cuánto paga (mínimo, máximo). */
  work?: { label: string; done: string; pay: [number, number] }
  services?: PlaceService[]
  /** Recargo sobre el precio base (lugares que no son tiendas de verdad). */
  markup?: number
}

const MEN = ['Don Hernán', 'Don Fabio', 'Don Rigo', 'Don Álvaro', 'Don Nelson', 'Don Jairo']
const WOMEN = ['Doña Gloria', 'Doña Luz', 'Doña Mery', 'Doña Stella', 'Doña Nubia', 'Doña Amparo']
const YOUNG = ['Juancho', 'Caro', 'Santi', 'Vale', 'Nico', 'Dani']

export const PLACE_PROFILES: Record<string, PlaceProfile> = {
  panaderia: {
    key: 'panaderia',
    label: 'Panadería',
    portrait: 'panadero',
    role: 'el panadero',
    names: MEN,
    greetings: [
      '¡Buenas! El pan está caliente y el chisme también.',
      'Llegó justo: acabo de sacar una bandeja.',
      '¿Qué le doy? Hoy amanecí generoso… pero no tanto.',
    ],
    sells: ['pan', 'empanada', 'tinto', 'chocolatina', 'masa', 'jugo'],
    wants: { masa: 0.9, queso: 0.8 },
    work: {
      label: 'Amasar pan',
      done: 'Quedaste lleno de harina, pero el pan salió.',
      pay: [16, 26],
    },
  },
  cafe: {
    key: 'cafe',
    label: 'Café',
    portrait: 'barista',
    role: 'el barista',
    names: YOUNG,
    greetings: [
      '¿Un tinto? ¿O prefieres algo con nombre en italiano que significa lo mismo?',
      'Bienvenido. Aquí el wifi es gratis y la silla también, un rato.',
      'Hoy el café está tan bueno que hasta yo me lo tomo.',
    ],
    sells: ['tinto', 'jugo', 'sanduche', 'pan', 'chocolatina', 'agua'],
    wants: { fruta: 0.9, flor: 0.8 },
    work: { label: 'Atender mesas', done: 'Nadie se quejó. Bueno, casi nadie.', pay: [18, 28] },
  },
  restaurante: {
    key: 'restaurante',
    label: 'Restaurante',
    portrait: 'cocinera',
    role: 'la cocinera',
    names: WOMEN,
    greetings: [
      '¡Siga, mijo! Hoy hay fríjoles. Bueno, siempre hay fríjoles.',
      'Siéntese donde quiera, menos en la mesa del señor de siempre.',
      '¿Almuerzo? Sale volando. Volando es un decir.',
    ],
    sells: ['almuerzo', 'jugo', 'arepa', 'limonada', 'agua'],
    wants: { fruta: 0.9, queso: 0.9, carne: 0.9, arepa_rellena: 1, chorizo: 1 },
    work: { label: 'Lavar platos', done: 'Loza brillante y manos de uva pasa.', pay: [20, 32] },
  },
  comida_rapida: {
    key: 'comida_rapida',
    label: 'Comidas rápidas',
    portrait: 'cocinera',
    role: 'la de la plancha',
    names: WOMEN,
    greetings: [
      '¿Con todo? Aquí “con todo” es con todo.',
      'Rápidas sí, afanadas no. ¿Qué va a pedir?',
      'La salsa de la casa es secreta. Es mayonesa con algo.',
    ],
    sells: ['hamburguesa', 'pizza', 'empanada', 'agua', 'jugo'],
    wants: { carne: 0.9, queso: 0.9, masa: 0.8 },
    work: {
      label: 'Armar pedidos',
      done: 'Veinte pedidos y ninguno equivocado. Milagro.',
      pay: [18, 30],
    },
  },
  heladeria: {
    key: 'heladeria',
    label: 'Heladería',
    portrait: 'barista',
    role: 'el heladero',
    names: YOUNG,
    greetings: [
      'Hay de todos los sabores. Menos del que usted quiere, seguro.',
      '¿Cono o vasito? Piénselo bien, es una decisión seria.',
    ],
    sells: ['helado', 'agua', 'jugo', 'chocolatina'],
    wants: { fruta: 1 },
    work: {
      label: 'Servir helados',
      done: 'Te quedó el brazo como de fisicoculturista.',
      pay: [15, 24],
    },
  },
  bar: {
    key: 'bar',
    label: 'Bar',
    portrait: 'barista',
    role: 'el de la barra',
    names: YOUNG,
    greetings: [
      'Aquí solo vendemos limonada. Y recuerdos.',
      '¿Lo de siempre? Ah, usted es nuevo. Entonces lo de siempre de otro.',
    ],
    sells: ['limonada', 'agua', 'empanada', 'jugo'],
    wants: { fruta: 0.9, chorizo: 1, empanada: 0.7 },
    work: { label: 'Recoger mesas', done: 'Botellas recogidas, propina simbólica.', pay: [18, 30] },
  },
  tienda: {
    key: 'tienda',
    label: 'Tienda',
    portrait: 'tendera',
    role: 'la tendera',
    names: WOMEN,
    greetings: [
      '¿Qué se le ofrece, veci?',
      'Aquí fiamos… mañana. Hoy no.',
      'Hay de todo, y lo que no hay se lo consigo.',
    ],
    sells: ['agua', 'fruta', 'pan', 'queso', 'carne', 'masa', 'chocolatina', 'carbon', 'botella'],
    wants: { fruta: 0.8, flor: 0.7, semilla: 0.8 },
    work: {
      label: 'Acomodar estantes',
      done: 'Todo en su puesto. Hasta las papas.',
      pay: [15, 26],
    },
  },
  ferreteria: {
    key: 'ferreteria',
    label: 'Ferretería',
    portrait: 'ferretero',
    role: 'el ferretero',
    names: MEN,
    greetings: [
      '¿Qué va a arreglar hoy? ¿O qué va a dañar?',
      'Tornillo que busque, tornillo que tengo.',
      'Si no sabe cómo se llama la pieza, hágame el ruido que hace.',
    ],
    sells: [
      'tabla',
      'clavos',
      'pintura',
      'cuerda',
      'martillo',
      'chatarra',
      'carbon',
      'cerca',
      'muro',
      'columna',
      'farola',
      'reloj',
      'molino',
    ],
    wants: { chatarra: 0.9, piedra: 0.9, palo: 1, pina: 0.7 },
    work: {
      label: 'Contar tornillos',
      done: 'Eran 1.482. O 1.483. Uno se te cayó.',
      pay: [18, 28],
    },
  },
  miscelanea: {
    key: 'miscelanea',
    label: 'Almacén',
    portrait: 'tendera',
    role: 'la del almacén',
    names: WOMEN,
    greetings: [
      'Bien pueda, mire sin compromiso.',
      'Eso que busca sí lo tengo. Creo.',
      'Todo a buen precio y con la sonrisa incluida.',
    ],
    sells: [
      'tela',
      'cuerda',
      'botella',
      'pintura',
      'canasta',
      'tabla',
      'clavos',
      'seto',
      'palmera',
      'arco',
      'fuente',
      'estandarte',
    ],
    wants: { flor: 0.9, hoja: 1, pina: 0.9, semilla: 0.7 },
    work: {
      label: 'Doblar mercancía',
      done: 'Doblaste tanto que ya ves todo cuadrado.',
      pay: [15, 25],
    },
  },
  farmacia: {
    key: 'farmacia',
    label: 'Salud',
    portrait: 'farmaceuta',
    role: 'la farmaceuta',
    names: WOMEN,
    greetings: [
      'Tómese esto con agua. No, eso es el agua.',
      '¿Qué le duele? Aparte de la quincena.',
    ],
    sells: ['agua', 'jugo', 'chocolatina'],
    wants: { hoja: 0.9, flor: 0.8 },
    work: {
      label: 'Organizar el mostrador',
      done: 'Ordenado por colores. No era la idea, pero quedó bonito.',
      pay: [16, 26],
    },
  },
  banco: {
    key: 'banco',
    label: 'Banco',
    portrait: 'cajera',
    role: 'la cajera',
    names: WOMEN,
    greetings: [
      'Tome su turno. Es el 348. Vamos en el 12.',
      'Aquí cuidamos su plata. La poquita y la otra.',
    ],
    sells: ['arbol_dorado', 'trono'],
    wants: {},
    work: {
      label: 'Organizar la fila',
      done: 'La fila quedó derechita. Duró así dos minutos.',
      pay: [22, 34],
    },
  },
  educacion: {
    key: 'educacion',
    label: 'Educación',
    portrait: 'bibliotecario',
    role: 'el bibliotecario',
    names: MEN,
    greetings: [
      'Shhh. Bienvenido. Shhh.',
      'Aquí el que no sabe, aprende. Y el que sabe, se calla.',
    ],
    sells: [],
    wants: {},
    work: {
      label: 'Ordenar libros',
      done: 'Por orden alfabético. O casi: la Ñ te confundió.',
      pay: [16, 26],
    },
    services: [
      {
        key: 'estudiar',
        label: 'Estudiar un rato',
        done: 'Aprendiste algo nuevo. No sabes bien qué, pero se siente.',
        cost: 20,
        xp: 45,
        hunger: 5,
        cooldownHours: 12,
        counter: 'studies',
      },
    ],
  },
  cultura: {
    key: 'cultura',
    label: 'Cultura',
    portrait: 'yeison',
    role: 'el guía',
    names: YOUNG,
    greetings: [
      'Esto que ve aquí tiene más historia que su abuela.',
      'Pase y mire. Tocar no, mirar sí.',
    ],
    sells: ['estatua', 'obelisco', 'kiosco'],
    wants: { flor: 0.9, pintura: 0.8 },
    services: [
      {
        key: 'recorrido',
        label: 'Hacer el recorrido',
        done: 'Ahora sabes tres datos curiosos para presumir.',
        cost: 12,
        xp: 30,
        cooldownHours: 12,
        counter: 'tours',
      },
    ],
  },
  hospedaje: {
    key: 'hospedaje',
    label: 'Hospedaje',
    portrait: 'vecino',
    role: 'el recepcionista',
    names: YOUNG,
    greetings: [
      'Bienvenido. El desayuno es de 6 a 6 y cuarto.',
      '¿Habitación? Tenemos con vista a la pared o con vista a la otra pared.',
    ],
    sells: ['agua', 'tinto', 'sanduche'],
    wants: { flor: 1.1 },
    work: { label: 'Tender camas', done: 'Camas tendidas, almohadas esponjadas.', pay: [18, 30] },
  },
  deporte: {
    key: 'deporte',
    label: 'Deporte',
    portrait: 'vecino',
    role: 'el entrenador',
    names: MEN,
    greetings: [
      '¡Esa es la actitud! ¿Vino a sudar o a mirar?',
      'El que no calienta, se lesiona. Y el que calienta mucho, también.',
    ],
    sells: ['agua', 'jugo'],
    wants: {},
    services: [
      {
        key: 'entrenar',
        label: 'Entrenar',
        done: 'Mañana te va a doler hasta el nombre.',
        cost: 0,
        xp: 25,
        hunger: 12,
        cooldownHours: 8,
        counter: 'trainings',
      },
    ],
  },
  transporte: {
    key: 'transporte',
    label: 'Transporte',
    portrait: 'conductor',
    role: 'el conductor',
    names: MEN,
    greetings: [
      '¡Súbase que sí cabe! Bueno, ya no. Era un decir.',
      'Yo conozco esta ciudad como la palma de mi mano. La izquierda.',
    ],
    sells: ['agua', 'chocolatina'],
    wants: { chatarra: 0.9 },
    work: { label: 'Lavar el bus', done: 'Quedó brillando. Mañana llueve, fijo.', pay: [20, 32] },
  },
  culto: {
    key: 'culto',
    label: 'Lugar tranquilo',
    portrait: 'vecino',
    role: 'un vecino',
    names: MEN,
    greetings: ['Aquí se respira calma. Aproveche.'],
    sells: [],
    wants: {},
  },
  vecino: {
    key: 'vecino',
    label: 'Lugar del barrio',
    portrait: 'vecino',
    role: 'un vecino',
    names: [...MEN, ...WOMEN],
    greetings: [
      '¿Busca algo? Yo de pronto le consigo, pero no es gratis.',
      'Aquí no es tienda, pero uno se rebusca.',
      'Dígame qué necesita y miramos.',
    ],
    sells: ['agua', 'pan', 'tabla', 'clavos', 'cuerda'],
    wants: {},
    work: { label: 'Hacer un mandado', done: 'Mandado hecho. El vuelto, completo.', pay: [14, 22] },
    markup: 1.4,
  },
}

/** Etiquetas OSM (lo que va después de "amenity:", "shop:"…) → perfil. */
const KIND_PROFILE: Record<string, string> = {
  // Comida
  bakery: 'panaderia',
  pastry: 'panaderia',
  confectionery: 'panaderia',
  cafe: 'cafe',
  coffee: 'cafe',
  restaurant: 'restaurante',
  food_court: 'restaurante',
  fast_food: 'comida_rapida',
  ice_cream: 'heladeria',
  bar: 'bar',
  pub: 'bar',
  biergarten: 'bar',
  nightclub: 'bar',
  // Tiendas
  convenience: 'tienda',
  supermarket: 'tienda',
  greengrocer: 'tienda',
  butcher: 'tienda',
  deli: 'tienda',
  marketplace: 'tienda',
  kiosk: 'tienda',
  general: 'tienda',
  mall: 'tienda',
  hardware: 'ferreteria',
  doityourself: 'ferreteria',
  trade: 'ferreteria',
  paint: 'ferreteria',
  lighting: 'ferreteria',
  electronics: 'ferreteria',
  appliance: 'ferreteria',
  motorcycle: 'ferreteria',
  car_repair: 'ferreteria',
  bicycle: 'ferreteria',
}

const CATEGORY_PROFILE: Record<PoiCategory, string> = {
  food: 'restaurante',
  shop: 'miscelanea',
  health: 'farmacia',
  education: 'educacion',
  worship: 'culto',
  money: 'banco',
  transport: 'transporte',
  culture: 'cultura',
  lodging: 'hospedaje',
  sport: 'deporte',
  service: 'vecino',
  other: 'vecino',
}

export function placeProfile(kind: string, category: PoiCategory): PlaceProfile {
  const tag = kind.split(':')[1] ?? ''
  const key = KIND_PROFILE[tag] ?? CATEGORY_PROFILE[category] ?? 'vecino'
  return PLACE_PROFILES[key]
}

/** Categorías junto a las que no se pueden poner objetos (respeto por el lugar real). */
export const NO_BUILD_CATEGORIES: ReadonlySet<string> = new Set(['worship', 'health', 'education'])

// --- Rebusque: materiales que dan los objetos del mapa --------------------------

export interface GatherDrop {
  item: string
  /** Probabilidad (0..1) de que salga. */
  chance: number
  qty: [number, number]
}

export interface GatherSource {
  /** Texto al rebuscar. */
  text: string
  /** Texto si no sale nada. */
  empty: string
  drops: GatherDrop[]
  /** Monedas sueltas (probabilidad y cantidad). */
  coins?: { chance: number; amount: [number, number] }
  /** Minutos hasta poder volver a rebuscar en la misma celda. */
  cooldownMinutes: number
}

/** Por nombre de prop (ver #map/catalog → Prop). */
export const GATHER: Record<string, GatherSource> = {
  TREE: {
    text: 'Sacudiste el árbol.',
    empty: 'El árbol no soltó nada. Te miró feo, eso sí.',
    drops: [
      { item: 'palo', chance: 0.85, qty: [1, 2] },
      { item: 'hoja', chance: 0.5, qty: [1, 2] },
      { item: 'fruta', chance: 0.12, qty: [1, 1] },
    ],
    cooldownMinutes: 20,
  },
  PINE: {
    text: 'Rebuscaste bajo el pino.',
    empty: 'Solo agujas de pino. Y una te pinchó.',
    drops: [
      { item: 'palo', chance: 0.7, qty: [1, 2] },
      { item: 'pina', chance: 0.5, qty: [1, 1] },
    ],
    cooldownMinutes: 20,
  },
  BUSH: {
    text: 'Esculcaste el arbusto.',
    empty: 'Nada. Solo un bicho que salió ofendido.',
    drops: [
      { item: 'hoja', chance: 0.8, qty: [1, 3] },
      { item: 'semilla', chance: 0.4, qty: [1, 1] },
      { item: 'flor', chance: 0.12, qty: [1, 1] },
      { item: 'piedra', chance: 0.12, qty: [1, 1] },
    ],
    cooldownMinutes: 20,
  },
  ROCK: {
    text: 'Le diste vueltas a la roca.',
    empty: 'Es una roca. Sigue siendo una roca.',
    drops: [{ item: 'piedra', chance: 1, qty: [1, 3] }],
    cooldownMinutes: 30,
  },
  BENCH: {
    text: 'Revisaste entre las tablas de la banca.',
    empty: 'Nada entre las tablas. Alguien llegó primero.',
    drops: [{ item: 'botella', chance: 0.3, qty: [1, 1] }],
    coins: { chance: 0.45, amount: [1, 6] },
    cooldownMinutes: 60,
  },
  STREET_LAMP: {
    text: 'Miraste al pie del poste.',
    empty: 'Al pie del poste no hay nada. Hoy.',
    drops: [
      { item: 'chatarra', chance: 0.35, qty: [1, 1] },
      { item: 'botella', chance: 0.25, qty: [1, 1] },
    ],
    cooldownMinutes: 60,
  },
  TRAFFIC_LIGHT: {
    text: 'Esperaste el verde mirando al piso.',
    empty: 'Nada en el piso. Pero cruzaste bien la calle.',
    drops: [{ item: 'chatarra', chance: 0.3, qty: [1, 1] }],
    coins: { chance: 0.25, amount: [1, 4] },
    cooldownMinutes: 60,
  },
  BUS_STOP: {
    text: 'Revisaste el paradero.',
    empty: 'Solo un volante de “se arreglan lavadoras”.',
    drops: [
      { item: 'botella', chance: 0.4, qty: [1, 1] },
      { item: 'chatarra', chance: 0.2, qty: [1, 1] },
    ],
    coins: { chance: 0.3, amount: [1, 5] },
    cooldownMinutes: 60,
  },
  FOUNTAIN: {
    text: 'Te asomaste a la fuente.',
    empty: 'Agua y deseos ajenos. Mejor no tocar.',
    drops: [{ item: 'agua', chance: 0.6, qty: [1, 1] }],
    coins: { chance: 0.6, amount: [2, 8] },
    cooldownMinutes: 120,
  },
  STATUE: {
    text: 'Le diste la vuelta al monumento.',
    empty: 'El monumento te ignoró con elegancia.',
    drops: [{ item: 'flor', chance: 0.3, qty: [1, 1] }],
    cooldownMinutes: 120,
  },
}
