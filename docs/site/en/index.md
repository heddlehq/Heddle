---
title: Heddle documentation
description: Build, run and publish automations on a visual canvas, with AI, code and the services you use.
sidebar:
  label: Overview
  order: 0
---

Heddle is a flow orchestrator you run yourself. You draw a flow on a canvas, node by node, and Heddle runs it: when you press **Run**, on a schedule, when a webhook is called, or from the API. It runs on the BEAM, so thousands of runs go on at once, a failing one doesn't take the others down, and a run survives a restart.

## Where to start

- **New to Heddle?** [Install it](/docs/start/installation/), then [build your first flow](/docs/start/first-flow/). It takes about ten minutes.
- **Want to see what it does?** The [tutorials](/docs/tutorials/webhook-to-slack/) build real flows end to end, each one with a file you can import.
- **Looking for a node?** The [node reference](/docs/nodes/) has every one of them, with its fields, its outputs and what it returns.

## How the documentation is organized

| Section | For when you want to |
| --- | --- |
| **Getting started** | Install Heddle and learn the editor. |
| **Tutorials** | Build a complete flow, step by step. |
| **Concepts** | Understand how runs, data, versions and teams work. |
| **Guides** | Do one thing: connect a service, handle errors, debug a run. |
| **Nodes** | Look up what a node takes and what it returns. |
| **Reference** | Use the API, the MCP server, the `heddle` command and the settings. |
| **Self-hosting** | Run Heddle on servers, and scale it. |

## The words you will see

- A **flow** is a graph of **nodes** joined by **connections**. Each node does one thing.
- A **run** (or execution) is one pass through a flow. It carries a **context**, the data every step reads and adds to. See [Data in a run](/docs/concepts/context/).
- A flow has a **draft**, which you edit, and **published versions**, which production runs. See [Versions](/docs/concepts/versions/).
- A **workspace** holds a team's flows, runs, credentials and API keys. See [Workspaces and roles](/docs/concepts/workspaces/).
- A **credential** keeps what a node needs to reach a service, encrypted. See [Credentials](/docs/guides/credentials/).
