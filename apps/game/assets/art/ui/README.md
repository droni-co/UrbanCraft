# Arte de la interfaz

Todo lo de esta carpeta se pintó en [Layer.ai](https://layer.ai) con GPT Image 2.5 Flare. Como referencia de estilo se usaron `../baseStyle.jpeg` y los cinco personajes de `../characters/`. Los originales están en `../source/ui/`, que no se exporta.

| Ruta | Qué es | Dónde se usa |
| ---- | ------ | ------------ |
| `logo.png` | Logo «UrbanCraft» con la casita de teja, 1200 px de ancho, fondo transparente | Pantalla de título y pantalla de carga |
| `screens/title.jpg` | Ilustración de portada: la ciudad al atardecer con los 5 personajes | Pantalla de título (`scenes/main`) |
| `screens/city.jpg`, `plaza.jpg`, `park.jpg`, `night.jpg` | Ilustraciones de 1920×1088 | Pantalla de carga (rotan cada 7 s, con zoom lento) |
| `frames/panel.png` | Marco de panel: azul marino con esquinas de latón | Menú, chat y tarjeta de la pantalla de título (`UiArt.panel()`) |
| `icons/` | Iconos pintados | Ver `icons/README.md` |
| `poi/` | Iconos de categorías de lugares (pixel art) | Pines del mapa |

## Cómo se dibuja

- La pantalla lógica es de 640×360 y el arte está a mayor resolución. Los nodos que lo muestran usan filtro lineal con mipmaps (`UiArt.smooth()`), porque el filtro por defecto del proyecto es *nearest* (para el pixel art). Los `.import` de esta carpeta tienen `mipmaps/generate=true`.
- `frames/panel.png` se dibuja como *nine-slice* con `ArtStyleBox` (`scripts/ui/art_style_box.gd`), a 3 píxeles del PNG por píxel lógico: las esquinas miden unos 12 px lógicos se estire como se estire el panel. Los bordes que no se estiran están en `UiArt.PANEL_MARGINS`. Si cambias el PNG, ajústalos.
  - El panel se generó sobre verde (#00FF00) y se recortó con croma: `magick panel.png -alpha set -fuzz 30% -transparent '#00ff00' -trim +repage -resize 50%`.
- Los botones, chips del HUD, barras y campos de texto se dibujan en código (`scenes/ui/menu/menu_theme.gd` y `UiArt`), con la misma paleta:
  - azul marino `13233d`;
  - latón `e6b85c`: foco, selección y marcos;
  - terracota `e2703a`: botón principal;
  - texto crema `f5efe3`.

## Fuentes

En `assets/fonts/` (licencia SIL OFL, ver `OFL-*.txt`):

- **Nunito**: texto. Es la fuente por defecto del proyecto (`gui/theme/custom_font` = `ui_body.tres`, peso 650). `ui_bold.tres` (peso 850) para botones y etiquetas del HUD.
- **Fredoka**: títulos (`ui_display.tres`, peso 600).

## Intro

La pantalla de título hace una intro corta la primera vez que se abre en cada ejecución: fundido desde negro, la ilustración se aleja, cae el logo con rebote y entran el lema y el panel. Un clic o una tecla la salta. Después la ilustración queda con un paneo lento y motas de luz flotando. Todo está en `scenes/main/main.gd`; los tiempos están en `_start_intro()`.
