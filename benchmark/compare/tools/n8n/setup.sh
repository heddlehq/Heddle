set -euo pipefail
$COMPOSE cp workflow.json n8n:/tmp/workflow.json
$COMPOSE exec -T n8n n8n import:workflow --input=/tmp/workflow.json >&2
$COMPOSE exec -T n8n n8n publish:workflow --id=bench00000000001 >&2 ||
  $COMPOSE exec -T n8n n8n update:workflow --id=bench00000000001 --active=true >&2
$COMPOSE restart n8n >&2
for _ in $(seq 1 120); do
  curl -fs http://127.0.0.1:18080/healthz >/dev/null && break
  sleep 1
done
sleep 5
echo "http://127.0.0.1:18080/webhook/bench"
