#!/bin/bash
# Variantes de suelo hechas con texturas y decals generados en Layer.ai (ver assets/art/README.md).
# Uso: PYTHON=/ruta/a/python-con-numpy tools/layer_art/variants.sh  (OUT=dir para probar en otra carpeta)
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ART=$HERE/../../assets/art
PY=${PYTHON:-python3}; P="$PY -I $HERE/iso_project.py"
G=$ART/tiles/ground
D=$ART/source/decals
OUT=${OUT:-$G}
mkdir -p $OUT
st() { local out=$1 base=$2; shift 2; $P "$OUT/$out" "$base" --over "$@"; }

# --- pasto ---
B=$G/grass_0@6.png
st grass_4@0.8.png $B --decal $D/clover_a.png:0.62:0.38:0.30 --sprite $D/daisy_a.png:0.42:0.55:40
st grass_5@0.8.png $B --sprite $D/dandelion_a.png:0.4:0.45:36 --sprite $D/dandelion_b.png:0.62:0.6:30 --sprite $D/tuft_a.png:0.55:0.3:34
st grass_6@0.7.png $B --decal $D/pebbles_a.png:0.35:0.65:0.22 --sprite $D/violet_a.png:0.6:0.45:38
st grass_7@0.15.png $B --decal $D/mushrooms_a.png:0.5:0.5:0.32
st grass_8@0.7.png $B --decal $D/leaves_b.png:0.55:0.45:0.34 --sprite $D/tuft_b.png:0.35:0.62:34
st grass_9@0.6.png $B --sprite $D/drygrass_a.png:0.5:0.55:46 --sprite $D/tuft_a.png:0.68:0.4:28
st grass_10@0.6.png $B --sprite $D/daisy_b.png:0.38:0.42:34 --sprite $D/violet_b.png:0.62:0.62:32 --decal $D/clover_b.png:0.6:0.35:0.22
# --- pasto oscuro ---
B=$G/grass_dark_0@5.png
st grass_dark_3@0.8.png $B --decal $D/leaves_a.png:0.5:0.5:0.36
st grass_dark_4@0.2.png $B --decal $D/mushrooms_b.png:0.45:0.55:0.30
st grass_dark_5@0.8.png $B --decal $D/clover_a.png:0.6:0.4:0.26 --sprite $D/tuft_b.png:0.4:0.6:36
st grass_dark_6@0.6.png $B --decal $D/pebbles_b.png:0.5:0.5:0.26 --sprite $D/tuft_a.png:0.62:0.62:28
# --- tierra ---
B=$G/dirt_0@5.png
st dirt_3@0.8.png $B --decal $D/pebbles_a.png:0.5:0.5:0.28
st dirt_4@0.5.png $B --decal $D/puddle_a.png:0.5:0.5:0.38
st dirt_5@0.7.png $B --decal $D/leaves_s_a.png:0.45:0.5:0.30 --sprite $D/tuft_a.png:0.62:0.38:28
st dirt_6@0.7.png $B --decal $D/gravel_b.png:0.5:0.5:0.38
# --- asfalto ---
B=$G/asphalt_0@12.png
st asphalt_3@0.6.png $B --decal $D/manhole_b.png:0.5:0.5:0.26
st asphalt_4@0.5.png $B --decal $D/drain_b.png:0.5:0.5:0.26
st asphalt_5@0.8.png $B --decal $D/patch_a.png:0.5:0.5:0.36
st asphalt_6@1.0.png $B --decal $D/cracks_a.png:0.5:0.5:0.40
st asphalt_7@0.5.png $B --decal $D/oil_a.png:0.5:0.5:0.28
st asphalt_8@0.4.png $B --decal $D/puddle_b.png:0.5:0.5:0.38
st asphalt_9@0.6.png $B --decal $D/gravel_a.png:0.5:0.5:0.36 --decal $D/leaves_s_b.png:0.4:0.6:0.22
# --- andén: base nueva de Layer (pave_b) ---
$P "$OUT/pavement_0@10.png" $ART/source/textures/pavement.png
B="$OUT/pavement_0@10.png"
st pavement_1@1.5.png $B --decal $D/leaves_s_a.png:0.5:0.5:0.30
st pavement_2@0.8.png $B --decal $D/drain_a.png:0.5:0.5:0.22
st pavement_3@0.8.png $B --decal $D/gravel_b.png:0.5:0.5:0.30
st pavement_4@0.5.png $B --decal $D/puddle_a.png:0.5:0.5:0.32
st pavement_5@0.6.png $B --decal $D/manhole_a.png:0.5:0.5:0.24
st pavement_6@0.6.png $B --decal $D/leaves_s_b.png:0.4:0.55:0.24 --sprite $D/tuft_a.png:0.6:0.4:22
echo "$(ls $OUT | wc -l) tiles en $OUT"
