set -euo pipefail
if [ -n "${CRASH:-}" ]; then
  sed 's#uri: http://host.docker.internal:9099/hit#uri: "http://host.docker.internal:9099/hit?id={{ trigger.body.id }}"#' flow.yml > /tmp/kestra-flow.yml
else
  cp flow.yml /tmp/kestra-flow.yml
fi
curl -fsS -u 'bench@example.com:BenchPass1234' -X POST http://127.0.0.1:18080/api/v1/main/flows -H 'content-type: application/x-yaml' --data-binary @/tmp/kestra-flow.yml >&2
sleep 3
echo "http://127.0.0.1:18080/api/v1/main/executions/webhook/bench/bench/benchkey"
