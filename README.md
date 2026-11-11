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

- `scenes/main/` — escena inicial (verifica conexión con el backend).
- `scripts/autoload/api_client.gd` — autoload `Api` con `health()`, `signup()`, `login()`, `logout()` y `request_json()`.
- Renderer `Mobile` (funciona en escritorio y es el adecuado para Android/iOS).
