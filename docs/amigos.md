# Amigos

Los jugadores pueden hacerse amigos y, por ahora, teletransportarse a donde está un amigo conectado.

## En el juego

**Menú → Amigos** (el botón muestra `Amigos (N)` si tienes solicitudes por responder):

- **Buscar:** escribe el **apodo exacto** del jugador (no distingue mayúsculas) y pulsa **Enviar solicitud**. No hay búsqueda parcial a propósito, para que no se pueda listar a los jugadores.
- **Solicitudes recibidas:** **Aceptar** o **Rechazar**. Rechazar borra la solicitud: el otro puede volver a enviarla más adelante.
- **Solicitudes enviadas:** se pueden **Cancelar**.
- **Mis amigos:** `●` verde si está en línea. Acciones:
  - **Ir:** te teletransporta a la posición actual del amigo (solo si está conectado y visible).
  - **Eliminar:** pide confirmación con un segundo clic.

Si dos jugadores se envían solicitud el uno al otro, quedan como amigos directamente.

Si estás conectado al multijugador, el servidor te avisa al momento (mensaje en pantalla) cuando alguien te envía una solicitud o acepta la tuya.

Para agregar una acción nueva con un amigo: el botón va en `FriendsSection._friend_row()` (`apps/game/scenes/ui/menu/friends_section.gd`) y la llamada al servidor en el autoload `Friends` (`apps/game/scripts/autoload/friends.gd`).

## Privacidad

- **Ir** da la posición **exacta** del amigo, y como el juego empieza en la ubicación real, puede ser su casa. Solo la ven los amigos aceptados.
- El **modo fantasma** (Menú → Multijugador) te oculta también para tus amigos: apareces desconectado y no pueden ir a donde estás.
- Las respuestas solo incluyen id, apodo y personaje (nunca el correo).

## API (`/api/v1/friends`, con sesión)

| Método | Ruta | Descripción |
| ------ | ---- | ----------- |
| GET    | `/` | `{ friends: [{ id, nickname, skin, online, friendshipId, since }], incoming, outgoing }` |
| GET    | `/search?nickname=X` | `{ user: { id, nickname, skin, relation } }` · 404. `relation`: `none`, `friend`, `incoming`, `outgoing`, `self` |
| POST   | `/requests` `{ nickname }` | 201 `{ status: 'sent' }` · 200 `{ status: 'accepted' }` si él ya te la había enviado · 404 · 409 · 422 |
| POST   | `/requests/:id/accept` | Acepta una solicitud recibida |
| DELETE | `/requests/:id` | Rechaza una recibida o cancela una enviada |
| DELETE | `/:userId` | Deja de ser amigos |
| GET    | `/:userId/location` | `{ lat, lon }` del amigo · 409 `friend_offline` si no está conectado o está en modo fantasma |

Por el WebSocket del multijugador llega `{ t: 'friends', e: 'request' | 'accepted', n: apodo }` (ver `apps/backend/app/realtime/protocol.ts`).

Datos: tabla `friendships` con una fila por pareja (índice único sobre `LEAST/GREATEST` de los dos ids), `status` = `pending` o `accepted`.

## Pruebas

```bash
cd apps/backend && node ace test --files tests/functional/friends.spec.ts

# Dos jugadores contra el backend local (DEV_LOGIN_ENABLED=true):
godot --path apps/game -- --local --dev-login=ana
godot --path apps/game -- --local --dev-login=beto
```
