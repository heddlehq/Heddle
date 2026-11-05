set -euo pipefail
base=http://127.0.0.1:18080/api/v1
json='content-type: application/json'
signup="$(curl -fsS -X POST $base/authentication/sign-up -H "$json" -d '{"email":"bench@example.com","password":"Bench-Password-1234","firstName":"Bench","lastName":"Mark","trackEvents":false,"newsLetter":false}')"
token="$(echo "$signup" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
project="$(echo "$signup" | python3 -c 'import json,sys; print(json.load(sys.stdin)["projectId"])')"
auth="Authorization: Bearer $token"
# Pieces sync from the registry after boot, so they take a moment to exist.
piece_version() {
  for _ in $(seq 1 120); do
    if body="$(curl -fsS "$base/pieces/@activepieces/$1" -H "$auth" 2>/dev/null)"; then
      echo "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])'
      return 0
    fi
    sleep 2
  done
  curl -sS "$base/pieces?limit=3" -H "$auth" | head -c 600 >&2
  return 1
}
http_version="$(piece_version piece-http)"
webhook_version="$(piece_version piece-webhook)"
flow="$(curl -fsS -X POST $base/flows -H "$auth" -H "$json" -d "{\"displayName\":\"bench\",\"projectId\":\"$project\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
python3 - "$http_version" "$webhook_version" > /tmp/ap-flow.json <<'PY'
import json, os, sys
http_version, webhook_version = sys.argv[1:3]
url = "http://host.docker.internal:9099/hit" + ("?id={{trigger['body']['id']}}" if os.environ.get("CRASH") else "")
print(json.dumps({"type": "IMPORT_FLOW", "request": {"displayName": "bench", "schemaVersion": None, "trigger": {
  "name": "trigger", "displayName": "Webhook", "type": "PIECE_TRIGGER", "valid": True,
  "settings": {"pieceName": "@activepieces/piece-webhook", "pieceVersion": webhook_version, "triggerName": "catch_webhook",
               "input": {"authType": "none", "authFields": {}}, "propertySettings": {}},
  "nextAction": {"name": "step_1", "displayName": "HTTP", "type": "PIECE", "valid": True, "skip": False,
    "settings": {"pieceName": "@activepieces/piece-http", "pieceVersion": http_version, "actionName": "send_request",
      "input": {"method": "POST", "url": url, "headers": {}, "queryParams": {},
                "body_type": "none", "body": {}, "response_is_binary": False, "use_proxy": False, "authType": "NONE", "authFields": {}},
      "propertySettings": {}, "errorHandlingOptions": {}}}}}}))
PY
curl -fsS -X POST "$base/flows/$flow" -H "$auth" -H "$json" -d @/tmp/ap-flow.json >&2
curl -fsS -X POST "$base/flows/$flow" -H "$auth" -H "$json" -d '{"type":"LOCK_AND_PUBLISH","request":{}}' >&2
curl -fsS -X POST "$base/flows/$flow" -H "$auth" -H "$json" -d '{"type":"CHANGE_STATUS","request":{"status":"ENABLED"}}' >&2
sleep 5
echo "http://127.0.0.1:18080/api/v1/webhooks/$flow"
