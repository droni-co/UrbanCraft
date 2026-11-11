# UrbanCraft

Juego multijugador de mundo abierto urbano (acción estilo GTA) con exploración basada en ubicación real (estilo Pokémon Go).

## Estructura del monorepo

```
UrbanCraft/
├── apps/
│   ├── game/       # Cliente del juego — Godot 4.7 (GDScript)
│   └── backend/    # API — AdonisJS 7 (Node 24, TypeScript)
├── packages/       # Paquetes compartidos (futuro)
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

Comandos útiles: `pnpm --filter @urbancraft/backend exec node ace make:model Creature -m`, `node ace list`.

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

### Estructura

```
apps/game/
├── scenes/
│   ├── main/        # Pantalla inicial (estado del servidor + Jugar)
│   ├── world/       # Mundo: TileMapLayers, cámara, cursor de celda
│   ├── player/      # Jugador (placeholder dibujado por código)
│   └── ui/          # HUD, botones táctiles, pausa
├── scripts/
│   ├── autoload/    # Api (backend), GameSettings (plataforma / táctil)
│   └── world/       # WorldTiles (catálogo), WorldGenerator, IsoPathfinder
├── resources/tilesets/world_tileset.tres   # generado
├── assets/tiles/    # ground.png, props.png (placeholders generados)
└── tools/           # scripts de generación (input map, arte, tileset)
```

### Cómo está armado

- **Mapa**: `Ground` (suelo) + `Entities/Props` (árboles, rocas) como `TileMapLayer` isométricos *diamond-down*. `Entities` tiene Y-sort, así el jugador queda delante/detrás de los props correctamente.
- **Tiles**: el TileSet tiene un custom data `walkable` y una capa física `world`. El agua y los props bloquean el paso y `IsoPathfinder` (A*) usa esos datos para el movimiento por toque/clic.
- **Mapa procedural**: si `Ground` está vacío, `WorldGenerator` genera un mapa de prueba (semilla configurable en el nodo `World`). Si pintas el mapa en el editor, se usa el tuyo.
- **Input unificado**: el joystick virtual nativo (`VirtualJoystick`) y los botones táctiles presionan las mismas acciones del InputMap que el teclado y el gamepad. El jugador solo lee `Input.get_vector(...)`.
- **Pantallas**: resolución base de 640×360 que escala a cualquier pantalla (`canvas_items` + `expand`), filtro *nearest* y renderer *Compatibility* para máxima compatibilidad móvil y web.

### Assets placeholder

`pnpm game:assets` regenera `assets/tiles/*.png` y el TileSet. Para usar arte real, reemplaza los PNG respetando el orden de `WorldTiles.Ground` / `WorldTiles.Prop` (suelo 64×32, props 64×64 con la base del objeto en y=48) y vuelve a ejecutar solo el último paso (`generate_tileset.gd`). `pnpm game:input` reescribe el InputMap desde `tools/setup_input_map.gd`.
