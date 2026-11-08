---
title: REST API
description: Create, change, run, publish and inspect flows over HTTP, with an API key.
sidebar:
  order: 1
---

Everything the editor does to a flow, the API does too. The full specification is in [openapi.yaml](/docs/openapi.yaml), which tools like Postman, Insomnia and code generators read.

## Authentication

Create a key in **API keys**. Send it in every request:

```bash
curl -H "Authorization: Bearer hd_live_ab12cd34_..." https://your-heddle/api/v1/workflows
```

`X-Heddle-API-Key: <key>` works too, for tools that can't set `Authorization`.

A key belongs to a person and to one workspace. It reaches only that workspace's flows, and does no more than its owner's role there, at the time of each request:

| Role | Can |
| --- | --- |
| `viewer` | Read flows, runs and nodes |
| `operator` | Also run flows |
| `editor` | Also create, change, delete and publish flows, and use the agent |
| `admin` | Also manage the workspace, its members and every key in it |

Keys also have **scopes**, picked when you create them: `workflows:read`, `workflows:write`, `workflows:delete`, `executions:read`, `executions:write` and `nodes:read`. A request needs both the scope and the role.

## Answers

| Status | Means |
| --- | --- |
| `200`, `201`, `202` | Done, created, queued |
| `401` | No key, a wrong one, or its owner left the workspace |
| `403` | The scope or the role doesn't allow it |
| `404` | It doesn't exist, or it's in another workspace |
| `409` | The flow was never published, and the call needs a published version; or, for `/changes`, operations on something no longer there |
| `422` | What was sent isn't valid: `errors` says what |
| `429` | More than 100 requests in a minute with this key (1200 for live editing) |

## Endpoints

### Flows

| Method and path | Does |
| --- | --- |
| `GET /api/v1/workflows` | List flows |
| `POST /api/v1/workflows` | Create a flow |
| `GET /api/v1/workflows/{id}` | Read a flow, with its nodes and connections |
| `PATCH /api/v1/workflows/{id}` | Change some fields, like the name or the nodes |
| `PUT /api/v1/workflows/{id}` | Replace the fields sent |
| `DELETE /api/v1/workflows/{id}` | Delete a flow |

Changing nodes or connections changes the draft, and shows on every open canvas at once.

```bash
curl -X POST https://your-heddle/api/v1/workflows \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "workflow": {
      "name": "Customer onboarding",
      "nodes": [
        {"id": "start", "type": "Start", "label": "Start", "controls": {}},
        {"id": "done", "type": "Output", "label": "Done", "controls": {}}
      ],
      "connections": [
        {"source": "start", "sourceOutput": "exec", "target": "done", "targetInput": "exec"}
      ]
    }
  }'
```

A node needs an `id`, a `type` from the [nodes](/docs/nodes/) and `controls`, the values of its fields by name. It may have a `label`, `settings` and a `position`; one without a position is placed on the canvas by itself.

### Runs

| Method and path | Does |
| --- | --- |
| `POST /api/v1/workflows/{id}/executions` | Queue a run |
| `GET /api/v1/workflows/{id}/executions` | List runs, with `page`, `per_page` and filters |
| `GET /api/v1/workflows/{id}/executions/{run id}` | Read a run: status, input, the context it ended with, its steps |

```bash
curl -X POST https://your-heddle/api/v1/workflows/12/executions \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"variables": {"customer_id": 42}}}'
```

A run takes the published version. `"version": "draft"` in the body runs the draft as it is saved.

### Versions

| Method and path | Does |
| --- | --- |
| `GET /api/v1/workflows/{id}/versions` | List versions, newest first |
| `GET /api/v1/workflows/{id}/versions/{version id}` | Read one, with its graph |
| `POST /api/v1/workflows/{id}/publish` | Publish the draft, with an optional `note` |
| `POST /api/v1/workflows/{id}/versions/{version id}/publish` | Put an older version back in production |
| `POST /api/v1/workflows/{id}/versions/{version id}/restore` | Put a version in the draft |

See [Drafts and versions](/docs/concepts/versions/).

### Editing together

| Method and path | Does |
| --- | --- |
| `GET /api/v1/workflows/{id}/live` | Follow the draft as people edit it, as server-sent events |
| `POST /api/v1/workflows/{id}/changes` | Change the draft without taking back what others changed |
| `POST /api/v1/workflows/{id}/focus` | Say which nodes you point at |

`PUT` and `PATCH` make the draft what you send, which takes back whatever someone else changed since you read it. To edit while others do, as [Treadle](https://github.com/heddlehq/Treadle) does:

1. Open `live`. While it is open you are on the flow like anyone with its canvas open: they see you, and the stream says who else is there. It sends `ready` first, with your `client`, whether you `can_edit` and the `graph`; then a `change` with the graph after each change, `presence` when someone comes, goes or selects something, and `cursor` where their pointers are. Another `ready` means the stream lost track: take its graph as it is.
2. Send each change to `changes` with `base`, the graph you last had, and `graph`, the one you have now. Only what changed between the two is applied, on top of what everyone else did; the answer has the draft right after it. What changes the same field last wins.
3. Send `focus` with your `client` and the nodes `selected`, and others see them in your color. A client without a pointer, like a terminal, sends a `cursor` too, `x` and `y` on the flow, and the canvases draw it as yours.

Live editing counts apart from the rest of the API, up to 1200 requests a minute per key. See [Editing together](/docs/concepts/collaboration/).

### The agent

| Method and path | Does |
| --- | --- |
| `GET /api/v1/workflows/{id}/agent` | Read the conversation with the flow's agent |
| `POST /api/v1/workflows/{id}/agent/messages` | Send it a message |
| `GET /api/v1/workflows/{id}/agent/events` | Follow it as it works, as server-sent events |
| `POST /api/v1/workflows/{id}/agent/decision` | Answer when it asks to run or publish |
| `POST /api/v1/workflows/{id}/agent/new` | Start a new conversation |
| `POST /api/v1/workflows/{id}/agent/stop` | Stop what it is doing |

This is how [Treadle](https://github.com/heddlehq/Treadle) talks to the agent. See [The AI Agent and the chat](/docs/guides/ai-agent/).

### Nodes

| Method and path | Does |
| --- | --- |
| `GET /api/v1/nodes` | List every node, with its fields and outputs |
| `GET /api/v1/nodes/{type}` | Read one |
| `GET /api/v1/health` | Whether the server is up, without a key |
