---
title: The AI Agent and the chat
description: Give an agent your steps as tools, keep its memory between runs, and let the editor's chat build flows for you.
sidebar:
  order: 7
---

Heddle has AI in two places. The **AI Agent** node works inside a run, with your steps as its tools. The **chat** in the editor works on the flow itself, building and changing it with you. Both need an [AI provider](/docs/guides/ai-providers/).

## The AI Agent node

The agent gets a **Prompt**, thinks, calls tools, reads what they answer, and goes on until it has a reply or reaches **Max steps**. The reply goes down `success` as `result`.

```text
Prompt: A customer wrote: "{{body.message}}". Their email is {{body.email}}.
        Find their last order and answer when it arrives.
```

### Tools

Any node connected to the agent's `tools` output becomes a tool, named after the node's label, like `find_order` for **Find order**. Name tools for what they do, and the agent picks the right one more often.

On a tool, **the fields you leave blank are what the agent fills in**, and the fields you fill stay as they are, out of its reach. A **SQL: Select Rows** with **Table** set to `orders` and **Where** blank lets the agent search orders, and only orders. It never picks a credential or a model, and never writes code.

A tool can be a whole branch: the agent calls its first node, and the steps after it run too, with what the agent passed in `input`. What the branch leaves in `result` is what the agent reads back.

After the run, `tool_calls` lists every tool it called, with the arguments and whether it worked, and the inspector shows each tool's steps.

### Replies as data

**Reply as** `JSON` asks for one JSON value, which becomes `result` already decoded, so the next node reads `{{result.priority}}`. Say what keys you want in the prompt:

```text
Reply with {"priority": "low" | "high", "summary": "..."}
```

A reply that isn't JSON goes down `error`.

### Memory

**Memory key** keeps the conversation between runs. Runs with the same key continue where the last one stopped: `{{body.customer_id}}` gives each customer their own thread. Blank forgets everything after each run.

### Keep it safe

- An agent can only do what its tools do. Fill in what it shouldn't change: the table, the channel, the recipient.
- Give a database tool a user with only the permissions it needs, because the agent writes the fields left blank, a query included.
- **Max steps** caps how many times it calls the model in one run, 10 by default.
- A [Wait](/docs/nodes/wait/) can't be a tool.

## The chat in the editor

The chat at the bottom right of the editor works on the flow you have open. Ask for what you need, in your own words:

> When a lead comes in on a webhook, save it to the leads table and tell #sales on Slack, with the lead's name and company.

It reads the flow and the nodes it has, plans the change, and edits the canvas in front of you: you see it among the avatars, and the nodes it changes flash. Then it can try the flow and fix what failed.

- It **always asks** before running a flow or publishing it, and before restoring a version. **Always** lets it run without asking for the rest of the conversation; publishing asks every time.
- Its changes are like anyone's: **Ctrl+Z** doesn't undo them for you, but the [version history](/docs/concepts/versions/) brings back any earlier state.
- A conversation belongs to you and the flow. Opening the flow again starts a new one, unless it is still working.

**Flows → Create with AI** starts a new flow from a description in the same way.

## From other tools

The same agent answers through the API, which is how [Treadle](https://github.com/heddlehq/Treadle) talks to it in the terminal, and Claude Code or any MCP client can build flows with the same tools. See [MCP](/docs/reference/mcp/).
