# Mecánicas del juego

Historia, economía, fabricación, territorio y logros de UrbanCraft. Todo el contenido (objetos, recetas, lugares, historia, logros) vive en catálogos del backend: agregar contenido casi nunca pide tocar código ni migraciones.

- Backend: `apps/backend/app/game/` (servicio, catálogos) y `app/controllers/game_controller.ts`.
- Cliente: autoload `Game` (`apps/game/scripts/autoload/game.gd`), ventanas en `scenes/ui/game/`, secciones del menú en `scenes/ui/menu/`.
- Pruebas: `apps/backend/tests/functional/game.spec.ts`.

## La idea central: el mapa es el mundo real

Cada jugador juega en su propia ciudad, así que **nada está atado a un lugar concreto**:

- Cada lugar del mapa (los puntos de interés de OpenStreetMap) toma un **perfil** según su etiqueta OSM o su categoría: panadería, café, restaurante, tienda, ferretería, banco, biblioteca… (`catalog/places.ts`). El perfil dice quién atiende, qué vende, qué compra caro, qué trabajo da y qué servicios ofrece.
- Los personajes de la historia aparecen en **cualquier** lugar de las categorías que pide el paso. Si en la zona no hay ninguno, atienden por teléfono (Menú → Misiones).
- Los encargos se arman con los lugares reales que hay cerca del jugador.

El servidor es la única fuente de verdad. Cada acción se valida contra el mapa generado (`WorldIndex`: ¿existe ese lugar?, ¿eso es un árbol?, ¿ahí se puede construir?) y contra la posición del jugador en el servidor en tiempo real (hay que estar a ≤ 7 celdas).

## Bucle básico

| Acción | Dónde | Qué da |
| ------ | ----- | ------ |
| Visitar un lugar nuevo | Interactuar junto a un pin | Experiencia e influencia en el sector |
| Rebuscar | Interactuar cerca (hasta unas 2 celdas, no hace falta estar justo enfrente) de árboles, arbustos, rocas, bancas, postes, paraderos, fuentes. Sobre el objeto sale el resultado: «¡Encontraste algo!», «No salió nada» o cuánto falta | Materiales y a veces monedas. Cada celda se recupera (20–120 min) |
| Comprar y vender | En cada lugar | Cada lugar ofrece parte del surtido de su perfil, con precio propio (hash de su id). Vender paga más donde lo necesitan |
| Trabajar un turno | Pestaña Trabajo | Dinero al momento; da hambre. Espera de 10 min por lugar |
| Servicios | Bibliotecas, cultura, deporte | Experiencia a cambio de dinero o hambre |
| Encargos | Pestaña Encargos o Menú → Misiones | Domicilios, mandados y vueltas: dinero, experiencia e influencia |
| Comer | Morral → Comer | Sube el hambre. En cero no se puede correr y el trabajo rinde la mitad |
| Fabricar | Morral → Fabricar | A mano, o junto a una mesa de trabajo o una parrilla (propia o de otro) |

Cada día de juego hay un premio de entrada, mayor con la racha de días seguidos.

## Objetos en el mapa

Lo que un jugador coloca lo ven y lo usan los demás (`world_objects.ts`):

| Objeto | Qué hace |
| ------ | -------- |
| Matera | Cualquiera la riega una vez al día; con dos riegos florece y da flores. Regarla da influencia al dueño |
| Puesto de venta | El dueño surte y pone precios. Compran otros jugadores y, con el tiempo, clientes del barrio (se simula al abrirlo: cada 8 min puede venderse una unidad, más fácil cuanto más barato) |
| Caja de trueque | Cualquiera deja y cualquiera se lleva (3 al día por caja) |
| Letrero | Frases predefinidas (sin texto libre: no hay que moderar) |
| Mesa de trabajo, parrilla | Estaciones de fabricación para todos. Usarlas da influencia al dueño |
| Bandera | Necesaria para dominar un sector (una por jugador y sector). Multiplica ×1,25 la influencia que se gana ahí |
| Banca, farol, mesa de fiesta | Decoración (el farol se enciende de noche) |
| Decoración de lujo | Solo se compra y cuesta una fortuna (metas de ahorro). Da más influencia en el sector que un objeto normal. Ferretería: cerca ($800), muro ($1.200), farola ($2.000), columna ($2.200), reloj ($4.500), molino ($7.500). Almacén: seto ($900), palma ($1.500), arco de flores ($2.800), fuente ($3.500), estandarte ($5.000, muestra el nombre del dueño). Cultura: estatua ($6.000), kiosco ($9.500), obelisco ($15.000). Banco: árbol dorado ($12.000), trono dorado ($25.000). Precios base: cada lugar los varía y no todos tienen todo |

Reglas para que el mapa no se llene de basura:

- Solo en andenes y zonas verdes libres: no en calles, vías ni ciclorrutas, ni encima de props, lugares u otros objetos.
- A 3 celdas o más de templos, centros de salud y de educación.
- Tope por jugador (8 + 2 por nivel, máximo 40) y por chunk (30).
- No bloquean el paso: nadie puede encerrar a otro.
- Un objeto que su dueño no toca en 21 días desaparece.
- Colocar da 4 de influencia y recoger la quita (no se puede ordeñar).

Los cambios se difunden por WebSocket (`{ t: 'obj' }`) a los jugadores a 3 chunks.

## Territorio

La ciudad se divide en **sectores** de 2×2 chunks (unos 300 m). Casi todo lo que se hace en un sector da **influencia** ahí.

- **Rangos:** Desconocido 0 · Visitante 20 · Vecino 60 · Conocido 150 · Referente 400 · Leyenda 1000. Desde Vecino hay descuento en las tiendas del sector (5 % a 15 %).
- **Dominio:** un sector es del jugador con bandera plantada, al menos 150 de influencia y más influencia que los demás con bandera. Cuando cambia de manos, los dos se enteran.
- **Renta:** $30 al día por sector dominado, más $4 por cada objeto propio en él (hasta 8). Se acumula 3 días; se cobra en Menú → Territorio.
- **Desgaste:** la influencia de un sector se reduce a la mitad cada 30 días sin actividad ahí. Un territorio que no se camina se pierde.

Esto es lo que obliga a planear: qué sectores conviene tener (vecinos, con buenas tiendas, por donde uno pasa), dónde poner puestos y cómo repartir el tiempo para no dejar apagar los que ya se tienen.

## Historia: «Dueños del barrio»

Nueve capítulos (`catalog/story.ts`). Cada uno tiene pasos en orden y cada paso metas en paralelo: contadores, totales, dinero, nivel, tener objetos o hablar con alguien.

1. **Recién desempacado** (tutorial, La Mona): caminar, visitar un lugar, comer, rebuscar, fabricar una matera, colocarla, un encargo, una compra.
2. **El rebusque** (Don Chepe): encargos, turnos y $300.
3. **Conociendo el vecindario** (la Profe Marta): 12 lugares, 5 tipos, 3 sectores, Vecino en uno.
4. **Manos a la obra** (el Flaco Wilmer): mesa de trabajo, fabricar, colocar y asar.
5. **Con bandera propia** (Doña Pola): dominar el primer sector. Aparece Don Gris.
6. **El negocio** (Don Chepe): un puesto y $400 de ventas.
7. **La red** (la Profe Marta): 3 sectores, Vecino en 6, 40 lugares.
8. **El plan gris** (Doña Pola): encargos, materas, ventas y 4 sectores.
9. **Leyenda del barrio**: 6 sectores, Referente en 2, nivel 12 y 40 logros.

El progreso se revisa al final de cada acción (`Progress.finish`). Los diálogos llegan como eventos y el cliente los muestra.

## Logros

120 logros en 36 familias (`catalog/achievements.ts`), con niveles bronce, plata, oro y diamante. Cada familia mira un contador del jugador (`player_counters`): metros caminados, lugares por tipo, encargos, dinero ganado, cosas fabricadas, riegos, ventas, sectores, racha, chat, saludos, acciones de noche o al amanecer… Dan experiencia y dinero.

Los metros, los saludos y los mensajes de chat los cuenta el servidor en tiempo real (`GameRealtimeServer` → `GameService.track`).

## Cómo agregar contenido

- **Objeto:** una entrada en `catalog/items.ts` y su icono `assets/art/items/<key>.png`.
- **Receta:** una entrada en `catalog/recipes.ts`.
- **Tipo de lugar:** un perfil en `catalog/places.ts` y, si aplica, su etiqueta en `KIND_PROFILE`.
- **Logro:** una familia en `catalog/achievements.ts`; si el contador es nuevo, sumarlo donde ocurra la acción con `store.count(ctx, 'clave')`.
- **Capítulo:** una entrada en `STORY` (`catalog/story.ts`).
- **Números** (pagos, esperas, rangos, límites): `catalog/rules.ts`.
- **Objeto del mapa con comportamiento:** su acción en `WorldObjects.act`, su detalle en `#detail`, su ventana en `scenes/ui/game/object_panel.gd` y su sprite en `assets/art/objects/`.

## API

Todo bajo `/api/v1/game`, con sesión. Las acciones responden con su resultado más el jugador al día: `{ …, stats, inventory, story, events }`. Los errores de juego son 4xx con `{ error, message }` y el mensaje va listo para mostrar.

| Ruta | Qué hace |
| ---- | -------- |
| `GET catalog` | Objetos, recetas, logros, personajes, rangos |
| `GET state` | Estado completo al entrar (y premio del día) |
| `POST places/visit · buy · sell · work · service` | Lugares (`poi: { id, cx, cy }`) |
| `POST gather` · `items/use` · `craft` | Rebusque, comer, fabricar |
| `GET jobs` · `POST jobs/refresh` · `jobs/:id/accept · abandon · step` | Encargos |
| `POST story/talk` · `story/seen` | Historia |
| `GET territory` · `POST territory/collect` | Sectores y renta |
| `GET objects` · `POST objects` · `objects/:id/act` | Objetos del mapa |
| `POST dev` | Solo desarrollo: `give`, `influence`, `skip`, `reset` |

En desarrollo, Menú → Depuración tiene botones para dar objetos, influencia, saltar pasos de la historia y empezar de cero. El teletransporte libre también quedó solo ahí; en el juego normal solo se puede ir a donde está un amigo.

## Pendiente conocido

- El servidor todavía acepta que un cliente modificado aparezca en cualquier punto (la ubicación inicial la informa el cliente). Con territorio y economía en juego, conviene limitarlo: aceptar saltos solo hacia un amigo o de vuelta a la zona propia.
- En zonas sin ningún lugar en el mapa (campo abierto) solo se puede rebuscar y fabricar: la historia necesita al menos un lugar cerca para los pasos de visitar, comprar y hacer encargos.
