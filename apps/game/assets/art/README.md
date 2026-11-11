# Arte del juego (editable)

Esta carpeta contiene el arte **fuente** de UrbanCraft: un PNG por tile, variante y personaje. Puedes editarlos con cualquier editor de pixel art (Aseprite, LibreSprite, Pixelorama, Krita, GIMP…) o reemplazarlos por los tuyos.

Después de editar, regenera los atlas y el TileSet:

```bash
pnpm game:assets
```

Ese comando:

1. Crea los archivos que falten con el arte inicial. **Nunca sobrescribe los tuyos.**
2. Empaqueta todo en `assets/tiles/ground.png` y `assets/tiles/props.png`, y escribe `assets/tiles/atlas.json`.
3. Reconstruye `resources/tilesets/world_tileset.tres`.

> No edites `assets/tiles/*.png` a mano: se regeneran desde aquí.

Para volver al arte inicial (borra tus cambios): `pnpm game:art:reset`.

## Estructura

```
art/
├── tiles/ground/   suelo, 64×32
├── props/          árboles, rocas, arbustos, 64×64
└── characters/     hojas de sprites de personajes
```

## Nombres y variantes

```
<tipo>_<n>[@peso].png        ej.  grass_0@6.png   asphalt_2@1.png
```

- `<tipo>` es el nombre del tipo en minúsculas. Tiene que coincidir con `WorldTiles.Ground` o `WorldTiles.Prop`, que a su vez coinciden con el catálogo del servidor:
  - Suelo: `grass`, `grass_dark`, `dirt`, `sand`, `water`, `stone`, `asphalt`, `pavement`, `building`.
  - Props: `tree`, `pine`, `rock`, `bush`.
- `<n>` es el número de variante. Se ordenan por número, y no hace falta que sean consecutivos.
- `@peso` (opcional, por defecto 1) es la frecuencia relativa. Con `asphalt_0@8`, `asphalt_1@2` y `asphalt_2@1`, la alcantarilla (2) sale en 1 de cada 11 celdas.
  - Para cambiar la frecuencia, renombra el archivo.
  - Para agregar una variante, crea `grass_4@2.png`.
  - Para quitar una, bórrala.
- Cada celda elige su variante con un hash de su posición **global**. Es estable: todos los jugadores ven el mismo tile en el mismo lugar.

Agregar un **tipo nuevo** (por ejemplo `snow`) no se hace solo con un archivo. Hay que añadirlo al final del enum en `scripts/world/world_tiles.gd` y en `apps/backend/app/map/catalog.ts`, y enseñarle al rasterizador del backend cuándo usarlo.

## Suelo: `tiles/ground/` (64×32)

- Un rombo isométrico 2:1 sobre fondo transparente. Cada fila `y` del rombo ocupa los píxeles `x` entre `32 − m` y `32 + m − 1`, con `m = 2·(y+1)` en la mitad superior y `m = 2·(32−y)` en la inferior. Lo más simple es partir de un tile existente.
- **Sin costuras:** el tile se repite en una grilla, así que lo que sale por un borde tiene que continuar en el borde opuesto.
  - Evita líneas en el contorno: dibujan la grilla.
  - Deja los detalles grandes (alcantarillas, flores) al menos 2–3 px dentro del rombo.
  - Las variantes de un mismo tipo deberían compartir la textura base y cambiar solo los detalles, para que encajen entre sí.
- `building` es el techo, visto desde arriba. Las celdas de un mismo edificio eligen variantes distintas, así que las variantes de techo deberían ser del mismo color.
- El minimapa usa un color por tipo, definido en `scenes/ui/minimap.gd` (`GROUND_COLORS`). Si cambias mucho un color, actualízalo ahí.

## Props: `props/` (64×64)

- La base del objeto (donde toca el suelo) va en el píxel **(32, 48)**: es el centro del rombo de su celda. Lo que sobresale hacia arriba tapa lo que está detrás, porque se ordena por profundidad.
- Incluye la sombra en el suelo (elipse negra semitransparente).
- Los props bloquean el paso. La colisión es un rombo pequeño en la base y no depende de la imagen.

## Personajes: `characters/player.png`

Hoja de **160×384**, con 5 columnas × 8 filas de frames de **32×48**:

| Columna | Contenido |
| ------- | --------- |
| 0 | Quieto |
| 1–4 | Ciclo de caminata (8 fps; al correr se acelera) |

| Fila | Dirección en pantalla |
| ---- | --------------------- |
| 0 | `e` → derecha |
| 1 | `se` ↘ |
| 2 | `s` ↓ (de frente a la cámara) |
| 3 | `sw` ↙ |
| 4 | `w` ← |
| 5 | `nw` ↖ |
| 6 | `n` ↑ (de espaldas) |
| 7 | `ne` ↗ |

- Los **pies** van en el píxel **(16, 44)** de cada frame: es el punto que toca el suelo.
- La sombra la dibuja el juego, así que no la incluyas.
- El jugador arma sus animaciones (`idle_<dir>`, `walk_<dir>`) desde esta hoja al iniciar, así que basta con editar el PNG. Si cambias tamaños o número de frames, ajusta las constantes de `scenes/player/player.gd`.

## Estilo

Pixel art de 16 bits:
- Luz desde arriba a la izquierda.
- Contorno de 1 px oscuro (no negro puro) en props y personajes.
- 3–4 tonos por material.
- El juego se ve a la escala de la resolución base 640×360, con filtrado *nearest*. No uses antialiasing ni bordes semitransparentes, salvo en las sombras.
