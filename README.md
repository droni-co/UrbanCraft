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
| GET    | `/api/v1/account/profile` | Perfil (Bearer token)       |
| POST   | `/api/v1/account/logout`  | Revoca el token             |
| GET    | `/api/v1/map/config`      | Grilla, versión y catálogo de tiles del mapa |
| GET    | `/api/v1/map/chunks/:z/:x/:y` | Chunk del mapa real (200 listo · 202 generando) |
| GET    | `/api/v1/geo/place?lat=&lon=` | Ciudad y país de la zona (Nominatim, cacheado por zona) |
| GET    | `/api/v1/geo/ip`          | Ubicación aproximada por IP (respaldo sin GPS) |

Mapa del mundo real (OpenStreetMap, chunks, caché y escalado): ver [docs/mapa-mundo-real.md](docs/mapa-mundo-real.md).

Comandos útiles: `pnpm map:pregenerate --lat=40.42 --lon=-3.6887 --radius=2000 --wait`, `pnpm --filter @urbancraft/backend exec node ace make:model Creature -m`, `node ace list`.

## Juego (apps/game)

Juego **2D isométrico** (tiles 64×32, estilo pixel art) pensado para jugarse igual de cómodo en PC y móvil.

### Controles

| Acción      | PC                         | Gamepad        | Móvil                       |
| ----------- | -------------------------- | -------------- | --------------------------- |
| Moverse     | WASD / flechas · clic      | Stick / D-pad  | Joystick dinámico · tocar   |
| Correr      | Shift                      | B              | Botón B (alterna)           |
| Interactuar | E / Espacio                | A              | Botón A                     |
| Zoom        | Rueda · `+` / `-`          | LB / RB        | Pellizco                    |
| Pausa       | Esc / P                    | Start          | Botón II                    |

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

### Minimapa y brújula

Minimapa isométrico (misma orientación que la cámara) arriba a la izquierda. Muestra toda tu zona de juego (500 m), los puntos de interés y una flecha con tu posición. La brújula discreta indica el norte, que en esta vista queda arriba a la derecha.

Las preferencias viven en `GameSettings` y se aplican en vivo (pensadas para una futura pantalla de opciones):

| Variable                | Por defecto   | Descripción                                          |
| ----------------------- | ------------- | ---------------------------------------------------- |
| `minimap_visible`       | `true`        | Mostrar u ocultar el minimapa                        |
| `minimap_corner`        | `TOP_LEFT`    | `ScreenCorner.TOP_LEFT/TOP_RIGHT/BOTTOM_LEFT/BOTTOM_RIGHT` |
| `minimap_size`          | `128×80`      | Tamaño en píxeles de la resolución base (640×360)    |
| `minimap_margin`        | `(8, 24)`     | Margen lateral y vertical (deja libre la barra superior) |
| `minimap_zoom`          | `1.0`         | 1 = toda la zona; mayor = más cerca                  |
| `minimap_follow_player` | `false`       | Centrado en tu zona o siguiendo al jugador           |
| `compass_visible`       | `true`        | Mostrar u ocultar la brújula                         |

### Etiquetas del mapa

Nombres discretos para orientarse, sacados de las etiquetas `name` y `addr:housenumber` de OpenStreetMap:

- **Calles y ríos**: pintados sobre el asfalto en perspectiva, siguiendo la dirección de la calle. El nombre se repite a lo largo de cada tramo recto y no se pone en rotondas ni en curvas cerradas.
- **Parques, plazas, edificios con nombre y puntos de interés**: texto pequeño sobre el lugar, solo cerca del jugador.
- **Números de portal**: solo en las casas de alrededor (unas 7 celdas).
- **Dónde estás**: debajo del minimapa aparece la calle que pisas, el lugar en el que estás o "Cerca de …".

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
│   ├── player/      # Jugador (placeholder dibujado por código)
│   └── ui/          # HUD, botones táctiles, pausa
├── scripts/
│   ├── autoload/    # Api, GameSettings, LocationService (ubicación real)
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

### Assets placeholder

`pnpm game:assets` regenera `assets/tiles/*.png` y el TileSet. Para usar arte real, reemplaza los PNG respetando el orden de `WorldTiles.Ground` / `WorldTiles.Prop` (suelo 64×32, props 64×64 con la base del objeto en y=48) y vuelve a ejecutar solo el último paso (`generate_tileset.gd`). `pnpm game:input` reescribe el InputMap desde `tools/setup_input_map.gd`.
