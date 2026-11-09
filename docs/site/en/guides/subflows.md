---
title: Subflows
description: Run one flow from another, to split a long flow or reuse the same steps in several.
sidebar:
  order: 3
---

A [Subflow](/docs/nodes/subflow/) node runs another flow of the workspace as one of its steps. Use it to split a flow that grew too long, or to keep in one place what several flows do, like scoring a lead or telling the team.

## The flow that is called

Start it with a [Subflow Trigger](/docs/nodes/subflow-trigger/). It gets the **Data** the Subflow sent as `result`, and `caller`, the flow that called it:

```json
{
  "result": {"email": "ana@example.com", "company": "Acme"},
  "caller": {"flow_id": 12, "flow_name": "New leads", "execution_id": "8f3k2m"}
}
```

Whatever it has in `result` when it ends goes back to the flow that called it. A flow without a Subflow Trigger is run from its Start node.

Like everything that runs on its own, it runs its [published version](/docs/concepts/versions/), so publish it first. Each call is a run of its own, so it shows in its runs with each step, and its error flow starts if it fails.

## Calling it

Add a **Subflow** node and pick the flow in **Flow**. **Open this flow**, under it, takes you there. **Data** is JSON, with placeholders, or a single placeholder like `{{result}}`:

```json
{"email": "{{body.email}}", "company": "{{body.company}}"}
```

Then pick how it waits:

- **Wait for it to finish**: the run goes on through `success` with the `result` the other flow ended with, or through `error` with why it failed.
- **Start it and go on**: the run goes on at once, and `result` is the run it started, like `{"execution_id": "8f3k2m", "flow_id": 12, "flow_name": "Score lead"}`.

A flow that pauses at a [Wait](/docs/nodes/wait/) can't be waited for: start it and go on instead.

## Limits

- A flow only calls flows of its own workspace.
- A flow can't call itself, directly or through others: the call goes through `error`.
- Flows call each other 8 levels deep at most.
