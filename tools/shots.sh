#!/usr/bin/env bash
# Кадры для проверки графики: 5 архетипов × разное время суток/биом/осадки,
# в FPV и в виде сзади без фильтров (--chase --clean). Печатает FPS и draw calls.
# Использование: tools/shots.sh <папка> [качество 0..2]
#   SEEDS="70 111" — свои сиды, MODES="fpv" — только FPV, AT=14 — секунда кадра.
#   DRIVER=vulkan (по умолчанию): на macOS Metal не отдаёт время GPU, а FPS упирается в экран;
#   «gpu ms» — среднее время кадра GPU за 3 с до снимка (1600×900).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${1:?папка для кадров}
Q=${2:-1}
AT=${AT:-14}
DRIVER=${DRIVER:-vulkan}
# Сид → архетип (сид mod 5) и косметика (MapPreset._roll_look):
#  70 долина/день/лето    111 плато/ночь        52 хребет/туман     38 каньон/ночь/зима/снег
#  114 холмы/пасмурно/дождь  40 долина/закат/степь  47 хребет/рассвет  68 каньон/день
#  20 долина/зима/снег   6 плато/закат/осень
SEEDS=${SEEDS:-"70 111 52 38 114 40 47 68 20 6"}
MODES=${MODES:-"fpv chase"}
mkdir -p "$OUT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for s in $SEEDS; do
  for m in $MODES; do
    extra=()
    [ "$m" = chase ] && extra=(--chase --clean)
    f="$OUT/s${s}_q${Q}_${m}.png"
    line=$("$GODOT" --path . --rendering-driver "$DRIVER" -- --training --autopilot --novsync --seed="$s" --quality="$Q" \
      --shot="$f" --shot-at="$AT" ${extra[@]+"${extra[@]}"} 2>&1 | grep -E "screenshot:|SCRIPT ERROR|ERROR:" | head -3)
    echo "s$s q$Q $m: ${line#screenshot: }"
  done
done
