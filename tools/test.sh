#!/usr/bin/env bash
# Headless-тесты: обновляет кэш классов и запускает tests/run_tests.gd.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@"
