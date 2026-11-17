#!/bin/bash
# Arma la hoja de un personaje desde su GLB riggeado de Meshy.
#
#   tools/characters/build.sh <id> <personaje.glb> <dir_donantes> <bici.glb> <salida_dir>
#
# <dir_donantes> tiene un GLB por animación (idle, walk, wave, craft, interact,
# attack, defend), todos del mismo esqueleto de Meshy (ver manifest.json).
# Deja <salida_dir>/<id>.png (24x16 cuadros a x3) y GIFs en preview_<id>/.
# HEAD=1.15 achica la cabeza si el pelo o un sombrero se salen por arriba.
set -e
N=$1; G=$(realpath "$2"); D=$(realpath "$3"); BIKE=$(realpath "$4"); OUT=$(realpath "$5")
HERE=$(cd "$(dirname "$0")" && pwd)
F=$OUT/frames_$N
rm -rf "$F"; mkdir -p "$F"
COMMON="--toon --head=${HEAD:-1.25} --bright=${BRIGHT:-0.34} --k=3"
r() {
	timeout 400 godot --path "$HERE/render" -s res://render.gd -- --glb="$G" --out="$F" $COMMON "$@" 2>&1 \
		| grep -E "SCRIPT ERROR" | head -3 || true
}
# Qué tramo de cada animación de Meshy se usa (fracciones de su duración).
r --donor="$D/idle.glb" --prefix=idle --times=0,0.06,0.12,0.06
r --donor="$D/walk.glb" --prefix=walk --frames=8
r --donor="$D/wave.glb" --prefix=wave --times=0.28,0.34,0.40,0.34
r --bike="$BIKE" --bike_scale=1.45 --prefix=bike --frames=4
r --donor="$D/craft.glb" --prefix=craft --times=0.08,0.16,0.24,0.16
r --donor="$D/interact.glb" --prefix=interact --times=0.10,0.20,0.30,0.20
r --donor="$D/attack.glb" --prefix=attack --times=0.19,0.31,0.44,0.56
r --donor="$D/defend.glb" --prefix=defend --times=0.06,0.12,0.20,0.12
python3 "$HERE/pack.py" "$F" "$OUT/$N.png" "$OUT/preview_$N"
