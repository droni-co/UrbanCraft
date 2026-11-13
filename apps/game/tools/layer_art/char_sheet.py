"""Arma la hoja final de un personaje a partir de las hojas de animación de Layer.

Uso: char_sheet.py out.png --s s.png --se se.png --e e.png --ne ne.png --n n.png [--height 39] [--scale 3]

Cada hoja de entrada es una grilla de 4x4 cuadros (como la pide el prompt de
Layer): fila 1 = respirar (4), filas 2-3 = caminar (8), fila 4 = saludar (4).
La salida es la hoja que lee scripts/characters/character_skins.gd:

- 16 columnas: 0-3 quieto (respira), 4-11 caminata, 12-15 saludo;
- 8 filas, una por dirección: e, se, s, sw, w, nw, n, ne (sw, w y nw son el
  espejo de se, e y ne);
- cuadros de 32x48 px lógicos a la escala `--scale` (x3 = 96x144), con los pies
  en (16, 44) lógicos.

Cada cuadro se recorta (se queda con la mancha más grande, para no arrastrar
pedazos del cuadro vecino), se escala igual en todas las direcciones (para que
el personaje mida `--height` px lógicos quieto, de frente) y se alinea: el
píxel más bajo en la línea de los pies y el centro del torso en el centro.
"""
import argparse
from collections import deque

import numpy as np
from PIL import Image

FRAME = (32, 48)
FEET = (16, 44)
GRID = 4
ROWS = ['e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne']
MIRROR = {'sw': 'se', 'w': 'e', 'nw': 'ne'}
ALPHA = 40


def largest_blob(alpha: np.ndarray) -> np.ndarray:
    """Máscara de la mancha conectada más grande (en una versión reducida, para que sea rápido)."""
    step = 4
    small = alpha[::step, ::step] > ALPHA
    h, w = small.shape
    seen = np.zeros_like(small, bool)
    best, best_size = None, 0
    for y0 in range(h):
        for x0 in range(w):
            if not small[y0, x0] or seen[y0, x0]:
                continue
            blob = []
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            while q:
                y, x = q.popleft()
                blob.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            if len(blob) > best_size:
                best, best_size = blob, len(blob)
    keep = np.zeros_like(small, bool)
    if best:
        ys, xs = zip(*best)
        keep[list(ys), list(xs)] = True
    # Vuelve a tamaño completo con un margen de un bloque (bordes suaves).
    big = np.kron(keep, np.ones((step, step), bool))[: alpha.shape[0], : alpha.shape[1]]
    # (sin np.roll: daría la vuelta y traería pedazos del borde opuesto).
    grown = big.copy()
    grown[step:] |= big[:-step]
    grown[:-step] |= big[step:]
    grown[:, step:] |= big[:, :-step]
    grown[:, :-step] |= big[:, step:]
    return grown


def frames(path: str) -> list[Image.Image]:
    """Los 16 cuadros de una hoja de Layer, recortados a su contenido."""
    sheet = Image.open(path).convert('RGBA')
    cw, ch = sheet.width // GRID, sheet.height // GRID
    out = []
    for r in range(GRID):
        for c in range(GRID):
            cell = np.asarray(sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))).copy()
            cell[..., 3] = np.where(largest_blob(cell[..., 3]), cell[..., 3], 0)
            img = Image.fromarray(cell)
            box = img.getchannel('A').point(lambda a: 255 if a > ALPHA else 0).getbbox()
            out.append(img.crop(box) if box else img)
    return out


def anchor_x(img: Image.Image) -> float:
    """Centro horizontal del torso (franja del 30 al 70 % de la altura)."""
    a = np.asarray(img.getchannel('A'), float)
    h = a.shape[0]
    band = a[int(h * 0.3): int(h * 0.7)]
    cols = band.sum(0)
    return float((cols * np.arange(len(cols))).sum() / cols.sum()) if cols.sum() else img.width / 2


def resize_premultiplied(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Escala sin bordes oscuros (premultiplica el alfa)."""
    a = np.asarray(img, float) / 255.0
    a[..., :3] *= a[..., 3:4]
    small = [np.asarray(Image.fromarray((a[..., i] * 255).astype(np.uint8)).resize(size, Image.LANCZOS), float) / 255.0
             for i in range(4)]
    rgb = np.stack(small[:3], -1)
    alpha = np.clip(small[3], 0, 1)
    rgb = np.where(alpha[..., None] > 1e-3, rgb / np.maximum(alpha[..., None], 1e-3), 0)
    out = np.dstack([np.clip(rgb, 0, 1), alpha])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    for d in ('s', 'se', 'e', 'ne', 'n'):
        ap.add_argument('--' + d, required=True)
    ap.add_argument('--height', type=float, default=39.0, help='alto del personaje quieto, en px lógicos')
    ap.add_argument('--scale', type=int, default=3)
    a = ap.parse_args()

    k = a.scale
    fw, fh = FRAME[0] * k, FRAME[1] * k
    feet_x, feet_y = FEET[0] * k, FEET[1] * k
    src = {d: frames(getattr(a, d)) for d in ('s', 'se', 'e', 'ne', 'n')}
    # Misma escala en todas las direcciones: la del personaje quieto de frente.
    idle_h = float(np.median([f.height for f in src['s'][:4]]))
    s = a.height * k / idle_h

    sheet = Image.new('RGBA', (fw * 16, fh * len(ROWS)), (0, 0, 0, 0))
    for row, d in enumerate(ROWS):
        base = MIRROR.get(d, d)
        for col, f in enumerate(src[base]):
            if d in MIRROR:
                f = f.transpose(Image.FLIP_LEFT_RIGHT)
            img = resize_premultiplied(f, (max(1, round(f.width * s)), max(1, round(f.height * s))))
            x = round(feet_x - anchor_x(img))
            y = feet_y + (k - 1) - img.height + 1
            # Lo que se salga del cuadro se recorta (alpha_composite no acepta posiciones negativas).
            cx, cy = max(0, -x), max(0, -y)
            part = img.crop((cx, cy, min(img.width, fw - x), min(img.height, fh - y)))
            frame = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
            frame.alpha_composite(part, (x + cx, y + cy))
            sheet.alpha_composite(frame, (col * fw, row * fh))
    sheet.save(a.out, optimize=True)


if __name__ == '__main__':
    main()
