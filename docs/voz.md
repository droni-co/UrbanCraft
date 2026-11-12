# Voz con amigos

Chat de voz con tus amigos en línea. Al activarlo oyes a los amigos que también lo tengan activo, y ellos a ti.

> **Fase 1: solo en la versión web** (`/play`). En PC y Android el botón muestra "La voz por ahora solo funciona en la versión web". Ver [Fase 2](#fase-2-pc-y-android).

## En el juego

| | PC | Móvil |
| - | -- | ----- |
| Activar o desactivar | Botón de micrófono (junto al chat) o Menú → Multijugador → **Activar voz** | Botón de micrófono |
| Hablar | Mantener **V** | Mantener el botón **Voz** (sobre A y B) |
| Micrófono abierto | Menú → Multijugador → **Micrófono abierto** | Igual |
| Silenciar a un amigo | Clic en su nombre (lista de la derecha) | Tocar su nombre |

- **Primera vez:** el navegador pide permiso para usar el micrófono. Si lo niegas, el juego explica cómo activarlo.
- **Botón de micrófono:** gris con la voz apagada, verde con la voz activa y verde brillante mientras transmites.
- **Lista bajo los stats:**
  - `Tú · mantén V`, `Tú · hablando` o `Tú · micrófono abierto`;
  - cada amigo en la voz: blanco, verde mientras habla, gris mientras conecta, rojo si no se pudo conectar, y `· silenciado` si lo silenciaste.
- **Avisos en pantalla:** cuando un amigo entra o sale de la voz.
- **Mientras escribes en el chat**, la V es una letra y no activa el micrófono.
- **Micrófono abierto:** transmite cuando detecta voz. El navegador cancela el eco, pero con altavoces fuertes conviene usar audífonos.
- **Al salir del mundo, cerrar sesión o pasar a modo fantasma**, la voz se desactiva y se suelta el micrófono.

## Cómo funciona

```
navegador A ── RTCPeerConnection (audio Opus, directo) ── navegador B
     │                                                       │
     └──── WebSocket /ws: quién está en la voz + señalización ────┘
                         (GameRealtimeServer)
```

- **Servidor** (`app/realtime/game_server.ts`): no toca el audio, solo coordina.
  - `{ t: 'voice', on }`: entras o sales. Se avisa a tus amigos conectados que están en la voz y, al entrar, se te dice quiénes ya estaban: `{ t: 'voice', id, n, on }`.
  - `{ t: 'rtc', to, k, d }`: reenvía offer, answer e ICE, **solo entre amigos aceptados que están los dos en la voz**.
  - Al desconectarte, pasar a modo fantasma o dejar de ser amigos, se avisa `on: false` y la conexión se corta.
  - En modo fantasma no se puede entrar.
- **Cliente:**
  - autoload `Voice` (`scripts/autoload/voice.gd`): con quién conectarse, estado y pulsar para hablar;
  - `web/voice.js`: micrófono con cancelación de eco y supresión de ruido del navegador, una `RTCPeerConnection` por amigo, reproducción y detección de quién habla. Se carga con `JavaScriptBridge`;
  - interfaz: `VoicePanel` (`scenes/ui/voice_panel.gd`) y la sección Multijugador del menú.
- **Quién hace la oferta:** en cada pareja ofrece el de **id menor** (así nunca ofrecen los dos a la vez).
- **Pulsar para hablar:** el micrófono siempre está abierto en el navegador, pero la pista que se envía se activa solo mientras mantienes V. El nivel de la voz se mide con otra copia de la pista, para que el micrófono abierto pueda detectar voz.
- **Topología:** cada amigo se conecta con cada uno. Va bien hasta unos 6–8 amigos a la vez en la voz.

### Servidores ICE (STUN/TURN)

Están en `voiceIceServers` (`apps/backend/config/realtime.ts`) y llegan al cliente en el mensaje `welcome`. Hoy solo se usa el **STUN público de Google**: entre un 10 y un 20 % de las parejas (sobre todo con datos móviles o redes de empresa) no logran conectarse directo, y su fila sale en rojo ("no se pudo conectar").

Para agregar un TURN propio (coturn en el VPS):

```ts
voiceIceServers: [
  { urls: ['stun:stun.l.google.com:19302'] },
  { urls: ['turn:urbancraft.droni.vip:3478'], username: '…', credential: '…' },
],
```

Lo ideal es que el backend genere credenciales temporales por usuario (`use-auth-secret` de coturn) en lugar de unas fijas.

## Privacidad

- **Tus amigos pueden ver tu dirección IP:** la conexión es directa entre navegadores. Solo se conectan amigos aceptados, y solo mientras los dos tienen la voz activa.
- **El servidor no recibe ni guarda audio.**
- **El modo fantasma** corta la voz.

## Probarlo en local

Hacen falta dos navegadores, o dos orígenes distintos en el mismo navegador (cada origen guarda su sesión):

1. `pnpm dev` en el backend (con `DEV_LOGIN_ENABLED=true`) y `pnpm game:export:web`.
2. Abre `http://localhost:3333/play` y entra como `ana`. En otra ventana abre `http://localhost.:3333/play` (con el punto final) y entra como `beto`. Deben ser amigos.
3. Activa la voz en las dos.

En la consola del navegador, `UCVoice.debug()` muestra el estado de cada conexión y el nivel de audio.

## Fase 2: PC y Android

Godot no trae pistas de audio WebRTC ni el códec Opus. El plan:

- **Transporte:** canal de datos WebRTC, con el plugin [webrtc-native](https://github.com/godotengine/webrtc-native) en PC y Android.
- **Captura y códec:** micrófono con `AudioStreamMicrophone` y `AudioEffectCapture`, codificado en Opus con la extensión [two-voip](https://github.com/goatchurchprime/two-voip-godot-4), que también trae reducción de ruido.
- **Web:** tendría que hablar también este "modo canal de datos" para conversar con jugadores de PC y Android.
- **Eco:** en PC y Android no hay cancelación de eco, así que conviene dejar pulsar para hablar como único modo o recomendar audífonos.
- **Android:** necesita el permiso `RECORD_AUDIO` en el preset y `audio/driver/enable_input=true`.
