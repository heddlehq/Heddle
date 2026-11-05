set -euo pipefail
curl -fsS -u 'bench@example.com:BenchPass1234' -X POST http://127.0.0.1:18080/api/v1/main/flows -H 'content-type: application/x-yaml' --data-binary @flow.yml >&2
sleep 3
echo "http://127.0.0.1:18080/api/v1/main/executions/webhook/bench/bench/benchkey"
