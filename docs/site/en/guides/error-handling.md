---
title: Handling errors
description: Try a step again, take an error path, go on anyway, or start another flow when a run fails.
sidebar:
  order: 4
---

Services go down, tokens expire and data comes in shapes nobody expected. Heddle gives each step four ways to deal with a failure, and each flow one more.

## Try again

In a node's drawer, under **When it fails**:

- **Tries again**: how many more times the step runs before it fails, up to 10.
- **Seconds between tries**: the wait before the first new try, up to 300.
- **Wait twice as long after each try**: doubles the wait each time, instead of keeping it.

Three tries with 2 seconds, doubling, try again after 2, 4 and 8 seconds. The run inspector shows each try and its error.

Retry steps that can be repeated safely: a GET, an upsert, a message you don't mind sending twice.

## Take an error path

Nodes that reach a service have an `error` output. With **Then** on **Stop the run**, the default, connect something to it and a failure goes there instead of failing the run, with the error in `result`:

```json
{"error": "Slack refused it: channel_not_found"}
```

From there you can tell someone, write the failure to a table, or answer the webhook with a `502`.

## Go on anyway

Under **Then**, pick **Continue** and the run goes on through the node's usual output, with `{"error": "..."}` as `result`. Use it for steps that are nice to have, like a log or a notification, so their failure doesn't stop what matters.

## Give any node an error output

Under **Then**, pick **Use an error output** and the node gets an `error` output, even if it had none, like **Evaluate Code**.

## Error flows

When a run fails and nothing above handled it, the flow's **error flow** runs. One error flow can watch many flows: build it once, and pick it in each flow's **⋯ → Settings**.

An error flow starts with an [Error Trigger](/docs/nodes/error-trigger/), and gets the error and the run that failed:

```text
{{error.message}}   Slack refused it: channel_not_found
{{error.node_label}} Tell the team
{{execution.flow_name}} New leads
{{execution.url}}   a link that opens the run in the inspector
```

A common one sends that to Slack or email. The error flow runs its published version, so publish it, and a failure inside it doesn't start another one.

## Check the data first

A [Validate](/docs/nodes/validate/) node checks what comes in against a schema, like Zod, before the flow uses it. Connect `invalid` to what should happen then, like a [Respond to Webhook](/docs/nodes/respond-to-webhook/) with status `422` and `{{result.message}}`:

```json
{"email": "email", "amount": {"type": "number", "gt": 0, "coerce": true}}
```

Through `valid`, the next nodes get the data cleaned up as the schema says.

## Fail on purpose

To stop a run when the data is wrong, put a [Condition](/docs/nodes/condition/) in front, and on the bad side an **Evaluate Code** that raises:

```elixir
raise "The order has no customer"
```

The run fails with that message, and the error flow gets it.
