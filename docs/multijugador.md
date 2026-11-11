# Multijugador en línea

Los jugadores se ven entre sí en tiempo real: los que están **en tu pantalla** aparecen con su sprite, su apodo y nivel, caminando o corriendo hacia donde miran, y con sus acciones (saludar, interactuar). Los que están **en tu radio de alcance** (1 km) salen como puntos en el minimapa.

## Cómo funciona

```
Juego (Godot)                         Backend (AdonisJS, mismo puerto 3333)
Online (WebSocketPeer) ── ws://…/ws ──> GameRealtimeServer (paquete ws)
  state  10/s moviéndose                 valida (velocidad) y guarda en PresenceWorld
                                         (índice espacial en memoria, cubetas de 128 celdas)
  <── snap   10/s: cercanos (≤ 40 celdas), posición exacta + apodo/nivel/personaje
             la 1.ª vez y cada vez que cambian
  <── radar   1/s: resto del radio (1 km), posición redondeada a 25 m, sin id
  act  ──>  <── act: se reenvía a los cercanos
```

- **Conexión:** el WebSocket vive en el mismo servidor HTTP (`/ws`). El primer mensaje es `{ t: 'auth', token }` con el token de la sesión (el mismo del API). Sin token válido en 5 s se cierra. Una cuenta = una conexión: si entras desde otra ventana, la anterior se cierra (código 4001).
- **Coordenadas:** celdas **globales** del mapa (z24, ~1,8–2,4 m) con decimales. En Godot se guardan como `float` (64 bits) y se pasan a coordenadas locales **antes** de convertirlas a `Vector2` (32 bits no alcanza para ~16 millones de celdas).
- **Suavizado:** cada avatar remoto (`RemotePlayer`) se dibuja 150 ms por detrás, interpolando entre los dos últimos estados recibidos. Los saltos grandes (teletransporte) no se interpolan.
- **Anti-trampas básico:** el servidor rechaza movimientos más rápidos que 9 celdas/s (corriendo se llega a ~7). Aparecer o teletransportarse se marca con `spawn` y se permite una vez cada 3 s. Si el servidor rechaza un salto, el cliente lo reintenta como aparición.
- **Límites:** mensajes de hasta 2 KB y 40 por segundo (muy por encima, se cierra la conexión). Sin mensajes en 30 s se cierra (el cliente manda `ping` cada 10 s, también con el menú abierto).
- Sin conexión el juego sigue funcionando y reintenta solo (1, 2, 4… hasta 15 s). Con el mapa de demostración no hay multijugador.

El protocolo completo está documentado en `apps/backend/app/realtime/protocol.ts` y la configuración (radios, tick, límites) en `apps/backend/config/realtime.ts`.

## En el juego

- **Arriba a la izquierda** se ve cuántos jugadores hay cerca (o `conectando…` / `sin multijugador`).
- **Saludar:** tecla **G** (gamepad: Y) o el botón del menú. Los demás ven `¡Hola!` y un saltito. **Interactuar** (E) muestra un `!`.
- **Menú → Multijugador:** estado de la conexión, cuántos hay en tu radio y el interruptor **Visible para otros jugadores** (modo fantasma: tú sigues viendo a los demás, ellos no te ven ni en pantalla ni en el radar).
- **Minimapa:** puntos amarillos. Los cercanos van con su posición exacta y los lejanos aproximados; los que quedan fuera de la vista se pegan al borde, más tenues.

## Privacidad

Como cada jugador empieza en su **ubicación real**, su posición en el juego dice dónde está en el mundo. Medidas actuales:

- Fuera de tu pantalla solo se ve un punto **sin nombre**, redondeado a 25 m.
- El modo fantasma te oculta del todo.
- La pantalla inicial cierra la conexión: solo apareces mientras estás en el mundo.

Pendiente de decidir: una **zona privada** alrededor de la ubicación real (por ejemplo 200–300 m) en la que no se muestre al jugador a los demás, o hacer aparecer a todos con un desplazamiento aleatorio.

## Pruebas

```bash
cd apps/backend && node ace test --files tests/functional/realtime.spec.ts   # 9 pruebas con clientes ws
node ace test --files tests/unit/realtime.spec.ts                            # protocolo e índice espacial

# Dos jugadores en la misma zona (servidor con DEV_LOGIN_ENABLED=true):
godot --path apps/game -- --dev-login=ana  --lat=40.42    --lon=-3.6887
godot --path apps/game -- --dev-login=beto --lat=40.42003 --lon=-3.68866
```

## Escalar más adelante

- **Varias instancias del backend:** hoy el estado está en memoria de un proceso. Con varias instancias, repartir a los jugadores por zona (sharding por chunk) o publicar las posiciones por Redis pub/sub (Redis ya está en docker-compose).
- **Teletransporte con permiso del servidor:** hoy el cliente decide a dónde se teletransporta (el servidor solo limita la frecuencia). Cuando el teletransporte cueste algo, el servidor debería autorizarlo.
- **Validar contra el mapa:** el servidor no comprueba si la celda es caminable ni el radio de 5 km alrededor del ancla real; para eso tendría que conocer el ancla de cada jugador.
- **Personaje (skin):** se guarda en la cuenta (`PATCH /api/v1/account/profile { skin }`) y el servidor lo reenvía en el próximo snap a quienes te tienen cerca. El servidor no conoce el arte: valida solo el formato del nombre, y si un jugador no tiene esa hoja usa el personaje por defecto.
- **Nivel en vivo:** el nivel que ven los demás se lee al conectar; si subes de nivel jugando, se actualiza al reconectar.
- **Protocolo binario:** el JSON pesa ~40 bytes por jugador cercano y snapshot. Con muchos jugadores juntos se puede pasar a binario o enviar solo los cambios.
