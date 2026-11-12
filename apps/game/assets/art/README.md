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
├── props/          árboles, rocas, arbustos, mobiliario urbano, 64×64
├── buildings/      fachadas de un piso para los edificios en 3D, 64×42
├── characters/     hojas de sprites de personajes
├── ui/icons/       iconos de la interfaz, 12×12 (stats del HUD; ver ui/icons/README.md)
└── ui/poi/         icono de cada categoría de lugar, 7×7 blanco (va dentro del pin)
```

## Nombres y variantes

```
<tipo>_<n>[@peso].png        ej.  grass_0@6.png   asphalt_2@1.png
```

- `<tipo>` es el nombre del tipo en minúsculas. Tiene que coincidir con `WorldTiles.Ground` o `WorldTiles.Prop`, que a su vez coinciden con el catálogo del servidor:
  - Suelo: `grass`, `grass_dark`, `dirt`, `sand`, `water`, `stone`, `asphalt`, `pavement`, `building`, `roof_brick`, `roof_concrete`, `roof_dark`, `roof_civic`, `roof_industrial`, `crosswalk`, `rail`, `cycleway`.
  - Props: `tree`, `pine`, `rock`, `bush`, `bench`, `street_lamp`, `traffic_light`, `bus_stop`, `fountain`, `statue`.
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
- `building` y `roof_*` son techos vistos desde arriba. Las celdas de un mismo edificio eligen variantes distintas, así que las variantes de un techo deberían ser del mismo color, con detalles sueltos como tanques de agua, ductos o tragaluces. Qué techo lleva cada edificio lo decide el backend (`classifyBuilding` en `rasterizer.ts`): `roof_brick` para casas, `roof_concrete` para comercio y oficinas, `roof_dark` para edificios altos, `roof_civic` para iglesias, colegios y hospitales, y `roof_industrial` para bodegas.
- `crosswalk` se pinta sobre el asfalto: las franjas tienen que seguir la dirección de la grilla.
- El minimapa usa un color por tipo, definido en `scenes/ui/minimap.gd` (`GROUND_COLORS`). Si cambias mucho un color, actualízalo ahí.

## Props: `props/` (64×64)

- La base del objeto (donde toca el suelo) va en el píxel **(32, 48)**: es el centro del rombo de su celda. Lo que sobresale hacia arriba tapa lo que está detrás, porque se ordena por profundidad.
- Incluye la sombra en el suelo (elipse negra semitransparente).
- Los props bloquean el paso. La colisión es un rombo pequeño en la base y no depende de la imagen.

## Edificios en 3D: `buildings/` (64×42)

Cada celda de edificio se dibuja como un bloque isométrico: las dos paredes del frente y el techo encima. `build_art.gd` arma los bloques apilando fachadas de un piso según la altura del edificio (1 a 6 pisos; el backend la saca de `building:levels` o `height` de OSM, o usa una típica del tipo) y les pone encima el tile de techo de su estilo (`tiles/ground/roof_*.png` o `building_*.png`).

```
<estilo>_<ground|upper>_<n>[@peso].png     ej.  roof_brick_ground_1@3.png
```

- `<estilo>`: el suelo del techo: `building` (casas), `roof_brick`, `roof_concrete`, `roof_dark` (vidrio), `roof_civic`, `roof_industrial`.
- `ground` es la planta baja (puertas, locales, portones) y `upper` un piso alto. Hace falta al menos uno de cada uno por estilo.
- Cada imagen tiene las dos paredes de un piso: la izquierda (x 0–31, iluminada) y la derecha (x 32–63, en sombra). El borde de arriba es una "V" (de (0, 0) a (32, 16) y a (64, 0)) y el de abajo la misma "V" 26 px más abajo. Fuera de esas dos franjas inclinadas, transparente. Lo más fácil es partir de una existente.
- Las ventanas siguen la inclinación de la pared (en la izquierda bajan 1 px cada 2 hacia la derecha, en la derecha suben).
- Cada celda elige una de 8 combinaciones (planta baja, pisos y variante de techo) con un hash de su posición: si un edificio se ve muy repetido, agrega variantes o cambia los pesos.
- La altura de un piso (26 px) y el máximo de pisos están en `WorldTiles` (`BUILDING_FLOOR_PX`, `BUILDING_MAX_FLOORS`). Si los cambias, cambia también el alto de las fachadas.

## Iconos de lugares: `ui/poi/<categoría>.png` (7×7)

- Blancos sobre fondo transparente; el pin les pone el color de la categoría (`scripts/map/poi_catalog.gd`).
- Categorías: `food`, `shop`, `health`, `education`, `worship`, `money`, `transport`, `culture`, `lodging`, `sport`, `service`, `other` (las calcula el backend en `app/map/poi_category.ts`).

## Personajes: `characters/*.png`

Cada PNG de `characters/` es un **personaje (skin)** que el jugador puede elegir en **Menú → Personaje**: `player01.png` … `player05.png`. Para agregar uno basta con poner otra hoja ahí: aparece sola en el selector como "Personaje N" (`player06.png`) o con su nombre (`ninja_rojo.png` → "Ninja Rojo"). `player01` es el personaje por defecto. El personaje elegido se guarda en la cuenta y los demás jugadores lo ven.

Cada hoja mide **160×384**, con 5 columnas × 8 filas de frames de **32×48**:

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
- Si las filas quedan un poco corridas (el dibujo no cae justo cada 48 px, típico de hojas generadas), el juego las **alinea al cargar**: mueve cada fila en bloque para que su píxel más bajo quede en y = 44. El PNG no se modifica.
- La sombra la dibuja el juego, así que no la incluyas.
- Las animaciones (`idle_<dir>`, `walk_<dir>`) se arman desde la hoja al iniciar (`scripts/characters/character_skins.gd`), así que basta con editar el PNG. Si cambias tamaños o número de frames, ajusta las constantes de ese archivo.

## Estilo

Pixel art de 16 bits:
- Luz desde arriba a la izquierda.
- Contorno de 1 px oscuro (no negro puro) en props y personajes.
- 3–4 tonos por material.
- El juego se ve a la escala de la resolución base 640×360, con filtrado *nearest*. No uses antialiasing ni bordes semitransparentes, salvo en las sombras.
