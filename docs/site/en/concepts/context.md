---
title: Data in a run
description: The context every step reads and adds to, result, variables, and how {{placeholders}} read them.
sidebar:
  order: 1
---

A run carries one object from its first step to its last: the **context**. Each step reads it and leaves it changed for the next. Knowing what is in it is most of what it takes to build a flow.

## What a run starts with

| Started by | The context begins with |
| --- | --- |
| **Run Flow** in the editor, or the API | What was sent as `input`. From the API, `{"input": {"variables": {"user_id": 42}}}` gives the run a variable. |
| A [Webhook](/docs/nodes/webhook/) | `body`, `headers`, `query_params`, `method` and `request_path` of the request. |
| A [Schedule](/docs/nodes/schedule/) | Nothing of its own. |
| An [Error Trigger](/docs/nodes/error-trigger/) | `error` and `execution`, about the run that failed. |

`flow_id` and `workspace_id` are always there, and no step can change them.

## result

Almost every node leaves what it did in `result`: the answer of an API, the rows of a query, the text of a summary. The next node reads it, and most fields default to it, like the **Rows** of an insert, which is `{{result}}` until you change it.

Each step replaces `result`. To keep a value for later steps, give it a name:

- a [Variable](/docs/nodes/variable/) node keeps a value under that name;
- a [code step](/docs/nodes/evaluate-code/) can put anything in the context: `Map.put(context, "customer", result)`.

What each node leaves is in its page, under **What it returns**.

## Placeholders

A field reads the context with `{{path}}`:

| You write | You get |
| --- | --- |
| `{{result}}` | The whole result |
| `{{body.customer.email}}` | A key inside a key |
| `{{result.rows.0.id}}` | The `id` of the first row: a number picks an item of a list |
| `Hello, {{body.name}}!` | Text with the value written into it |

A path that leads nowhere becomes empty text. An object or a list written into text becomes JSON. The run inspector writes paths for you: hover a value and press **Copy as {{placeholder}}**.

### In JSON fields

Fields that take JSON, like the rows of a database node, are read as JSON first and filled in after. Outside quotes a placeholder keeps its type; inside quotes it's written into the text:

```json
{"name": "{{body.name}}", "age": {{body.age}}, "tags": {{body.tags}}}
```

So a value that comes from outside can't change the shape you wrote. A field that is only a placeholder, like `{{result}}`, takes the value as it is.

### In queries

A placeholder in SQL, CQL or Cypher is sent to the database as a parameter, never as part of the query. See [Databases](/docs/guides/databases/#values-in-a-query).

### Fields that take a path

A few fields name where to read, without braces: the **List** of a [For Each](/docs/nodes/for-each/), the **Source** of the CSV nodes, the **Rows** of Google Sheets and the **Variable** of a [Condition](/docs/nodes/condition/). Write `body.items`, not `{{body.items}}`. The node's page says when a field is one of these.

## Variables

Variables live under `variables` in the context, and `{{name}}` reads a variable before a key of the context with the same name. They come from a [Variable](/docs/nodes/variable/) node, from the `variables` of an API call, or from the input of a test run.

## A node's fields while it runs

While a node runs, its fields are in the context under their own names, and they go back to what they were when it ends. That is why a node's fields have names like `response_body` and `switch_value`: a field called `body` would hide the body of the webhook from that node.

## How big a run can be

The context is saved with the run, so keep it to data. A list for a [For Each](/docs/nodes/for-each/), and the rows of a query, hold up to 10,000 items. Files, like a download or an image, travel as base64 inside `result`, and every node that takes a file reads them back. Long values are cut in the inspector, not in the run.
