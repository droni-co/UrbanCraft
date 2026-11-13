#!/bin/bash
# Techos con texturas de Layer.ai (teja de barro y concreto) y los detalles de los techos procedurales.
# Uso: PYTHON=/ruta/a/python-con-numpy tools/layer_art/roofs.sh  (OUT=dir para probar en otra carpeta)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ART=$HERE/../../assets/art
PY=${PYTHON:-python3}
T=$ART/source/textures
R=$ART/source/roof_details
OUT=${OUT:-$ART/tiles/ground}
mkdir -p $OUT

# roof <estilo> <textura> <pesos de las variantes 0 1 2...>
roof() {
	local style=$1 tex=$2; shift 2
	local w0=$1; shift
	$PY -I $HERE/iso_project.py "$OUT/${style}_0@$w0.png" "$tex"
	local i=1
	for w in "$@"; do
		$PY -I $HERE/transplant.py "$R/${style}_0.png" "$R/${style}_$i.png" "$OUT/${style}_0@$w0.png" "$OUT/${style}_$i@$w.png"
		i=$((i + 1))
	done
}

roof building $T/roof_clay.png 60 0.8 0.8
roof roof_brick $T/roof_clay_red.png 20 0.5 0.4
roof roof_concrete $T/roof_concrete.png 20 0.6 0.5

# Texturas que usa el shader de tejados a dos aguas en el juego (scripts/world/roof_styles.gd).
TILES=${TILES:-$ART/../tiles}
$PY -I -c "
import sys
from PIL import Image
for src, dst in zip(sys.argv[1::2], sys.argv[2::2]):
    Image.open(src).convert('RGB').resize((512, 512), Image.LANCZOS).save(dst, optimize=True)
" $T/roof_clay.png $TILES/roof_clay.png $T/roof_clay_red.png $TILES/roof_clay_red.png
