# Heddle Public API Guide

This guide will help you get started with the Heddle Public API.

## Authentication

All API requests require authentication using an API key. You can pass the API key in the `Authorization` header.

```bash
curl -H "Authorization: Bearer hd_live_ab12cd34_xxxxxxxxxxxxxxxxxxxxxxxx" \
  https://api.example.com/api/v1/workflows
```

Alternatively, you can use the `X-Heddle-API-Key` header:

```bash
curl -H "X-Heddle-API-Key: hd_live_ab12cd34_xxxxxxxxxxxxxxxxxxxxxxxx" \
  https://api.example.com/api/v1/workflows
```

## Examples

### 1. Create Workflow

```bash
curl -X POST https://api.example.com/api/v1/workflows \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "workflow": {
      "name": "Customer onboarding",
      "nodes": [
        {
          "id": "start",
          "type": "Start",
          "label": "Start",
          "controls": {},
          "position": { "x": 0, "y": 0 }
        },
        {
          "id": "output",
          "type": "Output",
          "label": "Output",
          "controls": {},
          "position": { "x": 200, "y": 0 }
        }
      ],
      "connections": [
        {
          "source": "start",
          "sourceOutput": "exec",
          "target": "output",
          "targetInput": "exec"
        }
      ]
    }
  }'
```

### 2. List Nodes

```bash
curl -X GET https://api.example.com/api/v1/nodes \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### 3. Create Execution

```bash
curl -X POST https://api.example.com/api/v1/workflows/123/executions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "trigger": "api",
      "variables": {
        "user_id": 42
      }
    }
  }'
```

### 4. Consult Execution

```bash
curl -X GET https://api.example.com/api/v1/workflows/123/executions/blue-orbit-route \
  -H "Authorization: Bearer YOUR_API_KEY"
```

### 5. Edit Together

`PUT /api/v1/workflows/{id}` makes the draft the graph you send, which takes back whatever someone else changed since you read it. To edit while others do, as Treadle does:

1. Follow the draft: `GET /api/v1/workflows/123/live` is a stream of server-sent events. The first, `ready`, has your `client`, whether you `can_edit`, and the `graph`. Each `change` brings the `graph` after it, `presence` says who is on the workflow, and `cursor` where their pointers are. Another `ready` means the stream lost track: take its graph as it is.
2. Change it with the graph you last had as `base`, so only what you changed is applied:

```bash
curl -X POST https://api.example.com/api/v1/workflows/123/changes \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"client": "CLIENT_FROM_READY", "base": {"nodes": [...]}, "graph": {"nodes": [...]}}'
```

The answer has the draft right after it, with everyone's changes. You can also send `ops`, the operations themselves (see `LiveChangeRequest` in the OpenAPI). Operations on something that is no longer there answer `409`, and nothing changes.

3. Say which nodes you point at, and others see them in your color:

```bash
curl -X POST https://api.example.com/api/v1/workflows/123/focus \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"client": "CLIENT_FROM_READY", "selected": ["2"], "editing": null}'
```

## Rate Limits

The API is rate limited to 100 requests per minute per API key. If you exceed this limit, you will receive a `429 Too Many Requests` response.

Live editing (`/live`, `/changes` and `/focus`) counts apart, up to 1200 requests per minute per API key, since a client sends each change as it is made.

## OpenAPI Documentation

For a full list of endpoints and schemas, refer to the [openapi.yaml](./openapi.yaml) file.
