#!/bin/bash
# Árboles, pinos y arbustos generados en Layer.ai (assets/art/source/props) ajustados a props/.
# Uso: PYTHON=/ruta/a/python-con-numpy tools/layer_art/props.sh  (OUT=dir para probar en otra carpeta)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ART=$HERE/../../assets/art
PY=${PYTHON:-python3}; R=$ART/source/props; OUT=${OUT:-$ART/props}
mkdir -p $OUT
F() { $PY -I $HERE/fit_prop.py "$@"; }
F $R/tree_a.png $OUT/tree_0@3.png --height 182 --max-width 150
F $R/tree_d.png $OUT/tree_1@3.png --height 186 --max-width 150
F $R/tree_b.png $OUT/tree_2@2.png --height 168 --max-width 145
F $R/bloom_a.png $OUT/tree_3@0.6.png --height 180 --max-width 140
F $R/bloom_b.png $OUT/tree_4@0.6.png --height 172 --max-width 140
F $R/pine_a.png $OUT/pine_0@3.png --height 186 --max-width 125 --shadow 0.85
F $R/pine_b.png $OUT/pine_1@2.png --height 176 --max-width 125 --shadow 0.85
F $R/pine_c.png $OUT/pine_2@2.png --height 166 --max-width 120 --shadow 0.85
F $R/bush_b.png $OUT/bush_0@3.png --height 90 --max-width 126 --shadow 0.9 --foot 0.15
F $R/bush_d.png $OUT/bush_1@2.png --height 86 --max-width 130 --shadow 0.9 --foot 0.15
F $R/bush_c.png $OUT/bush_2@2.png --height 84 --max-width 116 --shadow 0.9 --foot 0.15
echo "props listos en $OUT"
