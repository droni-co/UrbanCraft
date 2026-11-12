# Chat

Chat de texto público entre jugadores, con alcance limitado: **solo lees a quienes están en tu zona y a tus amigos**.

## Quién lee tu mensaje

| Destinatario | Condición |
| ------------ | --------- |
| Jugadores de tu **zona** | Su chunk del mapa está a ≤ `chatChunkRadius` chunks del tuyo. Por defecto 1: tu chunk y los 8 vecinos (3×3 chunks de 64 celdas, unos 450 m de lado). |
| Tus **amigos** conectados | Estén donde estén. Sus nombres salen en verde. |
| Tú | El servidor te devuelve tu mensaje como confirmación, y entonces aparece tu globo. |

- Usamos 3×3 chunks y no solo el tuyo porque, con solo el tuyo, dos jugadores a un paso de distancia no se leerían si los separa un borde de chunk. Para usar solo el chunk propio, pon `chatChunkRadius: 0` en `apps/backend/config/realtime.ts`.
- **Modo fantasma:** solo te leen tus amigos (si no, el chat delataría que estás cerca). Tú sigues leyendo a los de tu zona.
- Antes de aparecer en el mapa (todavía cargando) solo te leen tus amigos.
- Si dejan de ser amigos, se dejan de leer al momento (salvo que estén en la misma zona).

## En el juego

| | PC | Móvil |
| - | -- | ----- |
| Abrir | **Enter** o **T**, o el botón de chat (junto al menú) | Botón de chat |
| Enviar | **Enter** | Enviar del teclado o botón **Enviar** |
| Cerrar | **Esc**, **Enter** con el campo vacío, o **✕** | **✕** |
| Caminar con el chat abierto | Clic en el mapa (suelta el teclado) | Joystick o tocar el mapa |

- **Con el chat cerrado:** los mensajes nuevos aparecen unos segundos a la izquierda, sin bloquear el joystick ni los clics. El botón muestra cuántos mensajes no has leído.
- **Ventana del chat:** se abre **arriba** de la pantalla para que el teclado del móvil no la tape. Tiene el historial de la sesión (se desliza con el dedo) y debajo el campo de texto. El campo **sigue activo después de enviar**, para conversar seguido.
- **Globos:** cada mensaje aparece unos segundos sobre la cabeza de quien lo escribió, si lo tienes en pantalla.
- **Mientras escribes** el personaje no se mueve: WASD, espacio y Shift escriben en el campo.
- **Colores:** tú en amarillo, amigos en verde, los demás en azul y los avisos del juego en gris.

## Límites y limpieza

- **Largo:** hasta 200 caracteres.
- **Limpieza en el servidor:**
  - quita los caracteres de control y los de dirección del texto (con ellos se puede "voltear" lo que se ve);
  - junta los espacios repetidos y recorta los de los extremos.
- **Frecuencia:** ráfagas de hasta 4 mensajes y luego 1 cada 2 s (`chatBurst`, `chatRefillMs`). Si escribes más rápido, el servidor responde `reject` y el chat avisa cuánto esperar.
- **Formato del juego:** se escapa lo que escribe cada jugador, así que `[b]` y similares se ven tal cual.
- **Historial:** nada se guarda en el servidor. Cada cliente guarda los últimos 100 mensajes de la sesión y los borra al cerrar sesión.

## Protocolo (WebSocket `/ws`)

```
cliente → servidor   { t: 'say', m: 'hola' }
servidor → cliente   { t: 'chat', id, n: apodo, m: texto, f: 1 si es tu amigo · 0 }
                     { t: 'reject', r: 'chat', retry: ms }
                     { t: 'error', e: 'bad_message' }   (vacío o más de 200 caracteres)
```

Código:
- **Backend:** `GameRealtimeServer.#onSay` (`apps/backend/app/realtime/game_server.ts`) y `cleanChatText` (`protocol.ts`).
- **Juego:** autoload `Chat` (`scripts/autoload/chat.gd`), `ChatPanel` (`scenes/ui/chat_panel.gd`) y `ChatBubble` (`scenes/player/chat_bubble.gd`).

## Pendiente

- **Emojis en la versión web:** la fuente del juego no los tiene; en PC y Android se usan las fuentes del sistema. Haría falta incluir una fuente de emojis (pesa varios MB).
- **Moderación:** silenciar o bloquear a un jugador, reportar y filtrar groserías.
- Con varias instancias del backend, el chat tendría que repartirse por Redis, igual que las posiciones (ver [multijugador.md](multijugador.md#escalar-más-adelante)).
