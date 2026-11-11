#!/usr/bin/env bash
# Заметки к релизу из CHANGELOG.md: раздел «## X.Y.Z» для игроков, под чертой — как установить.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?тег vX.Y.Z}
VER=${TAG#v}
BODY=$(awk -v v="## $VER" '$0==v {on=1; next} /^## / && on {exit} on' CHANGELOG.md)
if [ -z "$(echo "$BODY" | tr -d '[:space:]')" ]; then
  echo "В CHANGELOG.md нет раздела «## $VER»" >&2
  exit 1
fi
echo "$BODY" | sed -e '/./,$!d'
cat <<NOTE

---

Проще всего установить через лаунчер Sevensave. Вручную: скачайте \`Operator-$VER-win-x64.zip\`, распакуйте и запустите \`Operator.exe\`.
NOTE
