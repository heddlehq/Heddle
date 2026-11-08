---
title: Your first flow
description: Build a flow that calls an API, shapes what it answers and shows the result, then run it and look inside.
sidebar:
  order: 3
---

In ten minutes you will build a flow that asks GitHub about a repository, turns the answer into a sentence and ends. Along the way you will run it, look at what each step did, and publish it.

You need Heddle running. If it isn't yet, see [Installation](/docs/start/installation/).

## 1. Create the flow

Open **Flows** and press **New Flow**. The editor opens on an empty canvas, and the flow is already saved: everything you change from now on is saved as you go.

Rename it by hovering the name at the top and clicking the pencil. Call it `GitHub stars`.

## 2. Add the nodes

Nodes come from the sidebar on the left. Drag them onto the canvas, or right-click the canvas and pick **Create Node**.

1. Add a **Start**. It is where a run begins when you press **Run**.
2. Add an **HTTP Request**, and connect the output of **Start** to its input: drag from the dot on the right of one node to the dot on the left of the other.
3. Add an **Evaluate Code** after it.
4. Add an **Output** at the end.

## 3. Set them up

Hover a node and press the gear to open its drawer on the right. What you type applies at once: there is no save button.

**HTTP Request**

| Field | Value |
| --- | --- |
| Method | `GET` |
| Endpoint URL | `https://api.github.com/repos/heddlehq/Heddle` |

**Evaluate Code**: pick `python` as the language, press **Edit Code** and write:

```python
set_result(f"{result['full_name']} has {result['stargazers_count']} stars")
```

`result` is what the step before left: here, what GitHub answered. [Data in a run](/docs/concepts/context/) explains how data goes from one step to the next.

## 4. Run it

Press **Run Flow** at the top right. Each node shows how its step went, and the **run inspector** opens below the canvas.

Click a step in the inspector to see what it got and what it did:

- On **HTTP Request**, **Output** shows `result` with the whole answer of GitHub.
- On **Evaluate Code**, `result` is now the sentence.

Hover a value and press **Copy as {{placeholder}}** to get the path to it, like `{{result.stargazers_count}}`, ready to paste in another node's field.

## 5. Stop calling the API while you work

Every run calls GitHub again. Open the **HTTP Request** step in the inspector and press **Pin output**: from now on, runs from the editor take that output instead of calling the API, and the node shows a pin. Unpin it in the node's drawer when you are done. Runs in production never take pinned data.

## 6. Publish it

What you edit is the **draft**. Webhooks, schedules and the API run the **published version**, and a flow that was never published doesn't run on its own. Press **Publish**, write a note like `First version`, and confirm. The badge next to the name now says **Live · v1**.

Change anything afterwards and the badge says **Unpublished changes**: production keeps running v1 until you publish again. See [Versions](/docs/concepts/versions/).

## Import it instead

The finished flow, ready to import:

<!-- flow:first-flow -->

## Next

- Start it from the outside: [Webhook to Slack](/docs/tutorials/webhook-to-slack/).
- Learn the rest of the editor: [The editor](/docs/start/editor/).
