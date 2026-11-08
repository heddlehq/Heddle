---
title: How a run moves
description: Where a run starts, how it follows outputs, branches, loops, joins and waits, and what happens when a step fails.
sidebar:
  order: 2
---

A run goes from node to node along the connections. Each node does its work, then picks one of its outputs, and the run follows what is connected to that output.

## Where it starts

- **Run Flow**, and runs from the API, start at the **Start** node. A flow without one starts at its first trigger.
- A call to a [Webhook](/docs/nodes/webhook/) starts at that Webhook.
- A [Schedule](/docs/nodes/schedule/) starts at itself, when its time comes.
- A run that another flow's failure started begins at the [Error Trigger](/docs/nodes/error-trigger/).
- A [section](/docs/start/editor/#notes-and-sections) run from its play button starts at the nodes nothing in the section leads to.

Runs from the editor run the **draft**. Webhooks, schedules, error flows and the API run the **published version**. See [Versions](/docs/concepts/versions/).

## Outputs

Most nodes have one output, `exec`. Nodes that reach a service have two, `success` and `error`, so a flow can handle the service being down. Flow control nodes pick among several:

| Node | Outputs |
| --- | --- |
| [Condition](/docs/nodes/condition/) | `true`, `false` |
| [Switch](/docs/nodes/switch/) | `case 1` to `case 4`, `otherwise` |
| [For Each](/docs/nodes/for-each/) | `item` for each item, then `done` |
| [Wait](/docs/nodes/wait/) | `exec`, or `timeout` when a call didn't come |
| [AI Agent](/docs/nodes/ai-agent/) | `success`, `error`, and `tools`, which aren't followed but offered to the agent |

## Branches

Several connections can leave one output. The run follows them one after the other, in the order they were made, and each branch gets the context as the node left it. A run ends when no branch has anything left to run.

## Loops

A [For Each](/docs/nodes/for-each/) runs the nodes on its `item` output once per item, in order, then goes on through `done` with what each pass left.

## Joining branches

A [Merge](/docs/nodes/merge/) waits for every connection that reaches it, then goes on once, with the results of all of them. A branch a Condition never took doesn't hold it forever: once nothing else is left to run, the Merge goes on with what arrived.

## Waiting

A [Wait](/docs/nodes/wait/) pauses the run for a while, until a date, or until something calls its address. The run is saved, holds no worker while it waits, and survives restarts.

## When a step fails

A step fails when its service answers with an error, its code raises, or a field is wrong. Then, in this order:

1. **It tries again**, if its settings give it tries, waiting between them.
2. **It takes its error path**: the `error` output when something is connected to it.
3. **It goes on**, if its settings say so, through its usual output with the error as `result`.
4. **Otherwise the run fails**, and the flow's [error flow](/docs/guides/error-handling/#error-flows), if it has one, runs.

See [Handling errors](/docs/guides/error-handling/).

## What is kept

Every run is kept with its status, its input, the context it ended with and each step: what it got, what it changed, how long it took and how many tries it needed. Open it from **Executions**, or in the editor's run inspector. A run started from the editor can also take [pinned data](/docs/guides/debugging/#pinned-data) instead of running a node.

## Where runs happen

Runs go through a queue in Postgres and run on the **workers**, which can be on other machines than the editor. A run that was going on when its worker died starts again from the beginning after a while, so keep steps that charge money or send messages safe to repeat. See [Scaling](/docs/self-hosting/scaling/).
