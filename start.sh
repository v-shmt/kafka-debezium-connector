#!/usr/bin/env bash
# Automates the CDC demo from note.pdf (PostgreSQL -> Debezium -> Kafka).
# Usage: ./start.sh        build + start stack, register connector, open psql and kcat terminals
#        ./start.sh down   stop the stack
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
DIR="$(pwd)"
PROJECT="$(basename "$DIR" | tr '[:upper:]' '[:lower:]')"
NETWORK="${PROJECT}_default"
POSTGRES_CONTAINER="${PROJECT}-postgres-1"
CONNECT_URL="http://127.0.0.1:8083"
CONNECTOR="exampledb-connector"

if [[ "${1:-}" == "down" ]]; then
  docker-compose down
  exit 0
fi

wait_for() { # description, command...
  local desc="$1"; shift
  echo "Waiting for ${desc}..."
  for _ in $(seq 1 90); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  echo "Timed out waiting for ${desc}" >&2
  exit 1
}

psql_exec() { docker exec -i "$POSTGRES_CONTAINER" psql -U docker -d exampledb -v ON_ERROR_STOP=1 "$@"; }

echo "==> Building and starting services"
docker-compose build debezium
docker-compose up -d

wait_for "PostgreSQL" docker exec "$POSTGRES_CONTAINER" pg_isready -U docker -d exampledb
wait_for "Kafka Connect" curl -sf --max-time 5 "${CONNECT_URL}/connectors"

echo "==> Creating and seeding employees table"
psql_exec <<'SQL'
CREATE TABLE IF NOT EXISTS employees (id INTEGER PRIMARY KEY, name VARCHAR);
ALTER TABLE employees REPLICA IDENTITY FULL;
INSERT INTO employees VALUES (1, 'Bob') ON CONFLICT DO NOTHING;
INSERT INTO employees VALUES (2, 'Maria') ON CONFLICT DO NOTHING;
SQL

echo "==> Registering connector"
if curl -sf --max-time 5 "${CONNECT_URL}/connectors/${CONNECTOR}" >/dev/null; then
  echo "Connector already registered"
else
  curl -sf --max-time 30 -X POST \
    -H "Accept:application/json" -H "Content-Type:application/json" \
    "${CONNECT_URL}/connectors/" --data "@debezium.json" >/dev/null
fi

connector_running() {
  curl -sf --max-time 5 "${CONNECT_URL}/connectors/${CONNECTOR}/status" |
    python3 -c 'import json,sys; s=json.load(sys.stdin); sys.exit(0 if s["connector"]["state"]=="RUNNING" and s["tasks"] and all(t["state"]=="RUNNING" for t in s["tasks"]) else 1)'
}
wait_for "connector and tasks to be RUNNING" connector_running
curl -s "${CONNECT_URL}/connectors/${CONNECTOR}/status" | python3 -m json.tool

echo "==> Opening terminals"
PSQL_CMD="docker exec -it ${POSTGRES_CONTAINER} psql -U docker -d exampledb"
KCAT_CMD="docker run --rm --tty --network ${NETWORK} confluentinc/cp-kcat kcat -b kafka:9092 -C -s key=s -s value=avro -r http://schema-registry:8081 -t postgres.public.employees"

osascript <<EOF
tell application "Terminal"
  activate
  do script "clear; ${PSQL_CMD}"
  do script "clear; echo 'kcat consumer on postgres.public.employees'; ${KCAT_CMD}"
end tell
EOF

echo "Done. Run './start.sh down' to stop the stack."
