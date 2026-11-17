"""Arma la hoja animada de un personaje y GIFs de vista previa.

  python3 tools/characters/pack.py <frames_dir> <out_sheet.png> <preview_dir>

Filas: e, se, s, sw, w, nw, n, ne. Columnas (LAYOUT, igual que
CharacterSkins.ANIMATED en el juego). Los cuadros vienen de render.gd:
<anim>_<fila>_<i>.png (32x48 lógicos a escala K). Aquí se les pone el
contorno marrón del arte del juego.
"""
import sys
from pathlib import Path
from PIL import Image, ImageFilter, ImageChops

K = 3
FW, FH = 32 * K, 48 * K
# Dos bandas de 8 filas (direcciones). (animación, columna, banda, cuadros,
# ancho en columnas, fps): la bici usa cuadros dobles (64 px).
LAYOUT = [
    ("idle", 0, 0, 4, 1, 3),
    ("walk", 4, 0, 8, 1, 11),
    ("wave", 12, 0, 4, 1, 6),
    ("bike", 16, 0, 4, 2, 8),
    ("craft", 0, 1, 4, 1, 6),
    ("interact", 4, 1, 4, 1, 6),
    ("attack", 8, 1, 4, 1, 10),
    ("defend", 12, 1, 4, 1, 6),
]
COLUMNS = 24
BANDS = 2
OUTLINE = (52, 34, 24)  # marrón oscuro de los contornos del arte
OUTLINE_PX = 2  # a x3: ~0,7 px lógicos


def outline(img: Image.Image) -> Image.Image:
    alpha = img.getchannel("A").point(lambda a: 255 if a > 90 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1))
    ring = ImageChops.subtract(grown, img.getchannel("A"))
    ring = ring.point(lambda a: int(a * 0.9))
    back = Image.new("RGBA", img.size, OUTLINE + (0,))
    back.putalpha(ring)
    return Image.alpha_composite(back, img)


def main() -> None:
    frames_dir, out_sheet, preview_dir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    preview_dir.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (FW * COLUMNS, FH * 8 * BANDS), (0, 0, 0, 0))
    missing = []
    for anim, col0, band, count, span, _fps in LAYOUT:
        for row in range(8):
            for i in range(count):
                f = frames_dir / f"{anim}_{row}_{i:02d}.png"
                if not f.exists():
                    missing.append(f.name)
                    continue
                img = Image.open(f).convert("RGBA")
                if img.size != (FW * span, FH):
                    img = img.resize((FW * span, FH), Image.LANCZOS)
                sheet.paste(outline(img), ((col0 + i * span) * FW, (band * 8 + row) * FH))
    sheet.save(out_sheet, optimize=True)
    print("hoja:", out_sheet, sheet.size, "faltan:", len(missing))

    bg = (122, 140, 92, 255)
    for anim, col0, band, count, span, fps in LAYOUT:
        out = []
        cw = FW * span
        for i in range(count):
            canvas = Image.new("RGBA", (cw * 8, FH), bg)
            for row in range(8):
                x = (col0 + i * span) * FW
                y = (band * 8 + row) * FH
                cell = sheet.crop((x, y, x + cw, y + FH))
                canvas.alpha_composite(cell, (row * cw, 0))
            out.append(canvas.convert("RGB"))
        out[0].save(preview_dir / f"{anim}.gif", save_all=True, append_images=out[1:],
                    duration=int(1000 / fps), loop=0)


if __name__ == "__main__":
    main()
