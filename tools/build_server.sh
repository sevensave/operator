#!/usr/bin/env bash
# Сборка выделенного сервера под Linux x86_64: build/server/operator-server.x86_64 (pck внутри).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
rm -rf build/server && mkdir -p build/server
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Linux Server" build/server/operator-server.x86_64
ls -la build/server
