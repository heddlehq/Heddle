---
title: MCP server
description: Let Claude Code, Claude Desktop, Cursor or any MCP client read, build, run and publish your flows.
sidebar:
  order: 2
---

Heddle is an [MCP](https://modelcontextprotocol.io) server. An AI tool connected to it gets the same tools the chat in the editor has: it lists the nodes, reads a flow, changes it, tests it, and publishes it when you say so.

## Connect

The address is `/mcp` on your Heddle, over HTTP, with an [API key](/docs/reference/api/#authentication) in the header. The key decides the workspace and what the tool may do.

**Claude Code**:

```bash
claude mcp add --transport http heddle https://your-heddle/mcp \
  --header "Authorization: Bearer <API key>"
```

**Clients with a JSON config**, like Claude Desktop or Cursor:

```json
{
  "mcpServers": {
    "heddle": {
      "type": "http",
      "url": "https://your-heddle/mcp",
      "headers": {"Authorization": "Bearer <API key>"}
    }
  }
}
```

The **AI** page shows the command with your address filled in. On a local install, the **Terminal** in the editor opens Claude Code already connected.

## Tools

| Tool | Does |
| --- | --- |
| `list_nodes` | Lists every node, with its fields and outputs |
| `list_flows` | Lists the flows of the workspace |
| `get_flow` | Reads a flow: nodes, connections and comments |
| `create_flow` | Creates a flow; nodes without a position are laid out |
| `update_flow` | Replaces the name, nodes or connections of a flow; it shows on open canvases at once |
| `test_flow` | Runs the draft and waits, returning the status, the error, the final context and each step. For a webhook flow, it takes the request's body |
| `run_flow` | Queues a run of the draft, and returns its id |
| `list_executions` | Lists the runs of a flow |
| `get_execution` | Reads a run |
| `list_versions` | Lists the versions, with who made each and what changed |
| `publish_flow` | Publishes the draft, or puts an older version back |
| `restore_version` | Puts a version in the draft |
| `chat` | Talks to Heddle's own agent, which answers with this server's model |

`test_flow`, `run_flow`, `publish_flow` and `restore_version` change real things. A well-behaved client asks you before calling them.

## A good first prompt

> Using Heddle, list the nodes, then build a flow that reads new rows from the "Leads" Google Sheet every hour and posts each one to #sales on Slack. Test it before you tell me it's done.

The tool will call `list_nodes`, `create_flow`, `test_flow`, read the error if there is one, fix it with `update_flow`, and try again.
