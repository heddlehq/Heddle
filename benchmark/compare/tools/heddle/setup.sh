set -euo pipefail
$COMPOSE cp setup.exs ui:/tmp/setup.exs
output="$($COMPOSE exec -T ui /app/ui/bin/heddle_ui rpc 'Code.eval_file("/tmp/setup.exs")')"
echo "$output" >&2
id="$(echo "$output" | grep -oE 'FLOW=[0-9]+' | cut -d= -f2)"
echo "http://127.0.0.1:18080/api/flows/$id/webhook/bench"
