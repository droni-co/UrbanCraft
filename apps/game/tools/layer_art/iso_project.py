"""Proyecta texturas cuadradas sin costura a rombos isométricos 256x128.

iso_project.py out.png base.png [--center other.png] [--decal d.png:u:v:scale ...] [--seed N]
- base: textura sin costura; un rombo = un período exacto -> los bordes encajan con cualquier vecino.
- center: otra textura que se mezcla solo en el interior (máscara suave), para variantes.
- decal: PNG con alpha estampado en coordenadas de textura (u,v en 0..1), escala relativa al tile.
"""
import sys, argparse
import numpy as np
from PIL import Image

W, H, SS, BLEED = 256, 128, 3, 3.2  # bleed en px reales fuera del rombo (como el generador)

def load_tex(p, n=1024):
    return np.asarray(Image.open(p).convert('RGBA').resize((n, n), Image.LANCZOS)).astype(np.float32) / 255

def sample(tex, u, v):
    n = tex.shape[0]
    x = (u % 1.0) * n; y = (v % 1.0) * n
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]; fy = (y - y0)[..., None]
    x0 %= n; y0 %= n; x1 = (x0 + 1) % n; y1 = (y0 + 1) % n
    return (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x1] * fx * (1 - fy)
            + tex[y1, x0] * (1 - fx) * fy + tex[y1, x1] * fx * fy)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('base')
    ap.add_argument('--over', action='store_true', help='base es un tile iso 256x128 ya hecho: solo se estampan decals')
    ap.add_argument('--margin', type=float, default=0.06, help='distancia minima al borde (u/v) de los decals')
    ap.add_argument('--center'); ap.add_argument('--center-size', type=float, default=0.32)
    ap.add_argument('--decal', action='append', default=[])
    ap.add_argument('--sprite', action='append', default=[], help='png:u:v:ancho_px (de pie, sin proyectar)')
    ap.add_argument('--tint', default=None, help='r,g,b multiplicador')
    a = ap.parse_args()
    w, h = W * SS, H * SS
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    x = (xs + 0.5) / SS; y = (ys + 0.5) / SS
    # rombo: arriba (128,0) derecha (256,64) abajo (128,128) izquierda (0,64)
    u = ((x - 128) / 128 + y / 64) / 2
    v = (y / 64 - (x - 128) / 128) / 2
    if a.over:
        img = np.zeros((h, w, 4), np.float32)  # capa de decals (premultiplicada)
    else:
        tex = load_tex(a.base)
        img = sample(tex, u, v)
    # distancia al borde del rombo en coordenadas de textura (0 en el borde, 0.5 en el centro)
    d = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    if a.center:
        t2 = load_tex(a.center)
        c = sample(t2, u + 0.37, v + 0.61)
        m = np.clip((d - 0.08) / a.center_size, 0, 1)
        m = (m * m * (3 - 2 * m))[..., None]
        img = img * (1 - m) + c * m
    for spec in a.decal:
        p, du, dv, sc = spec.split(':')
        dimg = Image.open(p).convert('RGBA')
        # el decal se dibuja en espacio de textura (cuadrado) para que se proyecte como el suelo
        n = 1024; size = int(float(sc) * n)
        dimg = dimg.resize((size, max(1, int(size * dimg.height / dimg.width))), Image.LANCZOS)
        layer = Image.new('RGBA', (n, n), (0, 0, 0, 0))
        layer.alpha_composite(dimg, (int(float(du) * n - dimg.width / 2), int(float(dv) * n - dimg.height / 2)))
        lt = np.asarray(layer).astype(np.float32) / 255
        s = sample(lt, u, v)
        fade = np.clip((d - a.margin) / 0.03, 0, 1)[..., None]
        al = s[..., 3:4] * fade
        if a.over:
            img[..., :3] = img[..., :3] * (1 - al) + s[..., :3] * al
            img[..., 3:4] = img[..., 3:4] * (1 - al) + al
        else:
            img[..., :3] = img[..., :3] * (1 - al) + s[..., :3] * al
    if a.tint:
        img[..., :3] *= np.array([float(t) for t in a.tint.split(',')], dtype=np.float32)
    # alpha: rombo + bleed
    px = np.abs(x - 128) / 128 + np.abs(y - 64) / 64  # 1 en el borde
    edge_px = (1 - px) * 64 / np.sqrt(1 + 0.25)  # aprox. distancia perpendicular en px
    alpha = np.clip(edge_px + BLEED + 0.5, 0, 1)
    if a.over:
        # despremultiplica tras reducir para no oscurecer los bordes de los decals
        small = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((W, H), Image.BOX)
        arr = np.asarray(small).astype(np.float32) / 255
        al = arr[..., 3:4]
        rgb = np.where(al > 1e-3, arr[..., :3] / np.maximum(al, 1e-3), 0)
        layer = Image.fromarray((np.clip(np.concatenate([rgb, al], -1), 0, 1) * 255).astype(np.uint8), 'RGBA')
        base = Image.open(a.base).convert('RGBA')
        a_base = base.getchannel('A')
        base.alpha_composite(layer)
        for spec in a.sprite:
            p, su, sv, sw = spec.split(':')
            sp = Image.open(p).convert('RGBA')
            sw = int(float(sw)); sh = max(1, round(sp.height * sw / sp.width))
            sp = sp.resize((sw, sh), Image.LANCZOS)
            su, sv = float(su), float(sv)
            bx = 128 + 128 * (su - sv); by = 64 * (su + sv)
            base.alpha_composite(sp, (int(round(bx - sw / 2)), int(round(by - sh * 0.85))))
        base.putalpha(a_base)
        base.save(a.out)
        return
    img[..., 3] = alpha
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((W, H), Image.LANCZOS)
    out.save(a.out)

main()
