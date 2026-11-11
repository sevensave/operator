#!/usr/bin/env bash
# Сборка Windows: dist/Operator-<версия>-win-x64.zip, в корне архива Operator.exe и Operator.pck.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
VER=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
rm -rf build/win && mkdir -p build/win dist
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows" build/win/Operator.exe
test -f build/win/Operator.exe && test -f build/win/Operator.pck
ZIP="dist/Operator-$VER-win-x64.zip"
rm -f "$ZIP"
if command -v zip >/dev/null; then
  (cd build/win && zip -q -9 "../../$ZIP" Operator.exe Operator.pck)
else
  powershell -NoProfile -Command "Compress-Archive -Path build/win/Operator.exe,build/win/Operator.pck -DestinationPath '$ZIP' -Force"
fi
echo "$ZIP"
