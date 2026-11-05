set -euo pipefail
base=http://127.0.0.1:18080/api
token="$(curl -fsS -X POST $base/auth/login -H 'content-type: application/json' -d '{"email":"admin@windmill.dev","password":"changeme"}')"
auth="Authorization: Bearer $token"
curl -fsS -X POST $base/workspaces/create -H "$auth" -H 'content-type: application/json' -d '{"id":"bench","name":"bench"}' >&2
python3 - > /tmp/windmill-script.json <<'PY'
import json, os
crash = os.environ.get("CRASH")
content = (
  "export async function main(id: string) {\n  await fetch('http://host.docker.internal:9099/hit?id=' + id, { method: 'POST', body: '{}' });\n}\n"
  if crash else
  "export async function main() {\n  await fetch('http://host.docker.internal:9099/hit', { method: 'POST', body: '{}' });\n}\n"
)
properties = {"id": {"type": "string"}} if crash else {}
print(json.dumps({
  "path": "u/admin/bench", "summary": "bench", "description": "", "language": "nativets",
  "content": content,
  "schema": {"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "properties": properties, "required": []},
}))
PY
curl -fsS -X POST $base/w/bench/scripts/create -H "$auth" -H 'content-type: application/json' -d @/tmp/windmill-script.json >&2
sleep 5
echo "http://127.0.0.1:18080/api/w/bench/jobs/run/p/u/admin/bench?token=$token"
