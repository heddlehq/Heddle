---
title: Debugging a run
description: Read what each step got and changed, run again from any step, and pin data so you stop calling real services while you build.
sidebar:
  order: 5
---

Every run keeps what happened in it. The run inspector, below the canvas, shows it step by step.

## Open a run

- A run you start from the editor opens in the inspector by itself.
- **Executions** lists the runs of every flow, with their status. Open one to see it in its flow's editor.
- The link of a failed run, like the `{{execution.url}}` an [error flow](/docs/guides/error-handling/#error-flows) gets, opens it straight in the inspector.

The flow shows as it was when the run started: a run pins its [version](/docs/concepts/versions/).

## Read a step

Click a step in the list, or **Show on the canvas** to find its node. For each step:

- **Input** is the context it got. **Output** is what it changed: what it added, what it changed and **Removed** keys.
- **Tries** shows each try of a step that [tried again](/docs/guides/error-handling/#try-again), with its error.
- **Error** says why it failed.

**Filter keys and values** finds a value in a big context. **Copy JSON** copies a value, and **Copy as {{placeholder}}** copies the path to it, to paste in a field.

Long values are cut to keep the run small, and a run with thousands of steps keeps the data of the last ones only. A step whose data was cut can't be run again from there.

## Run again

- **Run again** saves the flow and runs it with the same input. After fixing a node, this is the quickest check.
- **Run from here** saves the flow and runs it from that step, with the context that step got. The steps before it don't run again, so a run that failed at step 8 of 10 doesn't call steps 1 to 7 again.

Both run the draft.

## Pinned data

While you build, calling a real API on every run is slow, costs money or sends real messages. **Pin output** on a step makes runs from the editor take that output instead of running the node: the node shows a pin, and the run leaves through the same output with the same data.

- The data can be edited in the node's drawer, under **Pinned data**, as JSON. **Unpin** removes it.
- Only runs from the editor take it. Production, the API and schedules always run the node.

## Run a part of the flow

Put the nodes you are working on in a [section](/docs/start/editor/#notes-and-sections) and press its play button. Only that section runs.

## Test with a webhook's request

A flow that starts at a Webhook needs a request to run. **Run Flow** on such a flow asks for the body, the headers and the query to send, so you can try it without calling it from outside.

## When nothing shows

- **The run is Queued**: no worker is taking runs. See `heddle status`, or the worker logs on a server.
- **A webhook answers 404**: the flow isn't published, the path or the method differ, or the call reaches another server.
- **A schedule doesn't fire**: the flow isn't published, or the cron is in another time zone: it is UTC.
