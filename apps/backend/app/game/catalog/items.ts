/**
 * Catálogo de objetos del juego. Para agregar uno basta con una entrada aquí
 * y su icono en apps/game/assets/art/items/<key>.png (no hace falta migración:
 * el inventario se guarda como clave-cantidad).
 *
 * kind:
 * - food:      se come (baja el hambre: `hunger` puntos).
 * - material:  para fabricar (recipes.ts) o vender.
 * - tool:      se conserva; algunas recetas la piden (`tool`), y las de
 *              `slots` agrandan el morral.
 * - placeable: se puede poner en el mapa (objects.ts, campo `object`).
 */

export type ItemKind = 'food' | 'material' | 'tool' | 'placeable'

export interface ItemDefinition {
  key: string
  name: string
  desc: string
  kind: ItemKind
  /** Precio base de compra. Las tiendas lo varían; vender paga una fracción. */
  price: number
  /** Puntos de hambre que quita al comer (solo food). */
  hunger?: number
  /** Espacios extra del morral mientras se tenga (solo tool). */
  slots?: number
  /** Tipo de objeto del mapa que coloca (solo placeable). */
  object?: string
  /** Influencia que da en el sector al ponerlo (solo placeable; por defecto RULES.objects.influence). */
  influence?: number
}

const food = (
  key: string,
  name: string,
  price: number,
  hunger: number,
  desc: string
): ItemDefinition => ({ key, name, desc, kind: 'food', price, hunger })
const material = (key: string, name: string, price: number, desc: string): ItemDefinition => ({
  key,
  name,
  desc,
  kind: 'material',
  price,
})
const placeable = (key: string, name: string, price: number, desc: string): ItemDefinition => ({
  key,
  name,
  desc,
  kind: 'placeable',
  price,
  object: key,
})

/** Decoración de lujo: solo se compra, cuesta una fortuna y marca más el territorio. */
const luxury = (
  key: string,
  name: string,
  price: number,
  influence: number,
  desc: string
): ItemDefinition => ({ ...placeable(key, name, price, desc), influence })

export const ITEMS: ItemDefinition[] = [
  // --- Comida -------------------------------------------------------------------
  food('pan', 'Pan', 8, 12, 'Recién salido del horno. O eso dice el letrero desde 1998.'),
  food('empanada', 'Empanada', 12, 18, 'Crocante por fuera, lava volcánica por dentro.'),
  food('arepa', 'Arepa', 14, 20, 'Redonda, noble y sin pretensiones.'),
  food('tinto', 'Tinto', 5, 6, 'Café negro en vasito. El combustible oficial del barrio.'),
  food('jugo', 'Jugo', 9, 10, 'Natural, natural… con dos cucharadas de azúcar.'),
  food(
    'almuerzo',
    'Almuerzo',
    35,
    55,
    'Corrientazo completo: sopa, seco y juguito. Siesta no incluida.'
  ),
  food('hamburguesa', 'Hamburguesa', 28, 40, 'Con todos los juguetes.'),
  food('pizza', 'Porción de pizza', 20, 30, 'La punta se dobla sola. Es la ley.'),
  food('helado', 'Helado', 10, 12, 'Se derrite más rápido de lo que te lo comes.'),
  food('fruta', 'Mango', 6, 10, 'Un mango maduro. Con sal y limón queda mejor.'),
  food('agua', 'Botella de agua', 4, 4, 'Hidratarse también es de valientes.'),
  food('chocolatina', 'Chocolatina', 6, 8, 'Para el antojo de las tres de la tarde.'),
  food(
    'arepa_rellena',
    'Arepa rellena',
    34,
    48,
    'Arepa con queso derretido. Peligrosamente buena.'
  ),
  food('chorizo', 'Chorizo asado', 30, 42, 'Con arepita y limón, como debe ser.'),
  food('limonada', 'Limonada', 16, 16, 'Fría, con hielo y hecha por ti. Sabe a victoria.'),
  food('sanduche', 'Sánduche', 24, 30, 'Pan, queso y buena voluntad.'),

  // --- Materiales ---------------------------------------------------------------
  material('palo', 'Palo', 2, 'Una rama firme. Sirve para casi todo.'),
  material('hoja', 'Hojas', 1, 'Hojas verdes. Trenzadas hacen maravillas.'),
  material('piedra', 'Piedra', 4, 'Una piedra común, pero con carácter.'),
  material('semilla', 'Semillas', 3, 'Un puñado de semillas. Futuro en miniatura.'),
  material('flor', 'Flor', 8, 'Le alegra el día a cualquiera.'),
  material('pina', 'Piña de pino', 3, 'Cayó de un pino. Decorativa y puntiaguda.'),
  material('tabla', 'Tabla', 10, 'Madera cepillada, lista para armar algo.'),
  material('clavos', 'Clavos', 3, 'Un puñado. Siempre sobra uno.'),
  material('pintura', 'Pintura', 18, 'Un tarro de pintura roja. Mancha garantizada.'),
  material('tela', 'Tela', 14, 'Un retazo generoso de tela azul.'),
  material('cuerda', 'Cuerda', 8, 'Resistente. Aguanta hasta un trasteo.'),
  material('botella', 'Botella', 2, 'Vacía, de vidrio. Alguien dirá que es basura; tú no.'),
  material('masa', 'Masa', 6, 'Masa de maíz lista para la parrilla.'),
  material('queso', 'Queso', 9, 'Queso fresco. Hace chillar la arepa.'),
  material('carne', 'Chorizos crudos', 14, 'Les falta candela.'),
  material('carbon', 'Carbón', 7, 'Para la parrilla. Y para tiznarse las manos.'),
  material('chatarra', 'Chatarra', 6, 'Tuercas, tornillos y un engranaje misterioso.'),

  // --- Herramientas -------------------------------------------------------------
  {
    key: 'martillo',
    name: 'Martillo',
    desc: 'Con esto ya puedes armar muebles sin pedirle el favor a nadie.',
    kind: 'tool',
    price: 45,
  },
  {
    key: 'canasta',
    name: 'Canasta',
    desc: 'Cabe más mercado. Agranda el morral en 4 espacios.',
    kind: 'tool',
    price: 60,
    slots: 4,
  },
  {
    key: 'morral',
    name: 'Morral grande',
    desc: 'De los que cargan media casa. Agranda el morral en 8 espacios.',
    kind: 'tool',
    price: 180,
    slots: 8,
  },

  // --- Para poner en el mapa ----------------------------------------------------
  placeable('matera', 'Matera', 30, 'Riégala y florece. Embellece el andén y suma influencia.'),
  placeable('banca', 'Banca', 70, 'Para sentarse a ver pasar la vida.'),
  placeable('letrero', 'Letrero', 25, 'Deja un mensaje para el que pase.'),
  placeable('caja', 'Caja de trueque', 80, 'Deja algo, llévate algo. Así funciona el barrio.'),
  placeable(
    'puesto',
    'Puesto de venta',
    260,
    'Tu propio negocio: surte, pon precios y recoge la plata.'
  ),
  placeable('parrilla', 'Parrilla', 90, 'Para asar arepas y chorizos. Cualquiera puede usarla.'),
  placeable(
    'mesa',
    'Mesa de trabajo',
    110,
    'Para fabricar muebles y cosas grandes. Cualquiera puede usarla.'
  ),
  placeable('bandera', 'Bandera', 60, 'Plántala para pelear por el dominio de un sector.'),
  placeable('farol', 'Farol', 55, 'Alumbra la cuadra de noche.'),
  placeable('fiesta', 'Mesa de fiesta', 500, 'Torta, bombas y motivo de sobra para celebrar.'),

  // --- Decoración de lujo (metas de ahorro: solo en tiendas, a precio de oro) -----
  luxury(
    'seto',
    'Seto podado',
    900,
    6,
    'Un cubo verde perfecto. Sirve para marcar hasta dónde llega lo tuyo.'
  ),
  luxury('cerca', 'Cerca blanca', 800, 6, 'De las de película. Delimita con elegancia.'),
  luxury(
    'muro',
    'Muro de ladrillo',
    1200,
    7,
    'Ladrillo a la vista. Dice “aquí mando yo” sin gritar.'
  ),
  luxury('columna', 'Columna de mármol', 2200, 9, 'No sostiene nada, pero qué porte.'),
  luxury('palmera', 'Palma real', 1500, 8, 'Una palma en matera. El trópico, a domicilio.'),
  luxury(
    'farola',
    'Farola doble',
    2000,
    9,
    'Hierro forjado y dos faroles. La cuadra queda de postal.'
  ),
  luxury('arco', 'Arco de flores', 2800, 10, 'Todo el que pase por debajo se siente en una boda.'),
  luxury(
    'fuente',
    'Fuente de piedra',
    3500,
    12,
    'El sonido del agua sube el estrato de la cuadra.'
  ),
  luxury('reloj', 'Reloj de plaza', 4500, 14, 'Da la hora. Más o menos.'),
  luxury(
    'estandarte',
    'Estandarte',
    5000,
    16,
    'Carmesí y oro, con tu nombre. Que se vea desde lejos.'
  ),
  luxury(
    'estatua',
    'Estatua de bronce',
    6000,
    18,
    'Un prócer anónimo que se parece sospechosamente a ti.'
  ),
  luxury('molino', 'Molino', 7500, 20, 'No muele nada, pero hipnotiza a los vecinos.'),
  luxury('kiosco', 'Kiosco', 9500, 24, 'La glorieta del parque. Solo falta la banda.'),
  luxury('arbol_dorado', 'Árbol dorado', 12000, 28, 'Hojas de oro. No se cosecha, se presume.'),
  luxury('obelisco', 'Obelisco', 15000, 32, 'Granito, punta dorada y cero modestia.'),
  luxury('trono', 'Trono dorado', 25000, 45, 'Para quien manda en el barrio. Terciopelo incluido.'),
]

export const ITEMS_BY_KEY = new Map(ITEMS.map((item) => [item.key, item]))

/** Espacios del morral sin mejoras y tope de unidades por espacio. */
export const BASE_SLOTS = 16
export const MAX_STACK = 60
/** Vender a una tienda paga esta fracción del precio base. */
export const SELL_FRACTION = 0.4
