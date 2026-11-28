---
title: Agents
description: Agents that live in your workspace, remember each customer, follow up on their own, and work with each other.
sidebar:
  order: 8
---

The [AI Agent](/docs/guides/ai-agent/) node does a task inside one run, and forgets it when the run ends. An **agent** lives on: it has a name, keeps what it learns about each customer between messages, writes back three days later, and asks other agents when it needs them. Your flows are its hands.

Agents need an [AI provider](/docs/guides/ai-providers/). They are powered by [Jido](https://hex.pm/packages/jido), and you never need to know it.

## Start from a template

On the **Flows** page, **From a template** has four agents ready to try:

- **Support Agent** answers customers on its chat, remembers each one, and opens a ticket when it can't solve something.
- **SDR Follow-up** talks to each lead, keeps their stage, and follows up three days later if they go quiet.
- **Collections** reminds each customer of a late invoice, records what they promise, and asks a person before offering a discount.
- **Triage Team** is three agents in one flow: a triage agent that asks the Billing and Tech agents when it needs them.

Publish the flow, open the **Agent** node, and press **Chat** to talk to it.

## An agent is a flow

An agent is a flow that begins at the **Agent** trigger. Publishing the flow creates the agent, and each message to it is a run.

```text
Agent → Agent: Think → Agent: Reply
            └ tools → Find order
```

On the trigger:

- **Name**: how other flows reach it, and how it shows on its chat.
- **Instructions**: who it is and how it works, in plain words.
- **State**: what it keeps, as JSON with each field's starting value: `{"stage": "new", "attempts": 0}`. The starting value sets the type.

**Agent: Think** answers with the model, using the nodes connected to its `tools` output, like the AI Agent does. **Agent: Reply** sends the answer back. In between, the run reads `{{agent.message}}`, `{{agent.state}}` and `{{agent.from}}`.

## Instances

Each message names a **key**, like a customer's id or email, and each key is an **instance** of the agent, with its own state and conversation. Without a key it is `main`, for an agent that is one of a kind.

Messages to one instance are handled one at a time, in the order they came, so two never change it at once. What a run changes is kept only if the run ends well.

The trigger's drawer shows each instance, with its state, its messages, what it spent today and what it has scheduled.

## What it remembers

- **The conversation**: the last 20 messages go with each new one. Older ones become a short summary, so a conversation of months still fits.
- **Its state**: **Agent: Set State** changes it, like `{"stage": "won"}`. Think also has a **remember** tool, so the agent keeps what it learns on its own, like the customer's name.

## Talking to it

- **People**: the trigger's drawer has a **chat link**. Anyone with it talks to the agent, each in a conversation of their own, which is an instance. Put it on your site, or send it by email.
- **Other channels**: a flow that receives WhatsApp or Slack messages sends them with **Agent: Ask**, and answers with what the agent replied.
- **Flows**: **Agent: Send Message** sends and goes on. **Agent: Ask** waits for the reply, holding no worker.
- **The clock**: **Agent: Schedule** sends the agent a message later, like a follow-up in three days. **Call off the ones set before** moves it each time the customer writes. **Agent: Cancel Schedule** calls it off.
- **Events**: **Agent: Publish Event** tells the workspace that something happened, like `deal.won`, and every flow that begins at **When an Agent Publishes** starts.
- **MCP**: `list_agents`, `read_agent` and `message_agent` let an assistant like Claude talk to your agents.

## Agents working together

List the agents one may ask in Think's **Agents it can ask**. It then has an **ask_agent** tool: the run waits for the other agent's reply, holding no worker, and the agent goes on with it. An agent can't be asked back by one that waits for it, since neither would answer.

## Keeping it safe

- **Approval**: list tools in Think's **Tools that need approval**, like `offer_discount`. When the agent wants one, the run waits on the **Approvals** page, and the tool runs only once a person approves it.
- **Limits**: on the trigger, **Messages per hour** and **Spending per day** (US$) per instance. A message past them fails its run, saying why.
- **Who may message it**: agent names, `chat` for people, `flows` for any flow, or `flow:ID`. Blank lets anyone.
- **No endless loops**: agents messaging each other stop 5 messages deep.
- **Pause**: **Agent: Pause or Resume** stops an agent, or one instance, from taking messages.

## Changing an agent

Publish a new version, and each instance moves to it on its next message: fields it kept stay when their type is the same, new fields start at their value, and removed ones go.

**Agent: Read Agent** and **Agent: List Instances** read instances from any flow, and **Agent: Reset Instance** and **Agent: End Instance** forget one.
