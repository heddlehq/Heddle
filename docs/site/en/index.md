---
title: Heddle documentation
description: Build, run and publish automations on a visual canvas, with AI, code and the services you use.
template: splash
sidebar:
  label: Overview
  order: 0
hero:
  title: Draw it once. Heddle runs it.
  tagline: Everything about building flows on the canvas, running them on your own server, and connecting them to the tools you use.
  image:
    html: '<!-- flow-art:support-triage -->'
  actions:
    - text: Build your first flow
      link: start/first-flow/
      icon: right-arrow
    - text: Browse the nodes
      link: nodes/
      variant: minimal
---

## Start here

<div class="docs-cards docs-cards-3">
<a class="docs-card" href="/docs/start/installation/"><span class="docs-card-icon"><!-- icon:hero-arrow-down-tray --></span><strong>Install Heddle</strong><span>One command on your computer, or Docker on a server.</span></a>
<a class="docs-card" href="/docs/start/first-flow/"><span class="docs-card-icon"><!-- icon:hero-play --></span><strong>Your first flow</strong><span>Call an API, shape the answer, run it and look inside. Ten minutes.</span></a>
<a class="docs-card" href="/docs/start/editor/"><span class="docs-card-icon"><!-- icon:hero-squares-2x2 --></span><strong>The editor</strong><span>The canvas, the node drawer, the run inspector and the AI chat.</span></a>
</div>

## Build something real

<div class="docs-cards docs-cards-2">
<a class="docs-card docs-card-wide" href="/docs/tutorials/webhook-to-slack/"><span class="docs-card-icon"><!-- icon:hero-bolt --></span><strong>Webhook to Slack</strong><span>Receive leads from a form and tell the sales team.</span></a>
<a class="docs-card docs-card-wide" href="/docs/tutorials/daily-report/"><span class="docs-card-icon"><!-- icon:hero-envelope --></span><strong>A daily report by email</strong><span>Read yesterday's orders, make a CSV, email it every morning.</span></a>
<a class="docs-card docs-card-wide" href="/docs/tutorials/support-triage/"><span class="docs-card-icon"><!-- icon:hero-sparkles --></span><strong>Support triage with AI</strong><span>Let AI read each ticket and send it to the right team.</span></a>
<a class="docs-card docs-card-wide" href="/docs/tutorials/refund-approval/"><span class="docs-card-icon"><!-- icon:hero-hand-raised --></span><strong>Refunds with approval</strong><span>Pause a run until someone approves on Slack.</span></a>
</div>

## Go deeper

<div class="docs-columns">
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-light-bulb -->Concepts</p><a href="/docs/concepts/context/">Data in a run</a><a href="/docs/concepts/runs/">How a run moves</a><a href="/docs/concepts/versions/">Drafts and versions</a><a href="/docs/concepts/collaboration/">Editing together</a><a href="/docs/concepts/workspaces/">Workspaces and roles</a></div>
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-wrench-screwdriver -->Guides</p><a href="/docs/guides/credentials/">Credentials</a><a href="/docs/guides/starting-flows/">Starting flows</a><a href="/docs/guides/error-handling/">Handling errors</a><a href="/docs/guides/debugging/">Debugging a run</a><a href="/docs/guides/ai-agent/">The AI Agent and the chat</a></div>
<div class="docs-column"><p class="docs-column-title"><!-- icon:hero-book-open -->Reference</p><a href="/docs/nodes/">All 103 nodes</a><a href="/docs/reference/api/">REST API</a><a href="/docs/reference/mcp/">MCP server</a><a href="/docs/reference/cli/">The heddle command</a><a href="/docs/reference/configuration/">Configuration</a></div>
</div>

## The words you will see

- A **flow** is a graph of **nodes** joined by **connections**. Each node does one thing.
- A **run** is one pass through a flow. It carries a **context**, the data every step reads and adds to. See [Data in a run](/docs/concepts/context/).
- A flow has a **draft**, which you edit, and **published versions**, which production runs. See [Drafts and versions](/docs/concepts/versions/).
- A **workspace** holds a team's flows, runs, credentials and API keys. See [Workspaces and roles](/docs/concepts/workspaces/).
- A **credential** keeps what a node needs to reach a service, encrypted. See [Credentials](/docs/guides/credentials/).
