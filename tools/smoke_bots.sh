#!/usr/bin/env bash
# Смоук-матч по сети: сервер + 2 клиента-робота + 6 серверных ботов = 8 участников.
# Проверяет: лобби (создание, вход по коду, готовность, чат, старт), матч до победителя,
# отсутствие ошибок скриптов, тик сервера в бюджете. Использование: tools/smoke_bots.sh [порт]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
PORT=${1:-27731}
OUT=$(mktemp -d)
CODE="$OUT/code"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

"$GODOT" --headless --path . -- --server --port="$PORT" --exit-when-empty >"$OUT/server.log" 2>&1 &
SRV=$!
sleep 2
export OPERATOR_SERVER="127.0.0.1:$PORT"
"$GODOT" --headless --path . -s res://tools/robot_client.gd -- --name=Хост --create --slots=8 --lives=${LIVES:-2} --humans=2 --code-file="$CODE" >"$OUT/a.log" 2>&1 &
A=$!
sleep 2
"$GODOT" --headless --path . -s res://tools/robot_client.gd -- --name=Гость --code-file="$CODE" >"$OUT/b.log" 2>&1 &
B=$!
wait $A; RA=$?
wait $B; RB=$?
sleep 2
kill $SRV 2>/dev/null; wait $SRV 2>/dev/null

echo "== сервер"; grep -v "^\s*$" "$OUT/server.log" | tail -n 8
echo "== хост";   grep -E "МАТЧ|^\s+[0-9]\.|ошибка|матч начался|offline|таймаут" "$OUT/a.log"
echo "== гость";  grep -E "МАТЧ|ошибка|матч начался|чат|offline|таймаут" "$OUT/b.log"
ERRS=$(cat "$OUT"/*.log | grep -v "resources still in use" | grep -cE "SCRIPT ERROR|Parse Error|ERROR:|WARNING: Sending" || true)
FAIL=0
[ "$RA" = 0 ] || { echo "хост завершился с кодом $RA"; FAIL=1; }
[ "$RB" = 0 ] || { echo "гость завершился с кодом $RB"; FAIL=1; }
grep -q "МАТЧ ОКОНЧЕН" "$OUT/a.log" || { echo "матч не завершился"; FAIL=1; }
[ "$ERRS" = 0 ] || { echo "ошибок в логах: $ERRS"; cat "$OUT"/*.log | grep -E "SCRIPT ERROR|ERROR:" -A2 | head -20; FAIL=1; }
echo "логи: $OUT"
if [ $FAIL = 0 ]; then echo "СМОУК: ОК"; else echo "СМОУК: ПРОВАЛ"; fi
exit $FAIL
