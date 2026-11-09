---
title: Starting flows
description: Run a flow from a webhook, a form, on a schedule, from the API, or when another flow fails.
sidebar:
  order: 2
---

**Run Flow** in the editor is for trying. In production, flows start on their own: from a webhook, when someone sends a form, on a schedule, from the API, or when another flow fails. All of these run the [published version](/docs/concepts/versions/), so publish first.

## Webhooks

Add a [Webhook](/docs/nodes/webhook/) node, pick its **Method** and give it a **Path**. Its address is:

```text
https://your-heddle/api/flows/<flow id>/webhook/<path>
```

The flow id is in the editor's URL. A call with another method, or to a flow that isn't published, gets `404`.

What the request brings is in the run as `body`, `headers`, `query_params`, `method` and `request_path`:

```bash
curl -X POST https://your-heddle/api/flows/12/webhook/leads \
  -H "Content-Type: application/json" \
  -d '{"name": "Ana", "email": "ana@example.com"}'
```

Then `{{body.email}}` is `ana@example.com`.

### Answering the caller

By default the caller gets an answer at once, and the run goes on its own:

```json
{"status": "accepted", "execution_id": "8f3k2m", "execution_status": "queued"}
```

To answer with what the flow found, add a [Respond to Webhook](/docs/nodes/respond-to-webhook/). The caller then waits for it, up to 30 seconds, and gets its **Status** and **Body**. Steps after it keep running. A run that fails before answering gets `500`, and one that takes too long gets `504`.

### Checking who calls

A webhook's address is public. To accept only calls you expect, have the caller send a secret, and check it first with a [Switch](/docs/nodes/switch/):

| Field | Value |
| --- | --- |
| Value | `{{headers.x-webhook-secret}}` |
| Case 1 | the secret |

Connect the rest of the flow to `case 1`, and a **Respond to Webhook** with status `401` to `otherwise`.

## Forms

A [Form Trigger](/docs/nodes/form-trigger/) gives the flow a form anyone with its link can fill in: a customer, a lead, a colleague without an account. Its drawer builds the form. Each field has a **question**, a **type** (short text, long text, email, number, date, choice or checkbox), a **key** and whether it is **required**. The key follows the question until you write one of your own.

The link is at the top of the drawer, with **Copy**, **Open** and **Test the draft**. Like a webhook, it shows what is published, so publish before sharing it. It stays the same when you publish again, and **New link** replaces it when the old one got out.

What a person sends is in the run under `form`, by key, and in `result` right after the trigger:

```text
{{form.email}}    ana@example.com
{{form.plan}}     Pro
{{form.terms}}    true
```

Heddle checks every answer before the run starts: a required field must be filled in, an email must look like one, a number is a number and a choice is one of its options. A checkbox is `true` or `false`, a number comes as a number, and a date as `2026-11-08`.

After sending, the person sees the **Message after sending**, or goes to the address in **Then go to**. **Accepting answers** set to `No` closes the form once published. The page follows the visitor's language and theme, and a person can send the same form ten times a minute.

To keep the answers, connect a [Spool: Insert Rows](/docs/nodes/spool-insert-rows/) with **Rows** set to `{{form}}`. **Create Spool table** in the drawer makes a table with a column for each field. See [Spool](/docs/guides/spool/).

## Schedules

A [Schedule](/docs/nodes/schedule/) starts the flow at the times of its cron expression, in UTC.

| Cron | Runs |
| --- | --- |
| `0 9 * * *` | Every day at 09:00 UTC |
| `0 12 * * 1-5` | At noon UTC on weekdays |
| `*/15 * * * *` | Every 15 minutes |
| `0 8 1 * *` | On the first of each month at 08:00 UTC |

São Paulo is UTC−3, so 09:00 there is `0 12 * * *`. A flow can have several Schedules.

## The API

With an [API key](/docs/reference/api/#authentication), queue a run:

```bash
curl -X POST https://your-heddle/api/v1/workflows/12/executions \
  -H "Authorization: Bearer $HEDDLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"variables": {"customer_id": 42}}}'
```

It answers with the run's id at once, and `GET /api/v1/workflows/12/executions/<id>` reads how it went. Add `"version": "draft"` to the body to run the draft instead of the published version. A flow that was never published answers `409`. See the [API reference](/docs/reference/api/).

## When another flow fails

A flow that starts with an [Error Trigger](/docs/nodes/error-trigger/) runs when a flow that picked it as its error flow fails. See [Error flows](/docs/guides/error-handling/#error-flows).

## From another flow

A flow that starts with a [Subflow Trigger](/docs/nodes/subflow-trigger/) runs when a [Subflow](/docs/nodes/subflow/) node of another flow calls it, with what that node sent. See [Subflows](/docs/guides/subflows/).

## Waiting for a call in the middle of a run

A [Wait](/docs/nodes/wait/) set to **Until a call** pauses the run until something calls `{{resume_url}}`. Send that address in an email, a Slack message or to an API, and the run goes on when it is called, with the request as `result`. The [refund approval tutorial](/docs/tutorials/refund-approval/) does this.
