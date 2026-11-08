---
title: Support triage with AI
description: Read each new support ticket with AI, decide what it is about, and send it to the right team's channel.
sidebar:
  order: 3
---

Tickets arrive from your help desk on a webhook. AI reads each one and decides whether it is about billing, a bug or sales, and Heddle sends it to that team's Slack channel. Anything else goes to #support.

**You will use** [Webhook](/docs/nodes/webhook/), [Respond to Webhook](/docs/nodes/respond-to-webhook/), [AI: Classify](/docs/nodes/ai-classify/), [Switch](/docs/nodes/switch/), [Slack: Send Message](/docs/nodes/slack-send-message/). **Import it:** [support-triage.json](/docs/examples/support-triage.json).

## Before you start

- An [AI provider](/docs/guides/ai-providers/) set up in the **AI** page, for text.
- A **Slack** credential, with the bot in four channels.

## 1. Receive and acknowledge

Add a **Webhook** with **Method** `POST` and **Path** `/support`. The help desk sends `subject`, `message` and `email`.

Help desks don't like to wait, so answer at once: add a **Respond to Webhook** right after it, with **Status** `202` and **Body** `{"received": true}`. The run goes on after answering.

## 2. Classify the ticket

Connect a second branch from the Webhook to an **AI: Classify**:

| Field | Value |
| --- | --- |
| Text | `Subject: {{body.subject}}` and, on the next line, `{{body.message}}` |
| Categories | `billing, bug, sales, other` |

Leave **Credential** and **Model** blank to use the AI page's defaults. `result.category` is always one of the categories, exactly as written.

## 3. Route it

Add a **Switch** on the `success` output of Classify:

| Field | Value |
| --- | --- |
| Value | `{{result.category}}` |
| Case 1 | `billing` |
| Case 2 | `bug` |
| Case 3 | `sales` |

## 4. Tell each team

Add a **Slack: Send Message** on each case, to that team's channel, and one on `otherwise` for #support:

```text
New billing ticket from {{body.email}}: {{body.subject}}
```

`body` is still the ticket: Classify and Switch changed `result`, not the rest of the run.

Connect the `error` output of Classify to the #support message too, so a ticket still reaches someone when the AI is down.

## 5. Try it

Press **Run Flow** and send:

```json
{"subject": "Charged twice", "message": "My card was charged twice for May.", "email": "ana@example.com"}
```

The inspector shows `{"category": "billing"}` on Classify, the Switch going down `case 1`, and the message in #billing. Publish it, and point your help desk's webhook at the flow's address.

## Go further

- Let an [AI Agent](/docs/guides/ai-agent/) draft a reply, with your docs or past tickets as its tools.
- Pull more out of the ticket with [AI: Extract Data](/docs/nodes/ai-extract-data/): the order number, the plan, how upset the customer is.
- Translate tickets into one language first with [AI: Translate](/docs/nodes/ai-translate/).
