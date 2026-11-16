/**
 * Historia principal: «Dueños del barrio».
 *
 * Como el mapa es el mundo real, nada ocurre en un lugar fijo: los personajes
 * aparecen en CUALQUIER lugar de las categorías indicadas (`talk.cats`), y los
 * objetivos son cosas que se pueden hacer en cualquier ciudad. Si en la zona no
 * hay ningún lugar de esas categorías, el personaje atiende por teléfono.
 *
 * Cada capítulo tiene pasos en orden; cada paso tiene una o más metas que se
 * cumplen en paralelo. Tipos de meta:
 *   counter  suma de un contador desde que empezó el paso (jobs_completed…)
 *   total    valor total de un contador o medida (pois_discovered, sectors_owned…)
 *   stat     valor de un stat: money, level
 *   have     tener objetos en el morral
 *   talk     hablar con un personaje
 */

export type GoalDefinition =
  | { type: 'counter'; key: string; count: number; text: string }
  | { type: 'total'; key: string; count: number; text: string }
  | { type: 'stat'; key: 'money' | 'level'; count: number; text: string }
  | { type: 'have'; item: string; count: number; text: string }
  | { type: 'talk'; npc: string; cats: string[]; text: string; lines: string[] }

export interface Dialog {
  npc: string
  lines: string[]
}

export interface StepDefinition {
  key: string
  /** Pista de cómo se hace (se muestra bajo las metas). */
  hint?: string
  /** Lo dice el personaje al empezar el paso. */
  intro?: Dialog
  /** Objetos que el personaje te da al empezar el paso. */
  give?: Record<string, number>
  goals: GoalDefinition[]
}

export interface ChapterDefinition {
  key: string
  title: string
  /** Resumen de una línea para el diario. */
  summary: string
  npc: string
  steps: StepDefinition[]
  reward: { money: number; xp: number; items?: Record<string, number> }
  outro: Dialog
}

export interface NpcDefinition {
  key: string
  name: string
  role: string
  portrait: string
}

export const NPCS: Record<string, NpcDefinition> = {
  mona: { key: 'mona', name: 'La Mona', role: 'Mensajera en bici', portrait: 'mona' },
  chepe: { key: 'chepe', name: 'Don Chepe', role: 'Tendero de toda la vida', portrait: 'chepe' },
  marta: {
    key: 'marta',
    name: 'La Profe Marta',
    role: 'Hace los mapas del barrio',
    portrait: 'marta',
  },
  wilmer: {
    key: 'wilmer',
    name: 'El Flaco Wilmer',
    role: 'Todero: arma lo que sea',
    portrait: 'wilmer',
  },
  pola: { key: 'pola', name: 'Doña Pola', role: 'Presidenta de la junta', portrait: 'pola' },
  tulia: { key: 'tulia', name: 'La abuela Tulia', role: 'Jardinera del andén', portrait: 'tulia' },
  yeison: { key: 'yeison', name: 'Yeison', role: 'Artista de la cuadra', portrait: 'yeison' },
  gris: { key: 'gris', name: 'Don Gris', role: 'Constructora Gris S.A.', portrait: 'gris' },
}

const ANYWHERE = ['shop', 'food', 'service', 'other', 'culture', 'lodging', 'transport', 'money']

export const STORY: ChapterDefinition[] = [
  // ---------------------------------------------------------------------------
  {
    key: 'tutorial',
    title: 'Recién desempacado',
    summary: 'La Mona te enseña a sobrevivir en el barrio.',
    npc: 'mona',
    steps: [
      {
        key: 'caminar',
        hint: 'Toca el suelo para caminar hasta ahí, o usa WASD / el joystick. Mantén Shift para correr.',
        intro: {
          npc: 'mona',
          lines: [
            '¡Quiubo! Tú debes ser el nuevo. Yo soy La Mona: mensajera, guía turística y chismosa oficial del barrio.',
            'Esta ciudad es igualita a la de verdad, pero aquí sí alcanza el tiempo.',
            'Te voy a mostrar cómo es la vuelta. Primero lo primero: camina un poco, a ver si no te tropiezas.',
          ],
        },
        goals: [{ type: 'counter', key: 'distance_m', count: 25, text: 'Camina un poco' }],
      },
      {
        key: 'chismosear',
        hint: 'Los pines de colores son lugares de verdad. Acércate a uno y pulsa Interactuar (E o el botón A).',
        intro: {
          npc: 'mona',
          lines: [
            '¡Eso! Caminas mejor que mi primo, y él lleva treinta años practicando.',
            '¿Ves esos pines de colores? Son lugares de verdad: tiendas, restaurantes, de todo.',
            'Ve a chismosear uno. En cada lugar hay alguien que vende, compra o da trabajo.',
          ],
        },
        goals: [
          { type: 'counter', key: 'pois_discovered', count: 1, text: 'Visita un lugar del mapa' },
        ],
      },
      {
        key: 'comer',
        hint: 'Abre el morral (tecla I o el botón de la mochila), elige la empanada y pulsa Comer.',
        intro: {
          npc: 'mona',
          lines: [
            'Ojo con la barra de arriba a la derecha: es el hambre. Si llega a cero no puedes correr y el trabajo te rinde la mitad.',
            'Toma, te regalo dos empanadas. Son de ayer, pero de ayer en la tarde.',
            'Abre el morral y cómete una.',
          ],
        },
        give: { empanada: 2 },
        goals: [{ type: 'counter', key: 'food_eaten', count: 1, text: 'Cómete una empanada' }],
      },
      {
        key: 'rebuscar',
        hint: 'Párate junto a un árbol o un arbusto y pulsa Interactuar. Cada uno se recupera a los 20 minutos.',
        intro: {
          npc: 'mona',
          lines: [
            'Barriga llena, corazón contento. Ahora, a rebuscar.',
            'Los árboles y los arbustos sueltan cosas útiles si los esculcas: palos, hojas, semillas.',
            'Consigue 4 palos y 2 hojas. Te dejo una semilla, que esas son más esquivas.',
          ],
        },
        give: { semilla: 1 },
        goals: [
          { type: 'have', item: 'palo', count: 4, text: 'Consigue 4 palos (en los árboles)' },
          { type: 'have', item: 'hoja', count: 2, text: 'Consigue 2 hojas (en los arbustos)' },
        ],
      },
      {
        key: 'fabricar',
        hint: 'Abre el morral, ve a la pestaña Fabricar y elige la matera.',
        intro: {
          npc: 'mona',
          lines: [
            'Con eso ya puedes armar una matera. Sí, tú. Con esas manos.',
            'En el morral hay una pestaña que dice Fabricar. Ahí están las recetas.',
          ],
        },
        goals: [{ type: 'counter', key: 'crafted_matera', count: 1, text: 'Fabrica una matera' }],
      },
      {
        key: 'colocar',
        hint: 'En el morral, elige la matera y pulsa Colocar. Tiene que ser en un andén o zona verde, no en la calle.',
        intro: {
          npc: 'mona',
          lines: [
            '¡Te quedó hasta derecha! Ahora ponla en el andén.',
            'Todo lo que dejes en el mapa lo ven los demás jugadores, y pueden usarlo: regar tu matera, por ejemplo.',
            'Además, cada cosa buena que haces en un sector te da influencia ahí. De eso se trata este barrio.',
          ],
        },
        goals: [
          { type: 'counter', key: 'objects_placed', count: 1, text: 'Coloca la matera en el mapa' },
        ],
      },
      {
        key: 'encargo',
        hint: 'En cualquier lugar, pulsa Encargos, acepta uno y sigue la flecha. También los ves en Menú → Misiones.',
        intro: {
          npc: 'mona',
          lines: [
            'Bonita. Pero de materas no se vive: toca ganarse la plata.',
            'En cada lugar hay encargos: domicilios, mandados, vueltas. Pagan con plata y experiencia.',
            'Acepta uno y complétalo. Yo así empecé, y mírame: sigo en lo mismo, pero feliz.',
          ],
        },
        goals: [{ type: 'counter', key: 'jobs_completed', count: 1, text: 'Completa un encargo' }],
      },
      {
        key: 'comprar',
        hint: 'Entra a un lugar que venda comida (los pines naranja) y compra lo que quieras.',
        intro: {
          npc: 'mona',
          lines: [
            '¡Plata! Ahora gástala con sabiduría. O sea, en comida.',
            'Cada lugar vende cosas distintas y a precios distintos. Comparar no es de tacaños: es de vivos.',
          ],
        },
        goals: [{ type: 'counter', key: 'purchases', count: 1, text: 'Compra algo en un lugar' }],
      },
    ],
    reward: { money: 80, xp: 60, items: { arepa: 2 } },
    outro: {
      npc: 'mona',
      lines: [
        'Listo: ya no eres turista. Eres vecino en período de prueba.',
        'Toma esta platica y unas arepas para el camino.',
        'Si quieres progresar, busca a Don Chepe. Atiende en una tienda… bueno, en todas. Nadie sabe cómo le hace.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'rebusque',
    title: 'El rebusque',
    summary: 'Don Chepe te enseña a ganarte la vida.',
    npc: 'chepe',
    steps: [
      {
        key: 'hablar',
        hint: 'Entra a cualquier tienda o lugar de comida y pulsa Hablar.',
        goals: [
          {
            type: 'talk',
            npc: 'chepe',
            cats: ['shop', 'food'],
            text: 'Habla con Don Chepe en una tienda',
            lines: [
              '¿Usted es el que mandó La Mona? Lo imaginaba más alto.',
              'Yo llevo cuarenta años detrás de un mostrador. Empecé vendiendo bolis y hoy… sigo vendiendo bolis. Pero en muchas partes.',
              'El secreto es sencillo: el que no se mueve, no come. Haga encargos, trabaje turnos y ahorre.',
              'Vuelva cuando tenga 300 pesos juntos y callo en las manos.',
            ],
          },
        ],
      },
      {
        key: 'trabajar',
        hint: 'Los turnos se piden en cada lugar (botón Trabajar). Un mismo lugar da turno cada 10 minutos.',
        goals: [
          { type: 'counter', key: 'jobs_completed', count: 4, text: 'Completa 4 encargos' },
          { type: 'counter', key: 'work_shifts', count: 3, text: 'Trabaja 3 turnos' },
          { type: 'stat', key: 'money', count: 300, text: 'Junta $300' },
        ],
      },
    ],
    reward: { money: 100, xp: 120, items: { martillo: 1 } },
    outro: {
      npc: 'chepe',
      lines: [
        '¡Vea pues! Trescientos pesos y todavía sonríe. Va por buen camino.',
        'Tome este martillo. Era de mi papá. Bueno, era de un cliente que nunca volvió por él.',
        'Ahora vaya donde la Profe Marta. Ella conoce cada rincón de esta ciudad, y a usted le falta calle.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'vecindario',
    title: 'Conociendo el vecindario',
    summary: 'La Profe Marta quiere que camines la ciudad.',
    npc: 'marta',
    steps: [
      {
        key: 'hablar',
        hint: 'La Profe está en bibliotecas, colegios, museos y sitios así.',
        goals: [
          {
            type: 'talk',
            npc: 'marta',
            cats: ['education', 'culture', 'service', 'other'],
            text: 'Habla con la Profe Marta',
            lines: [
              '¡Ah, el nuevo! Siéntese. No, ahí no, esa silla es decorativa.',
              'Yo dibujo los mapas del barrio. La ciudad se divide en sectores, y cada sector tiene su gente y su maña.',
              'Mientras más haga usted en un sector, más lo conocen: primero Visitante, luego Vecino, Conocido, Referente… y los que saben, Leyenda.',
              'A los vecinos les rebajan en las tiendas, ¿sabía? Váyase a caminar: quiero que conozca lugares de todo tipo.',
            ],
          },
        ],
      },
      {
        key: 'explorar',
        hint: 'Tu rango en el sector aparece junto al minimapa. Sube visitando lugares, trabajando y haciendo encargos ahí.',
        goals: [
          { type: 'counter', key: 'pois_discovered', count: 12, text: 'Visita 12 lugares nuevos' },
          {
            type: 'total',
            key: 'cats_discovered',
            count: 5,
            text: 'Conoce lugares de 5 tipos distintos',
          },
          { type: 'total', key: 'sectors_visited', count: 3, text: 'Deja huella en 3 sectores' },
          { type: 'total', key: 'rank2_sectors', count: 1, text: 'Llega a Vecino en un sector' },
        ],
      },
    ],
    reward: { money: 120, xp: 200, items: { tabla: 4, clavos: 6 } },
    outro: {
      npc: 'marta',
      lines: [
        '¡Eso es caminar! Ya conoce más que el del taxi.',
        'Le dejo unas tablas y unos clavos. No son para mí: son para que el Flaco Wilmer le enseñe a usarlos.',
        'Wilmer anda por las ferreterías y los almacenes. Es flaco, habla mucho y arma lo que sea.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'manos',
    title: 'Manos a la obra',
    summary: 'El Flaco Wilmer te enseña a construir.',
    npc: 'wilmer',
    steps: [
      {
        key: 'hablar',
        hint: 'Wilmer está en tiendas, ferreterías y almacenes.',
        goals: [
          {
            type: 'talk',
            npc: 'wilmer',
            cats: ['shop', 'service', 'other'],
            text: 'Habla con el Flaco Wilmer',
            lines: [
              '¡Parcero! ¿Usted es el de la matera? Linda, linda. Torcida, pero linda.',
              'Yo le armo desde una banca hasta un puesto de empanadas. Y hoy le enseño, porque ando de buen genio.',
              'Lo primero es una mesa de trabajo: tablas, clavos, un par de palos y el martillo de Don Chepe.',
              'Con la mesa puesta en el mapa se hacen los muebles grandes. Y una parrilla nunca sobra: la comida asada vale el doble.',
            ],
          },
        ],
      },
      {
        key: 'construir',
        hint: 'Las recetas que piden mesa o parrilla se hacen estando cerca de una, tuya o de otro jugador.',
        goals: [
          { type: 'counter', key: 'crafted_mesa', count: 1, text: 'Fabrica una mesa de trabajo' },
          { type: 'counter', key: 'objects_placed', count: 3, text: 'Coloca 3 objetos en el mapa' },
          { type: 'counter', key: 'items_crafted', count: 6, text: 'Fabrica 6 cosas' },
          { type: 'counter', key: 'food_cooked', count: 2, text: 'Asa 2 comidas en una parrilla' },
        ],
      },
    ],
    reward: { money: 150, xp: 250, items: { tela: 2, pintura: 1 } },
    outro: {
      npc: 'wilmer',
      lines: [
        '¡Eso quedó de exposición! Bueno, de exposición de colegio, pero por algo se empieza.',
        'Le regalo tela y pintura. Con eso y dos palos sale una bandera.',
        '¿Para qué una bandera? Eso pregúntele a Doña Pola, la de la junta. Y vaya bien peinado.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'bandera',
    title: 'Con bandera propia',
    summary: 'Doña Pola te reta a hacerte cargo de un sector.',
    npc: 'pola',
    steps: [
      {
        key: 'hablar',
        hint: 'Doña Pola atiende a la comunidad en casi cualquier lugar del barrio.',
        goals: [
          {
            type: 'talk',
            npc: 'pola',
            cats: ANYWHERE,
            text: 'Habla con Doña Pola',
            lines: [
              '¡Por fin! Me han hablado de usted. Bien, en general.',
              'Le cuento el problema: un tal Don Gris anda comprando la ciudad cuadra por cuadra para volverla parqueaderos.',
              'Sector que no tiene quién lo quiera, sector que se queda él. Y a mí no me da la vida para cuidarlos todos.',
              'Necesito gente que se haga cargo. Hágase conocer en un sector, plante su bandera, y ese sector es suyo.',
            ],
          },
        ],
      },
      {
        key: 'dominar',
        hint: 'Para dominar un sector: llega a Conocido (150 de influencia), planta ahí tu bandera y ten más influencia que los demás con bandera.',
        goals: [
          { type: 'total', key: 'rank3_sectors', count: 1, text: 'Llega a Conocido en un sector' },
          { type: 'counter', key: 'crafted_bandera', count: 1, text: 'Fabrica una bandera' },
          { type: 'total', key: 'sectors_owned', count: 1, text: 'Domina un sector' },
        ],
      },
    ],
    reward: { money: 300, xp: 400 },
    outro: {
      npc: 'gris',
      lines: [
        'Buenas tardes. Don Gris, de Constructora Gris S.A. Un placer… para usted.',
        'Veo que plantó una banderita. Qué tierno. Yo iba a poner ahí un parqueadero de tres pisos.',
        'Disfrute su sector mientras dure. En esta ciudad todo termina siendo gris. Es cuestión de paciencia.',
        '(Doña Pola, al oído) No le haga caso. Un sector dominado le paga renta cada día: cóbrela en Menú → Territorio.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'negocio',
    title: 'El negocio',
    summary: 'Don Chepe te ayuda a montar tu propio puesto.',
    npc: 'chepe',
    steps: [
      {
        key: 'hablar',
        hint: 'Don Chepe sigue en las tiendas y lugares de comida.',
        goals: [
          {
            type: 'talk',
            npc: 'chepe',
            cats: ['shop', 'food'],
            text: 'Vuelve a hablar con Don Chepe',
            lines: [
              '¡Mírelo! Con sector propio y todo. Ya casi me alcanza. Le faltan cuarenta años.',
              'La renta ayuda, pero la plata de verdad está en vender. Monte un puesto.',
              'Lo surte con lo que quiera, le pone precio, y la gente del barrio le compra aunque usted no esté. Los otros jugadores también.',
              'Un consejo de viejo: lo asado se vende mejor que lo crudo, y en un sector donde lo conocen, se vende más rápido.',
            ],
          },
        ],
      },
      {
        key: 'vender',
        hint: 'El puesto se fabrica en una mesa de trabajo (nivel 5). Si pones precios muy altos, nadie compra.',
        goals: [
          { type: 'counter', key: 'placed_puesto', count: 1, text: 'Coloca un puesto de venta' },
          { type: 'counter', key: 'stall_income', count: 400, text: 'Gana $400 con tu puesto' },
          { type: 'stat', key: 'level', count: 6, text: 'Llega al nivel 6' },
        ],
      },
    ],
    reward: { money: 400, xp: 500, items: { carbon: 4, masa: 6 } },
    outro: {
      npc: 'chepe',
      lines: [
        '¡Cuatrocientos pesos sin estar parado ahí! Eso, mijo, se llama progreso.',
        'Le dejo masa y carbón, para que no se le acabe el surtido.',
        'Ahora piense en grande. Un sector es un buen comienzo; una red de sectores es un imperio. Hable con la Profe.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'red',
    title: 'La red',
    summary: 'Extiende tu influencia por la ciudad.',
    npc: 'marta',
    steps: [
      {
        key: 'hablar',
        hint: 'La Profe Marta está en bibliotecas, colegios, museos y sitios así.',
        goals: [
          {
            type: 'talk',
            npc: 'marta',
            cats: ['education', 'culture', 'service', 'other'],
            text: 'Habla con la Profe Marta',
            lines: [
              'Estuve pintando su sector en el mapa. Se ve muy solo, pobrecito.',
              'Don Gris ya tiene el ojo puesto en los de al lado. Hay que ganarle de mano.',
              'Mi consejo: no se riegue. Escoja sectores vecinos, donde haya buenas tiendas y por donde pase seguido.',
              'La influencia se va apagando si uno no vuelve. Un imperio que no se camina, se pierde.',
            ],
          },
        ],
      },
      {
        key: 'expandir',
        hint: 'Mira el mapa de sectores en Menú → Territorio. Los objetos que pones y la gente que los usa también suman.',
        goals: [
          { type: 'total', key: 'sectors_owned', count: 3, text: 'Domina 3 sectores' },
          { type: 'total', key: 'rank2_sectors', count: 6, text: 'Sé Vecino en 6 sectores' },
          { type: 'total', key: 'pois_discovered', count: 40, text: 'Conoce 40 lugares en total' },
        ],
      },
    ],
    reward: { money: 600, xp: 800 },
    outro: {
      npc: 'marta',
      lines: [
        'Tres sectores. Ya tuve que comprar otro color para pintarlos.',
        'Tome, se lo ganó. Pero no se confíe.',
        'Me cuentan que Don Gris está furioso. Y cuando ese señor se pone furioso… manda cartas.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'plan_gris',
    title: 'El plan gris',
    summary: 'Don Gris contraataca. El barrio necesita verse vivo.',
    npc: 'pola',
    steps: [
      {
        key: 'hablar',
        hint: 'Doña Pola atiende en casi cualquier lugar del barrio.',
        goals: [
          {
            type: 'talk',
            npc: 'pola',
            cats: ANYWHERE,
            text: 'Habla con Doña Pola',
            lines: [
              '¡Llegó la carta! Lea, lea: «Los sectores sin actividad comprobada pasarán a Constructora Gris S.A.».',
              'Ese señor quiere demostrar que aquí no pasa nada. ¡Que el barrio está muerto!',
              'Pues le vamos a mostrar lo contrario. Encargos por todas partes, materas regadas, negocios abiertos.',
              'La abuela Tulia y Yeison ya están avisados. Usted ponga el ejemplo, que para eso tiene bandera.',
            ],
          },
        ],
      },
      {
        key: 'defender',
        hint: 'Las materas se riegan una vez al día cada una; también cuentan las de otros jugadores.',
        goals: [
          { type: 'counter', key: 'jobs_completed', count: 12, text: 'Completa 12 encargos' },
          { type: 'counter', key: 'waterings', count: 8, text: 'Riega materas 8 veces' },
          { type: 'counter', key: 'stall_income', count: 600, text: 'Gana $600 con tus puestos' },
          { type: 'total', key: 'sectors_owned', count: 4, text: 'Domina 4 sectores' },
        ],
      },
    ],
    reward: { money: 900, xp: 1200, items: { farol: 2 } },
    outro: {
      npc: 'gris',
      lines: [
        '… Está bien. Reconozco que hay cierta… actividad.',
        'Mis abogados dicen que así no puedo comprar. Mis abogados son muy aburridos.',
        'Pero una ciudad es grande, y usted es uno solo. Nos veremos cuando sea leyenda. O sea, nunca.',
      ],
    },
  },

  // ---------------------------------------------------------------------------
  {
    key: 'leyenda',
    title: 'Leyenda del barrio',
    summary: 'Conviértete en alguien que la ciudad no olvide.',
    npc: 'pola',
    steps: [
      {
        key: 'hablar',
        hint: 'Doña Pola atiende en casi cualquier lugar del barrio.',
        goals: [
          {
            type: 'talk',
            npc: 'pola',
            cats: ANYWHERE,
            text: 'Habla con Doña Pola',
            lines: [
              '¿Oyó lo que dijo ese señor? «Cuando sea leyenda». ¡Pues eso es lo que va a ser!',
              'La junta quiere hacerle una fiesta. Pero una fiesta de verdad se la gana uno.',
              'Media docena de sectores, que lo respeten de verdad en un par, y que no haya vecino que no sepa su nombre.',
              'Vaya, que yo voy encargando la torta.',
            ],
          },
        ],
      },
      {
        key: 'leyenda',
        hint: 'Es el objetivo más largo del juego: reparte bien tu tiempo entre sectores y no dejes apagar los que ya tienes.',
        goals: [
          { type: 'total', key: 'sectors_owned', count: 6, text: 'Domina 6 sectores' },
          { type: 'total', key: 'rank4_sectors', count: 2, text: 'Sé Referente en 2 sectores' },
          { type: 'stat', key: 'level', count: 12, text: 'Llega al nivel 12' },
          { type: 'total', key: 'achievements', count: 40, text: 'Consigue 40 logros' },
        ],
      },
    ],
    reward: { money: 2500, xp: 3000, items: { fiesta: 1 } },
    outro: {
      npc: 'pola',
      lines: [
        '¡Vecinos, silencio! Bueno, no tanto silencio, que es una fiesta.',
        'Hace un tiempo llegó aquí alguien con cien pesos y cara de perdido. Hoy media ciudad lleva su bandera.',
        'Aquí tiene: la mesa de la fiesta. Póngala donde quiera, que el barrio entero está invitado.',
        '(Don Gris, desde lejos) … ¿Queda torta?',
      ],
    },
  },
]

export const STORY_BY_KEY = new Map(
  STORY.map((chapter, index) => [chapter.key, { chapter, index }])
)
