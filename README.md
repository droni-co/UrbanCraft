# UrbanCraft

Juego multijugador de mundo abierto urbano (acción estilo GTA) con exploración basada en ubicación real (estilo Pokémon Go).

## Estructura del monorepo

```
UrbanCraft/
├── apps/
│   ├── game/       # Cliente del juego — Godot 4.7 (GDScript)
│   └── backend/    # API — AdonisJS 7 (Node 24, TypeScript)
├── packages/       # Paquetes compartidos (futuro)
├── docs/           # Documentación de arquitectura
├── docker-compose.yml  # PostgreSQL + PostGIS y Redis para desarrollo
└── pnpm-workspace.yaml
```

## Requisitos

- Node.js 24 (`nvm use`)
- pnpm 12 (`npm i -g pnpm`)
- Docker + Docker Compose
- Godot 4.7 (`sudo pacman -S godot` en Arch/CachyOS)

## Primeros pasos

```bash
pnpm install          # dependencias de todo el monorepo
pnpm db:up            # levanta Postgres/PostGIS + Redis
pnpm db:migrate       # migraciones del backend
pnpm dev              # backend en http://localhost:3333 (HMR)
pnpm game:editor      # abre el proyecto en el editor de Godot
pnpm game             # ejecuta el juego
```

El backend usa `apps/backend/.env` (copiar de `.env.example` y generar llave con `node ace generate:key`).

El cliente lee la URL del backend del ajuste `urbancraft/network/api_base_url` en `apps/game/project.godot`.

## Backend (apps/backend)

| Método | Ruta                      | Descripción                 |
| ------ | ------------------------- | --------------------------- |
| GET    | `/health`                 | Estado del API y de la BD   |
| POST   | `/api/v1/auth/signup`     | Registro (devuelve token)   |
| POST   | `/api/v1/auth/login`      | Login (devuelve token)      |
| POST   | `/api/v1/auth/google/start` · `/poll` | Login con Google desde el juego ([docs](docs/login-google.md)) |
| POST   | `/api/v1/auth/dev/login`  | Usuario de prueba (solo desarrollo y en local) |
| GET    | `/auth/google/redirect` · `/callback` | Login con Google (lo abre el navegador) |
| GET    | `/api/v1/account/profile` | Perfil (Bearer token)       |
| PATCH  | `/api/v1/account/profile` | Cambiar el apodo y/o el personaje (`{ nickname?, skin? }`) |
| GET    | `/api/v1/player/stats`    | Stats del jugador (hambre, xp/nivel, dinero…) |
| POST   | `/api/v1/player/heartbeat` | Latido cada ~60 s jugando: aplica el desgaste (hambre) |
| POST   | `/api/v1/player/stats/dev` | Solo desarrollo y en local: `{ key, delta \| value }` |
| POST   | `/api/v1/account/logout`  | Revoca el token             |
| GET    | `/api/v1/map/config`      | Grilla, versión y catálogo de tiles del mapa |
| GET    | `/api/v1/map/chunks/:z/:x/:y` | Chunk del mapa real (200 listo · 202 generando) |
| GET    | `/api/v1/geo/place?lat=&lon=` | Ciudad y país de la zona (Nominatim, cacheado por zona) |
| GET    | `/api/v1/geo/ip`          | Ubicación aproximada por IP (respaldo sin GPS) |
| WS     | `/ws`                     | Multijugador en tiempo real ([docs](docs/multijugador.md)) |

Mapa del mundo real (OpenStreetMap, chunks, caché y escalado): ver [docs/mapa-mundo-real.md](docs/mapa-mundo-real.md).

**Despliegue en producción** (Docker + nginx-proxy + acme-companion): ver [docs/despliegue.md](docs/despliegue.md).

**Login con Google:** pon `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` en `apps/backend/.env` (cómo obtenerlos: [docs/login-google.md](docs/login-google.md)). Hace falta iniciar sesión para jugar. Para depurar sin Google hay **usuarios de prueba** (`DEV_LOGIN_ENABLED=true`, solo en local): botón en la pantalla inicial o `godot --path apps/game -- --dev-login=ana`.

Comandos útiles: `pnpm map:pregenerate --lat=40.42 --lon=-3.6887 --radius=2000 --wait`, `pnpm --filter @urbancraft/backend exec node ace make:model Creature -m`, `node ace list`.

## Juego (apps/game)

Juego **2D isométrico** (tiles 64×32, estilo pixel art) pensado para jugarse igual de cómodo en PC y móvil.

### Controles

| Acción      | PC                         | Gamepad        | Móvil                       |
| ----------- | -------------------------- | -------------- | --------------------------- |
| Moverse     | WASD / flechas · clic      | Stick / D-pad  | Joystick dinámico · tocar   |
| Correr      | Shift                      | B              | Botón B (alterna)           |
| Interactuar | E / Espacio                | A              | Botón A                     |
| Saludar     | G · menú → Multijugador    | Y              | Menú → Multijugador         |
| Zoom        | Rueda · `+` / `-`          | LB / RB        | Pellizco                    |
| Menú        | Esc / P · botón ☰          | Start          | Botón ☰                     |

Para probar los controles táctiles en PC (el ratón simula toques): `pnpm game:touch`.

El mapa es el **mundo real** (OpenStreetMap) alrededor de tu ubicación, cargado por chunks desde el backend. Por defecto se usa el Retiro de Madrid; para otro lugar: `godot --path apps/game -- --lat=4.6097 --lon=-74.0817`. Sin servidor (o con `-- --demo`) se usa un mapa procedural.

### Ubicación del jugador

Al arrancar, `LocationService` busca tu posición en este orden:

1. Argumentos `--lat/--lon` (para probar una ubicación concreta).
2. GPS del navegador (export web; el navegador pide permiso).
3. GPS nativo de Android/iOS (pendiente: requiere un plugin).
4. IP pública, consultada por el backend. **Es aproximada (nivel ciudad, puede fallar por varios km)**: es lo que se usa en PC, que no tiene GPS.
5. Última ubicación conocida (`user://location.cfg`).
6. Ubicación por defecto de los ajustes del proyecto (Madrid).

La barra superior muestra la ciudad y el país de la zona (por ejemplo "Madrid, España"), y el mensaje de bienvenida dice de dónde salió la ubicación. La información de depuración (chunk y FPS) solo aparece si `GameSettings.debug_info_visible` está activo (por defecto, en builds de depuración).

```bash
godot --path apps/game -- --lat=4.6097 --lon=-74.0817   # forzar una ubicación
```

### Menú del jugador

El botón **☰** (arriba a la derecha, junto al minimapa) o **Esc** abre el menú: un modal que pausa el juego. Tiene una lista de secciones a la izquierda (arriba en pantallas angostas) y el contenido a la derecha. Se cierra con la X, con Esc o tocando fuera del panel.

Secciones: **Teletransporte**, **Personaje** (elegir la skin: vista previa caminando y girando; se guarda en la cuenta y los demás la ven al momento; para agregar personajes ver [assets/art/README.md](apps/game/assets/art/README.md#personajes-characterspng)), **Multijugador** (estado, modo fantasma, saludar; ver [docs/multijugador.md](docs/multijugador.md)) y **Cuenta** (iniciar sesión con Google, cambiar el apodo, cerrar sesión; la pantalla inicial muestra una versión compacta). Ver [docs/login-google.md](docs/login-google.md).

**Teletransporte**:
- Escribe la latitud y la longitud, o pega el par en cualquiera de los dos campos (`4.6097, -74.0817`, como lo copia Google Maps). Acepta decimales con punto o con coma (`4,6097`).
- **Teletransportarse** mueve el ancla de tu zona a esas coordenadas y recarga el mundo allí: chunks, minimapa, etiquetas y ciudad.
- **Usar posición actual** rellena los campos con donde estás parado.
- **Volver a mi ubicación real** aparece solo mientras estás teletransportado.
- El teletransporte no se guarda: al reiniciar el juego vuelves a tu ubicación real.
- Si nadie ha visitado la zona, generarla puede tardar hasta un minuto (Overpass).

Para agregar una opción nueva, crea un `Control` con su contenido y regístralo en `Hud._build_menu()` con `menu.add_section("Título", control)`. El estilo de todo el menú está en `scenes/ui/menu/menu_theme.gd`.

### Stats del jugador

Bajo el botón ☰ hay un panel compacto con los stats principales:

| Stat | Cómo se ve | Reglas (por defecto) |
| ---- | ---------- | -------------------- |
| Hambre | Barra; roja y parpadeando por debajo del 20 % | Empieza en 100. Baja 0,5 por minuto **jugando**; el tiempo desconectado no cuenta |
| Experiencia | `Nv 3` y una barra fina de progreso | Pasar del nivel N al N+1 cuesta `100 · N^1.5` xp (100, 283, 520…). Al subir de nivel sale un aviso |
| Dinero | Número (`1.250`) que cuenta al cambiar | Empieza en 100 monedas |

Al pasar el ratón por encima se ve el detalle (`Hambre 87/100`, `Nivel 3 (50/520 xp)`…). Los cambios muestran un `+50` flotante. Se puede ocultar con `GameSettings.stats_hud_visible`.

- **El servidor es la fuente de verdad:** el cliente solo lee los stats. Los cambios llegan por acciones del servidor (comer, misiones…), así nadie puede ponerse dinero desde el juego.
- **Agregar un stat** es una entrada en `apps/backend/config/player_stats.ts` (tipo `meter`, `level` o `counter`, límites, valor inicial, desgaste, orden, icono y color), sin migraciones. El panel lo dibuja solo. Para su icono, crea `apps/game/assets/art/ui/icons/<icon>.png` (12×12).
- **Depuración:** en builds de depuración, con `DEV_LOGIN_ENABLED`, el menú tiene una sección **Depuración** para sumar y restar stats.

### Multijugador

Ves a los demás jugadores que están en tu pantalla (sprite, apodo, nivel, si caminan o corren, y sus saludos) y, en el minimapa, puntos amarillos con los que están a menos de 1 km (los lejanos con posición aproximada, por privacidad). Funciona por WebSocket con el mismo backend. Arriba a la izquierda se ve cuántos hay cerca. En **Menú → Multijugador** puedes ponerte en modo fantasma. Detalles, protocolo y privacidad: [docs/multijugador.md](docs/multijugador.md).

### Minimapa y brújula

Minimapa isométrico (misma orientación que la cámara) arriba a la izquierda. Sigue al jugador y muestra unos 400 m a su alrededor, con los puntos de interés, tu posición y el borde de tu zona de juego (5 km) cuando te acercas a él. La brújula discreta indica el norte, que en esta vista queda arriba a la derecha.

Las preferencias viven en `GameSettings` y se aplican en vivo (pensadas para una futura pantalla de opciones):

| Variable                | Por defecto   | Descripción                                          |
| ----------------------- | ------------- | ---------------------------------------------------- |
| `minimap_visible`       | `true`        | Mostrar u ocultar el minimapa                        |
| `minimap_corner`        | `TOP_LEFT`    | `ScreenCorner.TOP_LEFT/TOP_RIGHT/BOTTOM_LEFT/BOTTOM_RIGHT` |
| `minimap_size`          | `128×80`      | Tamaño en píxeles de la resolución base (640×360)    |
| `minimap_margin`        | `(8, 24)`     | Margen lateral y vertical (deja libre la barra superior) |
| `minimap_zoom`          | `1.0`         | 1 = toda la zona; mayor = más cerca                  |
| `minimap_view_radius_meters` | `400` | Metros visibles con zoom 1 (y área que se mantiene cargada) |
| `minimap_follow_player` | `true`        | Siguiendo al jugador o centrado en tu ubicación real |
| `compass_visible`       | `true`        | Mostrar u ocultar la brújula                         |

### Pantalla de carga

Mientras se conecta, ubica al jugador y carga el mapa, una barra muestra el progreso. Si la zona es nueva (el servidor la descarga de OpenStreetMap, 30–60 s), dice en qué va ("En cola", "Descargando…", "Faltan unos 20 s"), usando lo que responde el servidor. Al terminar se cierra sola. Código en `apps/game/scenes/ui/loading/loading_screen.gd`.

### Etiquetas del mapa

Nombres discretos para orientarse, sacados de las etiquetas `name` y `addr:housenumber` de OpenStreetMap:

- **Calles y ríos**: pintados sobre el asfalto en perspectiva, siguiendo la dirección de la calle. El nombre se repite a lo largo de cada tramo recto y no se pone en rotondas ni en curvas cerradas.
- **Parques, plazas, edificios con nombre y puntos de interés**: texto pequeño sobre el lugar, solo cerca del jugador.
- **Números de portal**: solo en las casas de alrededor (unas 7 celdas).
- **Dónde estás**: debajo del minimapa aparece la calle que pisas, el lugar en el que estás o "Cerca de …".
- **Barrio**: arriba, junto a la ciudad ("Chicó Lago, Bogotá"), y como un nombre grande sobre el mapa en el punto del barrio.
- **Lugares (POIs)**: un pin con el color y el icono de su categoría (comida, tiendas, salud, educación…). Al interactuar se ve el tipo en español y la cocina, por ejemplo "Osaki · Restaurante · japonesa".

El mapa también reproduce el entorno real: edificios en 3D isométrico con sus pisos (de 1 a 6) y su fachada según el tipo (casas, ladrillo, concreto, vidrio, edificios públicos, bodegas), que se vuelven transparentes si tapan al jugador, andenes, pasos de cebra, vías férreas, ciclorrutas, bancas, postes de luz, semáforos, paraderos, fuentes y estatuas, todo según lo que haya en OpenStreetMap. Detalles en [docs/mapa-mundo-real.md](docs/mapa-mundo-real.md).

Todas se desvanecen con la distancia y evitan pisarse entre sí y tapar al jugador. Preferencias en `GameSettings` (señal `labels_settings_changed`):

| Variable                 | Por defecto | Descripción                                     |
| ------------------------ | ----------- | ----------------------------------------------- |
| `street_names_visible`   | `true`      | Nombres de calles y ríos sobre el suelo         |
| `place_names_visible`    | `true`      | Parques, plazas, edificios y puntos de interés  |
| `house_numbers_visible`  | `true`      | Números de portal cercanos                      |
| `current_street_visible` | `true`      | Calle o lugar actual junto al minimapa          |
| `labels_opacity`         | `1.0`       | Opacidad general de las etiquetas (0–1)         |

### Estructura

```
apps/game/
├── scenes/
│   ├── main/        # Pantalla inicial (estado del servidor + Jugar)
│   ├── world/       # Mundo: TileMapLayers, cámara, cursor de celda
│   ├── player/      # Jugador y RemotePlayer (otros jugadores)
│   └── ui/          # HUD, botones táctiles, minimapa; menu/ = menú del jugador
├── scripts/
│   ├── autoload/    # Api, Auth (sesión/Google), PlayerStats, Online (multijugador), GameSettings, LocationService
│   ├── map/         # Geo (lat/lon <-> celdas), ChunkManager (streaming)
│   └── world/       # WorldTiles (catálogo), WorldGenerator, IsoPathfinder
├── resources/tilesets/world_tileset.tres   # generado
├── assets/tiles/    # ground.png, props.png (placeholders generados)
└── tools/           # scripts de generación (input map, arte, tileset)
```

### Cómo está armado

- **Mapa**: `Ground` (suelo) + `Entities/Props` (árboles, rocas) como `TileMapLayer` isométricos *diamond-down*. `Entities` tiene Y-sort, así el jugador queda delante/detrás de los props correctamente.
- **Tiles**: el TileSet tiene un custom data `walkable` y una capa física `world`. El agua y los props bloquean el paso y `IsoPathfinder` (A*) usa esos datos para el movimiento por toque/clic.
- **Mapa real**: `ChunkManager` descarga chunks de 64×64 celdas alrededor del jugador, los cachea en disco y descarga los lejanos. Detalles en [docs/mapa-mundo-real.md](docs/mapa-mundo-real.md).
- **Modo demo**: sin servidor, `WorldGenerator` genera un mapa procedural local.
- **Input unificado**: el joystick virtual nativo (`VirtualJoystick`) y los botones táctiles presionan las mismas acciones del InputMap que el teclado y el gamepad. El jugador solo lee `Input.get_vector(...)`.
- **Pantallas**: resolución base de 640×360 que escala a cualquier pantalla (`canvas_items` + `expand`), filtro *nearest* y renderer *Compatibility* para máxima compatibilidad móvil y web.

### Arte (tiles y sprites)

El arte editable vive en `apps/game/assets/art/`: un PNG por tile, variante y personaje. Las especificaciones están en [`assets/art/README.md`](apps/game/assets/art/README.md): tamaños, punto de anclaje, nombres `<tipo>_<n>@peso.png` y hoja del jugador de 8 direcciones.

- `pnpm game:assets`: crea lo que falte con el arte inicial (sin tocar tus archivos), arma los atlas de `assets/tiles/` y reconstruye el TileSet. Ejecútalo después de editar.
- `pnpm game:art:reset`: vuelve a generar todo el arte inicial. **Borra tus cambios.**
- Cada celda elige una variante con un hash de su posición global, así la ciudad no se ve repetida y todos ven lo mismo.

`pnpm game:input` reescribe el InputMap desde `tools/setup_input_map.gd`.
