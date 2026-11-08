---
title: Refunds with approval
description: Pause a run until a person approves on Slack, then refund through an API, or give up after a day.
sidebar:
  order: 4
---

A refund request comes in. Heddle asks #finance on Slack, with a link to approve and one to reject, and waits. When someone clicks, the run goes on: it calls the payments API or says it was rejected. If nobody decides in 24 hours, it says so.

**You will use** [Webhook](/docs/nodes/webhook/), [Slack: Send Message](/docs/nodes/slack-send-message/), [Wait](/docs/nodes/wait/), [Switch](/docs/nodes/switch/), [HTTP Request](/docs/nodes/http-request/).

<!-- flow:refund-approval -->

## 1. Receive the request

Add a **Webhook** with **Method** `POST` and **Path** `/refunds`. It gets `order_id`, `amount` and `reason`.

## 2. Ask for a decision

Add a **Slack: Send Message** to #finance:

```text
Refund of {{body.amount}} for order {{body.order_id}} ({{body.reason}}).
Approve: {{resume_url}}?decision=approve
Reject: {{resume_url}}?decision=reject
```

`{{resume_url}}` is an address made for this run, which exists because the flow has a Wait. Calling it, even by clicking a link, makes the run go on.

## 3. Wait

Add a **Wait** on Slack's `success` output:

| Field | Value |
| --- | --- |
| Wait | Until a call |
| How long | `24` |
| Unit | `hours` |

The run is saved and stops here, holding no worker. It survives restarts. When the address is called, it goes on through `exec`, with the request in `result`. After 24 hours without a call, it goes on through `timeout`.

## 4. Act on the decision

Add a **Switch** on `exec`, with **Value** `{{result.query_params.decision}}`, **Case 1** `approve` and **Case 2** `reject`.

On `case 1`, an **HTTP Request** to your payments API:

| Field | Value |
| --- | --- |
| Method | `POST` |
| Endpoint URL | `https://payments.example.com/refunds` |
| Headers (JSON) | `{"Content-Type": "application/json"}` |
| Body | `{"order_id": "{{body.order_id}}", "amount": {{body.amount}}}` |

Then a Slack message saying it was refunded. On `case 2`, a message saying it was rejected, and on the Wait's `timeout`, one saying nobody decided.

## 5. Try it

Press **Run Flow** with:

```json
{"order_id": "4411", "amount": 129.9, "reason": "Arrived broken"}
```

The inspector shows the run **Waiting** at the Wait. Click **Approve** in Slack: the browser shows `{"status": "resumed"}`, and the run finishes through the refund. A second click answers that it was already resumed.

## Go further

- Anyone with the link can decide. To know who did, send the links in a direct message, or ask for a code in the body and check it.
- Ask by email instead, with [Email: Send Email](/docs/nodes/email-send-email/).
- Wait until a date instead, like the end of a trial, with **Until a date**.
