# Uso: isogrid.py out.png N tile1.png [tile2.png ...]  -> mosaico NxN de rombos 256x128 (variantes al azar)
import sys, random
from PIL import Image
out, n, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
tiles = [Image.open(f).convert('RGBA').resize((256,128), Image.LANCZOS) for f in files]
W, H = 256, 128
canvas = Image.new('RGBA', (W*n, H*n + H), (40,40,40,255))
random.seed(1)
for y in range(n):
    for x in range(n):
        px = (x - y) * W//2 + (n-1)*W//2
        py = (x + y) * H//2
        t = random.choice(tiles)
        canvas.alpha_composite(t, (px, py))
canvas.save(out)
