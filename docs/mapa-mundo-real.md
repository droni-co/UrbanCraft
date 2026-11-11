# Mapa del mundo real

El mundo del juego se genera a partir de **OpenStreetMap** (OSM), se guarda una sola vez en la base de datos y se reutiliza para todos los jugadores. El cliente lo carga por **chunks** alrededor del jugador, al estilo Minecraft.

## Por qué OpenStreetMap y no Google Maps

Los términos de Google Maps Platform prohíben guardar y cachear su contenido (más allá de lo temporal) y crear mapas o datos derivados. Este sistema hace exactamente eso: guarda geometría y la convierte en tiles. Pokémon Go dejó Google Maps en 2017 por motivos parecidos.

OSM usa la licencia **ODbL**, que permite guardar y transformar los datos con estas condiciones:

- **Atribución visible**: "© OpenStreetMap contributors". Ya aparece en el HUD y viene en cada chunk.
- **Share-alike**: aplica si se distribuye públicamente una *base de datos derivada*, por ejemplo una API abierta con los datos procesados. Si en algún momento se publican los chunks como dataset, revisarlo con criterio legal.

## Grillas

Todas las grillas son tiles Web Mercator (slippy map), así que pasar de un nivel a otro es una potencia de 2 exacta.

| Nivel        | Zoom | Tamaño aprox.                       | Uso                                            |
| ------------ | ---- | ----------------------------------- | ---------------------------------------------- |
| Source tile  | z15  | ~1.2 km (930 m en Madrid)           | 1 consulta al proveedor OSM; datos crudos      |
| Chunk        | z18  | ~150 m · 64×64 celdas               | Unidad que descarga el cliente                 |
| Celda        | z24  | 2.4 m en el ecuador (1.8 m en Madrid) | Un tile isométrico                           |

Todo se configura en `apps/backend/config/map.ts`. Si cambias los zooms, sube `generatorVersion`.

En pantalla, el **norte apunta hacia arriba a la derecha**: la celda `x` crece hacia el este y `y` hacia el sur, en un layout *diamond-down*.

## Flujo

```
Cliente (Godot)                          Backend (AdonisJS)                         Proveedor
───────────────                          ──────────────────                         ─────────
GET /map/chunks/18/x/y?v=1 ───────────▶  ¿en memoria (LRU)? ¿en map_chunks?
                                          └─ sí ─▶ 200 (gzip, ETag, immutable)
                                          └─ no ─▶ encola source tile z15 ─▶ 202 Retry-After
        (reintenta tras Retry-After)
                                          MapWorker (cola en osm_source_tiles):
                                            1. Overpass (solo la 1ª vez) ─────────────▶ OSM
                                            2. guarda features normalizadas (gzip)
                                            3. rasteriza los 64 chunks de una pasada
                                            4. guarda en map_chunks (transacción)
GET … ────────────────────────────────▶  200
guarda en user://map_cache
```

Medido con datos reales del Retiro de Madrid:

- Overpass tardó **30-60 s** por source tile y a veces devolvió 502 (lo cubren los reintentos).
- El tile tenía 2,061 features, que se convirtieron en 64 chunks de **~1 KB cada uno** (gzip): 67 KB por km².
- Con el chunk ya generado, el spawn tarda 220 ms desde el servidor y 96 ms desde la caché en disco.

## Piezas

### Backend (`apps/backend`)

- `app/map/geo.ts`: proyección y jerarquía de tiles.
- `app/map/catalog.ts`: ids de tiles. **Deben coincidir con `WorldTiles.gd`**; el cliente los valida al arrancar.
- `app/map/providers/`: `OsmProvider` (interfaz), `OverpassProvider` y el parser.
- `app/map/rasterizer.ts`: reglas de estilo OSM → suelo/props/POIs. Es determinista:
  - Áreas: relleno scanline con regla par-impar. Soporta multipolígonos con huecos sin tener que ensamblar anillos.
  - Calles y ríos: buffer según su ancho real. Usa un mínimo de 0.75 celdas para que los senderos sean transitables.
  - Prioridades: los puentes van sobre el agua y los túneles se omiten.
  - Edificios más chicos que una celda ocupan igual 1 celda.
  - Decoración: árboles en bosques y parques con un hash por celda global, así que son estables entre chunks y versiones.
- `app/map/labels.ts`: etiquetas de cada chunk (campo `labels`):
  - Calles, senderos y ríos con nombre: los trozos de su trazado recortados al chunk (`paths`), agrupados por nombre porque una calle suele estar partida en varias vías OSM. También lleva el tramo recto más largo (`at`, `angle`, `len`) como referencia.
  - Parques, agua, plazas y edificios con nombre: un punto interior. Es el centroide o, si cae fuera (formas en L), el centro del tramo interior más ancho. Solo lo emite el chunk que contiene ese punto, así cada área sale una sola vez. No se repite si un POI del chunk ya tiene ese nombre.
  - Números de portal (`addr:housenumber`) de nodos y edificios, sin duplicar el mismo número en el edificio y en su portal.
  - Los números suben el chunk de ~1 KB a ~1.7 KB (gzip).
- `app/services/map_chunk_service.ts`: caché en memoria → BD → cola, reintentos con backoff y límites por IP.
- `app/services/map_worker.ts`: consume la cola. Funciona con varias instancias gracias a `FOR UPDATE SKIP LOCKED`.
- Tablas:
  - `osm_source_tiles`: datos crudos y, a la vez, la cola de trabajos.
  - `map_chunks`: chunks inmutables por versión del generador.
  - Ambas tienen `bounds geometry` con índice GiST.

### Cliente (`apps/game`)

- `scripts/map/geo.gd`: la misma proyección que el backend.
- `scripts/map/chunk_manager.gd`: streaming de chunks.
  - Carga los que están dentro de `load_radius` y descarga los que quedan fuera de `keep_radius` (histéresis).
  - Hasta 4 peticiones en paralelo, reintentos y caché en disco.
  - Aplica los tiles por filas en cada frame para evitar tirones.
- **Origen flotante**: los TileMap usan celdas *locales* (celda global − origen). Las celdas globales llegan a ~16.7 millones y en píxeles isométricos superarían la precisión de float32.
- `scripts/world/iso_pathfinder.gd`: A* bajo demanda sobre el rectángulo origen→destino, así funciona sobre un mapa sin límites.
- `scenes/world/map_labels.gd`: dibuja las etiquetas.
  - Une los trozos de cada calle entre chunks en tramos rectos y reparte el nombre en puntos fijos de cada tramo, pintado en el suelo con una fuente MSDF y transformación isométrica.
  - Los lugares y números van en una capa superior a tamaño fijo en pantalla, con detección de choques.
  - `location_name()` alimenta el texto de "dónde estás" del HUD.
- `scripts/autoload/location_service.gd`: la ubicación real (el "ancla"). El jugador se mueve libremente dentro de `playRadiusMeters` (500 m). Fuentes: argumentos → GPS del navegador → GPS nativo (pendiente) → IP vía backend → última conocida → por defecto.

### Ciudad, país y ubicación por IP (`apps/backend/app/geo`)

- `GET /api/v1/geo/place?lat=&lon=`: ciudad y país con **Nominatim** (datos OSM).
  - Se resuelve por tile z14 (~2.4 km) consultando el **centro del tile**, nunca la posición exacta del jugador. Así es más privado y lo comparten todos los jugadores de la zona.
  - Caché en memoria → tabla `geo_places` → proveedor. Las llamadas al proveedor van de a una, como máximo 1 por segundo (política del servidor público), y se deduplican mientras están en vuelo.
- `GET /api/v1/geo/ip`: ubicación aproximada por la IP del cliente, con ipapi.co y ipwho.is como respaldo.
  - Si la IP es local (desarrollo), el proveedor usa la IP pública del servidor, que en tu PC es la tuya.
  - Hay caché por IP y límite de consultas.
- Los proveedores (`ReverseGeocoder`, `IpLocator`) son intercambiables, como `OsmProvider`.
- Configuración en `config/geo.ts` y `NOMINATIM_URL` / `GEO_IP_ENABLED`.
- **Para producción**:
  - El límite de 1/s es por instancia y el Nominatim público no admite uso intensivo: conviene una instancia propia de Nominatim o un servicio comercial.
  - Para la IP, una base local GeoLite2 (MaxMind) evita depender de terceros y no envía las IPs de los jugadores a otros servicios.

## Uso

```bash
# Pregenerar una ciudad antes de lanzarla (evita la espera de Overpass)
pnpm map:pregenerate --lat=40.42 --lon=-3.6887 --radius=2000 --wait

# Jugar en otra ubicación
godot --path apps/game -- --lat=4.6097 --lon=-74.0817

# Forzar el mapa procedural sin servidor
godot --path apps/game -- --demo
```

Cambiar las reglas de estilo: edita `rasterizer.ts` o `labels.ts` y sube `generatorVersion`. Los chunks se regeneran **desde los datos OSM ya guardados**, sin volver a consultar Overpass.

Si agregas un tag a `KEPT_TAGS` (como `addr:housenumber`), los datos guardados no lo tienen. Para volver a pedirlos al proveedor:

```bash
pnpm map:pregenerate --lat=40.42 --lon=-3.6887 --radius=2000 --refetch --wait
```

Las zonas que no se vuelvan a pedir siguen funcionando, solo que sin ese dato (por ejemplo, sin números de portal).

## Estrategias de escalado (en orden de prioridad)

1. **Pregenerar las ciudades de lanzamiento** con `map:pregenerate`. Los primeros jugadores nunca esperan, y un source tile pregenerado sirve a todos los que lleguen después.

2. **Pasar de Overpass público a un import local en PostGIS.** Es el cambio más importante antes de producción.
   - Descargar extractos de [Geofabrik](https://download.geofabrik.de/) del país o región e importarlos con `osm2pgsql`.
   - Mantenerlos al día con `osm2pgsql-replication` (diffs diarios).
   - Crear un `PostgisProvider` que implemente `OsmProvider`. Nada más cambia.
   - Resultado: la generación pasa de 30-60 s a milisegundos y desaparecen los límites de terceros. Alternativa intermedia: una instancia propia de Overpass (`OVERPASS_URL`).

3. **CDN delante de los chunks.** La respuesta ya está lista para cachearse:
   - Es inmutable por versión (`?v=`) y no lleva cookies (la sesión solo se aplica a las rutas que la piden).
   - Tiene `ETag` y va comprimida.
   - Con Cloudflare o CloudFront delante, casi ningún request de chunk llega al backend.

4. **Mover los blobs a almacenamiento de objetos (S3/R2)** cuando la tabla crezca. Clave: `chunks/v{version}/{z}/{x}/{y}.json.gz`. El cliente puede construir la URL del CDN a partir de `/map/config`; Postgres queda solo como índice y cola. Como referencia, una ciudad de 500 km² ocupa ~35 MB, así que no corre prisa.

5. **Separar el worker en su propio proceso** (o una cola tipo BullMQ/Redis) cuando haya mucha generación. La cola en Postgres ya admite varios consumidores en paralelo.

6. **Límites de abuso con varias instancias.** El límite por IP actual vive en memoria, por instancia. En producción conviene:
   - Usar `@adonisjs/limiter` con Redis.
   - Exigir usuario autenticado para generar zonas *nuevas*; leer las ya generadas puede seguir siendo público.
   - Validar en el servidor que las zonas pedidas están cerca del ancla del jugador.

7. **Frescura de datos.** `osm_timestamp` y `fetched_at` permiten refrescar zonas viejas, por ejemplo volviendo a encolar en segundo plano los source tiles de más de 6 meses cuando alguien los visita.

8. **Multijugador por zonas** (siguiente gran pieza):
   - Un servicio en tiempo real (WebSocket) donde cada jugador se suscribe a los chunks de su radio (*interest management*).
   - Redis pub/sub por chunk o source tile.
   - Servidor autoritativo: valida que la posición esté dentro del radio del ancla.
   - Anti-spoofing de GPS: velocidad máxima entre actualizaciones, saltos imposibles.
   - Los POIs (`pois` de cada chunk, con id OSM estable) sirven como "paradas" o spawns compartidos.

## Limitaciones conocidas

- **Mar abierto**: el mar no está en OSM como polígono (solo `natural=coastline`), así que las zonas costeras se ven como pasto. Solución: importar los *water polygons* de osmdata.openstreetmap.de.
- **Edificios planos**: se dibujan como techos, sin altura ni interiores.
- **GPS en móvil**: Godot no trae una API de geolocalización. En Android/iOS hace falta un plugin (permiso `ACCESS_FINE_LOCATION` en Android), y `LocationService.set_location()` ya está listo para recibirlo. Mientras tanto, el móvil usa la IP, que es aproximada.
- **El ancla no se actualiza en vivo**: la zona se fija al entrar al mundo. Seguir al GPS mientras se juega (recentrar la zona al caminar en la vida real) es el siguiente paso.
- **Escala**: cambia un poco con la latitud por Web Mercator (las celdas miden menos metros lejos del ecuador). El radio de juego se calcula en metros, así que es justo en todas partes.
