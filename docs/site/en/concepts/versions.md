---
title: Drafts and versions
description: Edit a draft while production runs what you published, keep every version with who changed it and when, and go back in one click.
sidebar:
  order: 3
---

A flow has two sides. The **draft** is what the canvas shows, and it changes as anyone edits it. The **published version** is what production runs. They stay apart until you publish, so you can work on a flow that is live without breaking it.

## What runs what

| Started by | Runs |
| --- | --- |
| **Run Flow**, a section's play button, **Run from here** | The draft, as it is |
| Webhooks, schedules, error flows | The published version |
| The API | The published version, unless the call asks for `version=draft` |
| The AI chat, and `run_flow` and `test_flow` over MCP | The draft |

A flow that was never published doesn't run on its own: its webhooks answer `404` and its schedules don't fire. Every run keeps the version it ran, so a run from last week shows the flow as it was then.

## Publishing

Press **Publish**, write what changed, and confirm. Publishing checks the whole flow: a half-written cron expression is fine in a draft, but not in production, and the dialog says what to fix.

The badge next to the name tells where things stand:

- **Not published**: production runs nothing yet.
- **Live · v4**: production runs what the canvas has.
- **Unpublished changes**: the draft moved on, and production still runs the last version published.

Admins and editors can publish. The AI chat can too, but it asks first.

## The history

Open **⋯ → Versions**. Each version shows its number, when it was made, who made it and who else changed the draft since the version before, and its note. There are three kinds:

- **Published**, made by **Publish**, with a note.
- **Checkpoint**, made on its own while a flow is edited, every ten minutes or so, and when everyone leaves it.
- **Run**, the draft as it was when someone ran it from the editor.

Click a version to see it on the canvas, with what it changed from the one before: added and changed nodes are marked, and removed ones show dashed where they were.

Checkpoints and run versions older than 30 days are deleted, unless a run used them or they are the newest. Published versions are kept.

## Going back

From a version in the history:

- **Restore** puts it in the draft. The draft you had is kept as a checkpoint first, so restoring can be undone. Production keeps running what it ran until you publish.
- **Publish this version** puts it back in production, leaving the draft alone. That is the quick way out of a bad release.

## From the API

The API has the same: list versions, read one, publish the draft, publish an older version and restore one. See the [API reference](/docs/reference/api/#versions).
