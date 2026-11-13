# Iconos de la interfaz

Iconos de **48×48** píxeles con fondo transparente. El juego los muestra a 12×12 lógicos (como todo el arte, a x4: ver `assets/art/README.md`), con filtro lineal. Los iniciales son los de pixel art 12×12 ampliados con Scale4x (`scale4x()` en `tools/generate_starter_art.gd`).

| Archivo | Uso |
| ------- | --- |
| `hunger.png` | Hambre (HUD de stats) |
| `xp.png` | Experiencia / nivel |
| `money.png` | Dinero |
| `stat.png` | Reserva para stats que todavía no tienen icono |

**Stats nuevos:** el nombre del icono sale del catálogo del backend (`apps/backend/config/player_stats.ts`, campo `icon`). Para darle icono a un stat nuevo, crea `<icon>.png` aquí. Si no existe, se usa `stat.png`.

Estilo: contorno oscuro (no negro puro) y luz desde arriba a la izquierda, igual que el resto del arte (`assets/art/README.md`).
