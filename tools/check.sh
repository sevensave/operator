#!/usr/bin/env bash
# Проверка компиляции всех скриптов.
cd "$(dirname "$0")/.."
fail=0
for f in $(git ls-files --others --cached --exclude-standard '*.gd'); do
  out=$(godot --headless --path . --check-only -s "res://$f" 2>&1 | grep -v "Identifier not found: Settings" | grep -E "SCRIPT ERROR|Parse Error" -A1 | grep -v "^--" | grep -B1 -A0 "at:" | head -6)
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
exit $fail
