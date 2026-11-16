import sys, numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi
src, art = sys.argv[1], sys.argv[2]
im = np.array(Image.open(src).convert('RGB')).astype(int)
mn, mx = im.min(2), im.max(2)
bg = (mn >= 226) & (mx - mn <= 8)
lab, n = ndi.label(bg)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
remove = np.isin(lab, list(border))
# huecos encerrados (entre brazos de la farola, aspas…): tienen los dos tonos del ajedrez
sizes = ndi.sum(bg, lab, range(1, n + 1))
for i, size in enumerate(sizes, 1):
    if i in border or size < 150: continue
    m = lab == i
    v = mn[m]
    light, dark = (v >= 247).mean(), (v <= 241).mean()
    if light > 0.2 and dark > 0.2: remove |= m
remove = ndi.binary_dilation(remove, iterations=2)  # se come el halo claro del borde
alpha = Image.fromarray((~remove * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(0.8))
rgba = Image.fromarray(im.astype('uint8')).convert('RGBA'); rgba.putalpha(alpha)
names = ['seto','cerca','muro','columna','palmera','farola','arco','fuente','reloj','estandarte','estatua','molino','kiosco','arbol_dorado','obelisco','trono']
a = np.array(alpha) > 40
C = 512
for k, name in enumerate(names):
    r, c = divmod(k, 4)
    # el objeto es el componente opaco con más área dentro de la celda (los vecinos no se cuelan)
    cell = a[r*C:(r+1)*C, c*C:(c+1)*C]
    cl, cn = ndi.label(cell)
    big = 1 + int(np.argmax(ndi.sum(cell, cl, range(1, cn + 1))))
    by, bx = np.where(cl == big)
    keep = np.zeros_like(cell)
    for i in range(1, cn + 1):  # motas sueltas fuera del objeto: fuera
        yy, xx = np.where(cl == i)
        if i == big or (bx.min() <= xx.mean() <= bx.max() and by.min() <= yy.mean() <= by.max()):
            keep |= cl == i
    ys, xs = np.where(keep)
    box = (c*C + xs.min(), r*C + ys.min(), c*C + xs.max() + 1, r*C + ys.max() + 1)
    tile = rgba.crop((c*C, r*C, (c+1)*C, (r+1)*C))
    ta = np.array(tile); ta[..., 3] = np.where(keep, ta[..., 3], 0)
    sp = Image.fromarray(ta).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    for folder, size, pad, bottom in [('objects', 192, 6, True), ('items', 96, 4, False)]:
        s = (size - 2*pad) / max(sp.size)
        if bottom: s = min((size - 2*pad) / sp.size[1], (size - 28) / sp.size[0])
        w, h = max(1, round(sp.size[0]*s)), max(1, round(sp.size[1]*s))
        out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        small = sp.resize((w, h), Image.LANCZOS)
        out.alpha_composite(small, ((size - w)//2, size - h - 2 if bottom else (size - h)//2))
        out.save(f'{art}/{folder}/{name}.png')
    print(name, sp.size)
