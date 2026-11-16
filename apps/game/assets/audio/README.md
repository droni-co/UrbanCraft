# Sonido del juego

Lo reproduce `GameAudio` (`scripts/autoload/game_audio.gd`). El volumen de la
música y el de los efectos se cambian por separado en **Menú → Ajustes** y se
guardan en el dispositivo (`user://settings.cfg`).

| Carpeta    | Bus   | Uso |
| ---------- | ----- | --- |
| `music/`   | Music | `Day01.ogg` y `Day02.ogg` suenan de día, uno tras otro; `Night.ogg`, de noche. La pantalla de inicio usa siempre un tema de día. |
| `sfx/`     | SFX   | `teleport.wav`: al teletransportarse o volver a casa. |
| `ui/`      | SFX   | `dooropen` entrar a un lugar · `lockeddoor` lugar cerrado o edificio · `eating` comer · `headwear` abrir el morral, cambiar de personaje · `picklock` / `picklock-fail` rebuscar (bien / nada) · `ring` dinero, logros, lugares nuevos, amigos · `scroll` abrir el menú, diálogos, historia. |
| `ambient/` | SFX   | Ambiente del mundo (`scenes/world/ambient_sounds.gd`): pájaros y gaviotas de día, cuervos al atardecer, grillos y chimenea de noche, agua y fuentes cerca, reloj al anochecer y al amanecer. También acciones: `build*`/`smith*` fabricar, trabajar y colocar objetos; `alchemist*`/`bubbles` cocinar; `fireplace` asar en la parrilla. |

Para cambiar un sonido basta con reemplazar el archivo con el mismo nombre.
Para agregar uno nuevo, súmalo a `GameAudio.SOUNDS` (efectos) o a las listas de
`AmbientSounds` (ambiente).

- **Música y ambiente largo:** `.ogg`. **Efectos cortos:** `.wav` (Godot los
  comprime solo a QOA al importar).
- Los efectos largos se cortan con un fundido (campo `max` en `SOUNDS`) para no
  quedarse sonando sobre la interfaz.

## Buses

Los buses `Music` y `SFX` están en `apps/game/default_bus_layout.tres`, que Godot carga al arrancar. No los crees desde el código: en la versión web (reproducción por "samples") un bus creado en tiempo de ejecución deja mal conectado el audio del navegador y el juego queda mudo.
