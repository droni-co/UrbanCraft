"""Ajusta un sprite con fondo transparente (p. ej. de Layer.ai) al formato de props/.

fit_prop.py in.png out.png --height H [--max-width W] [--shadow 0.7] [--shift-x 0]
- Recorta el sprite, lo escala para que mida H px de alto (sin pasar de W de ancho).
- Pone el pie (centro de la fila opaca más baja) en el píxel (128, 192) del PNG 256x256.
- Dibuja debajo la sombra del suelo: elipse 2:1 negra semitransparente con borde difuso.
"""
import argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BASE = (128, 192)

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('out')
ap.add_argument('--height', type=float, required=True)
ap.add_argument('--max-width', type=float, default=150)
ap.add_argument('--shadow', type=float, default=0.75, help='ancho de la sombra / ancho del sprite')
ap.add_argument('--shadow-alpha', type=float, default=0.38)
ap.add_argument('--foot', type=float, default=0.04, help='fracción inferior del sprite donde se busca el pie')
ap.add_argument('--shift-x', type=float, default=0)
a = ap.parse_args()

im = Image.open(a.src).convert('RGBA')
# quita el halo del fondo removido: alpha débil fuera y un píxel de erosión
al = im.getchannel('A').point(lambda p: 0 if p < 40 else p).filter(ImageFilter.MinFilter(3))
im.putalpha(al)
im = im.crop(al.getbbox())
k = min(a.height / im.height, a.max_width / im.width)
sw, sh = max(1, round(im.width * k)), max(1, round(im.height * k))
sp = im.resize((sw, sh), Image.LANCZOS)

arr = np.asarray(sp.getchannel('A')) > 128
rows = np.where(arr.any(1))[0]
bottom = rows.max()
band = arr[max(0, bottom - max(2, int(sh * a.foot))):bottom + 1]
cols = np.where(band.any(0))[0]
foot_x = (cols.min() + cols.max()) / 2 + a.shift_x

out = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
# sombra: algo corrida a la derecha (la luz viene de arriba a la izquierda)
shw = min(sw * a.shadow, 170); shh = shw / 2
sh_img = Image.new('L', (256, 256), 0)
cx, cy = BASE[0] + shw * 0.06, BASE[1] + 1
ImageDraw.Draw(sh_img).ellipse((cx - shw / 2, cy - shh / 2, cx + shw / 2, cy + shh / 2), fill=int(255 * a.shadow_alpha))
sh_img = sh_img.filter(ImageFilter.GaussianBlur(max(2, shw * 0.06)))
shadow = Image.new('RGBA', (256, 256), (0, 0, 0, 0)); shadow.putalpha(sh_img)
out.alpha_composite(shadow)
ox, oy = round(BASE[0] - foot_x), round(BASE[1] - bottom)
layer = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
layer.paste(sp, (ox, oy), sp)
out.alpha_composite(layer)
out.save(a.out)
