#!/usr/bin/env bash
# Выкатывает сервер «Оператора»: ./server/deploy.sh <ssh-хост> [udp-порт]
# Собирает Linux-бинарь, копирует его с Dockerfile и compose в /root/operator-server и поднимает контейнер.
# Порт должен быть открыт для UDP в файрволе хоста (например: ufw allow 27630/udp).
set -euo pipefail
HOST=${1:?"укажите ssh-хост: ./server/deploy.sh <хост> [порт]"}
PORT=${2:-27630}
cd "$(dirname "$0")/.."
./tools/build_server.sh
STAGE=$(mktemp -d)
cp build/server/operator-server.x86_64 server/Dockerfile server/docker-compose.yml "$STAGE/"
tar -czf - -C "$STAGE" . | ssh "$HOST" "mkdir -p /root/operator-server && tar -xzf - -C /root/operator-server"
ssh "$HOST" PORT="$PORT" bash -s <<'REMOTE'
set -euo pipefail
cd /root/operator-server
echo "OPERATOR_PORT=$PORT" > .env
docker compose up -d --build
sleep 2
docker compose logs --tail=5
REMOTE
echo "ok: сервер на $HOST, UDP $PORT"
