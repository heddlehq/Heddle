---
title: Webhook to Slack
description: Receive leads from a website form, tell the sales team on Slack, and answer the form whether it worked.
sidebar:
  order: 1
---

A form on your website sends each new lead to Heddle. Heddle tells **#sales** on Slack and answers the form, so it can show "thanks" or an error.

**You will use** [Webhook](/docs/nodes/webhook/), [Slack: Send Message](/docs/nodes/slack-send-message/), [Respond to Webhook](/docs/nodes/respond-to-webhook/).

<!-- flow:webhook-to-slack -->

## Before you start

Create a **Slack** credential with a bot that can `chat:write`, and invite it to the channel. See [Credentials](/docs/guides/credentials/#slack).

## 1. Receive the form

Create a flow called `New leads to Slack` and add a **Webhook**:

| Field | Value |
| --- | --- |
| Method | `POST` |
| Path | `/leads` |

Its address is `https://your-heddle/api/flows/<flow id>/webhook/leads`, where the flow id is the number in the editor's URL.

## 2. Tell the team

Add a **Slack: Send Message** after the Webhook:

| Field | Value |
| --- | --- |
| Credential | Your Slack credential |
| Channel | The ID of #sales, like `C0123456789` |
| Message | `New lead: *{{body.name}}* <{{body.email}}> from {{body.company}}` |

`{{body.name}}` reads the `name` the form sent. See [Data in a run](/docs/concepts/context/).

## 3. Answer the form

The form waits for an answer, so give it one either way:

1. Add a **Respond to Webhook** on the `success` output of Slack, with **Status** `200` and **Body** `{"ok": true}`.
2. Add another on the `error` output, with **Status** `502` and **Body** `{"ok": false, "error": "{{result.error}}"}`.

Because the error output is connected, a Slack failure doesn't fail the run: it answers the form instead.

## 4. Try it

Press **Run Flow**. A flow that starts at a Webhook asks for the request to try with. Give it a JSON body:

```json
{"name": "Ana Souza", "email": "ana@example.com", "company": "Acme"}
```

The message shows up in #sales, and the inspector shows what the flow would have answered.

## 5. Put it live

Press **Publish**. From now on, calls reach the published version:

```bash
curl -X POST https://your-heddle/api/flows/12/webhook/leads \
  -H "Content-Type: application/json" \
  -d '{"name": "Ana Souza", "email": "ana@example.com", "company": "Acme"}'
```

```json
{"ok": true}
```

## Go further

- Save each lead too: add a [SQL: Insert Rows](/docs/nodes/sql-insert-rows/) or [Google Sheets: Add Rows](/docs/nodes/google-sheets-add-rows/) before Slack.
- Accept only your form: [check a secret header](/docs/guides/starting-flows/#checking-who-calls).
- Know when it breaks: add an [error flow](/docs/guides/error-handling/#error-flows).
