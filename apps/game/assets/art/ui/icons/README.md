# Iconos de la interfaz

Iconos de **12×12** píxeles, en pixel art y con fondo transparente. El juego los muestra a tamaño real, sin filtrado.

| Archivo | Uso |
| ------- | --- |
| `hunger.png` | Hambre (HUD de stats) |
| `xp.png` | Experiencia / nivel |
| `money.png` | Dinero |
| `stat.png` | Reserva para stats que todavía no tienen icono |

**Stats nuevos:** el nombre del icono sale del catálogo del backend (`apps/backend/config/player_stats.ts`, campo `icon`). Para darle icono a un stat nuevo, crea `<icon>.png` aquí. Si no existe, se usa `stat.png`.

Estilo: contorno oscuro de 1 px (no negro puro), 3–4 tonos y luz desde arriba a la izquierda, igual que el resto del arte (`assets/art/README.md`).
