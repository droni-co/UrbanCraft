# Iconos de la interfaz

Iconos de **96×96** píxeles con fondo transparente, pintados en [Layer.ai](https://layer.ai) (GPT Image 2.5 Flare, con `baseStyle.jpeg` como referencia de estilo). Se muestran reducidos, de 12 a 24 px lógicos según dónde estén, con filtro lineal y mipmaps (`UiArt.icon()` / `UiArt.icon_rect()` en `scripts/ui/ui_art.gd`).

El original es una hoja de 4×4 (`assets/art/source/ui/icons_sheet.png`, no se exporta). Cada icono se recortó de su celda de 384×384, se recortó el margen transparente y se centró en 96×96 ocupando 88 px.

| Archivo | Uso |
| ------- | --- |
| `menu.png` | Botón de menú del HUD (mochila) y cabecera del menú |
| `chat.png` | Botón de chat del HUD |
| `mic.png` | Botón de voz del HUD |
| `teleport.png`, `character.png`, `multiplayer.png`, `friends.png`, `account.png`, `debug.png` | Secciones del menú (`GameMenu.add_section(título, control, icono)`) |
| `play.png` | Botón «Jugar» de la pantalla de título |
| `hunger.png` | Hambre (HUD de stats) |
| `xp.png` | Experiencia / nivel; también la estrella de los consejos de la pantalla de carga |
| `money.png` | Dinero |
| `settings.png`, `map.png`, `exit.png` | Libres, para opciones futuras |
| `stat.png` | Reserva para stats que todavía no tienen icono (pixel art inicial) |

**Stats nuevos:** el nombre del icono sale del catálogo del backend (`apps/backend/config/player_stats.ts`, campo `icon`). Para darle icono a un stat nuevo, crea `<icon>.png` aquí. Si no existe, se usa `stat.png`.

Estilo: contorno marrón oscuro (no negro puro), volúmenes con degradés suaves y luz desde arriba a la izquierda, igual que el resto del arte (`assets/art/README.md`).

