"""Pasa los detalles de una variante de techo (tanque, chimenea, tragaluz...) a un techo nuevo.

Uso: transplant.py old_base old_variant new_base out [--threshold 22] [--grow 3]

Los detalles son los píxeles en que `old_variant` difiere de `old_base` (los dos son
tiles iso 256x128 hechos por generate_starter_art). Se recortan con un borde suave y
se pegan sobre `new_base`, con una sombra de contacto leve debajo.
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('old_base'); ap.add_argument('old_variant'); ap.add_argument('new_base'); ap.add_argument('out')
    ap.add_argument('--threshold', type=float, default=22)
    ap.add_argument('--grow', type=int, default=3)
    a = ap.parse_args()

    old = np.asarray(Image.open(a.old_base).convert('RGBA'), float)
    var = Image.open(a.old_variant).convert('RGBA')
    new = Image.open(a.new_base).convert('RGBA')
    v = np.asarray(var, float)

    diff = np.abs(v[..., :3] - old[..., :3]).max(-1) * (v[..., 3] > 0)
    mask = Image.fromarray(((diff > a.threshold) * 255).astype(np.uint8))
    # Quita puntos sueltos (ruido de la textura) y cierra el contorno del detalle.
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(2 * a.grow + 1))
    mask = mask.filter(ImageFilter.GaussianBlur(1.0))

    # Sombra de contacto: la silueta desplazada abajo a la derecha (sol arriba a la izquierda).
    shadow = Image.new('RGBA', new.size, (20, 18, 40, 0))
    sm = mask.filter(ImageFilter.GaussianBlur(3)).point(lambda p: int(p * 0.45))
    shadow.putalpha(Image.fromarray(np.roll(np.asarray(sm), (3, 5), (0, 1))))

    out = new.copy()
    out.alpha_composite(shadow)
    detail = var.copy()
    detail.putalpha(Image.fromarray(np.minimum(np.asarray(mask), np.asarray(var.getchannel('A')))))
    out.alpha_composite(detail)
    # Conserva la silueta del rombo del techo nuevo.
    out.putalpha(new.getchannel('A'))
    out.save(a.out)


if __name__ == '__main__':
    main()
