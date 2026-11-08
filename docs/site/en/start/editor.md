---
title: The editor
description: A tour of the canvas, the node drawer, the run inspector, sections, the AI chat and what sits at the top.
sidebar:
  order: 4
---

The editor is where a flow is drawn and tried. It saves as you go, and everyone with the flow open sees the same canvas.

## The top bar

From left to right:

- **Flows / name**: back to the list, and the flow's name. Hover the name and press the pencil to rename it.
- **Status**: **Live · v3** when production runs what the canvas has, **Unpublished changes** when the draft moved on, **Not published** when it never was. Click it to open the versions. While it saves, **Saving...** shows next to it.
- **People**: who else has the flow open. Click someone to follow their cursor. See [Editing together](/docs/concepts/collaboration/).
- **⋯**: **Versions**, the flow's **Settings** (like its [error flow](/docs/guides/error-handling/#error-flows)), and **Import from a file**.
- **Publish** puts the draft in production, and **Run Flow** runs the draft now.

## The canvas

- **Add a node**: drag it from the sidebar, or right-click the canvas and pick **Create Node**. The sidebar searches by name and by what a node works with, like `postgres`, and keeps the ones you used last.
- **Connect**: drag from an output, on the right of a node, to an input, on the left. Several connections may leave one output: they run in the order they were made.
- **Select**: click a node, **Ctrl**+click to add more, or hold **Shift** and drag a box around several. Then **Ctrl+C** and **Ctrl+V** copy them, even into another flow, and **Delete** removes them.
- **Undo**: **Ctrl+Z** and **Ctrl+Y**, or the right-click menu. Undo takes back only what you did, never what someone else did.
- **Move around**: drag the empty canvas, and scroll to zoom.

## The node drawer

Hover a node and press the gear. The drawer shows the node's name and its fields, and every change applies as you type. Below the fields, **When it fails** says how the node behaves when it fails: tries again, goes on, or takes an error path. See [Handling errors](/docs/guides/error-handling/).

Fields that take `{{placeholders}}` read the run's data. See [Data in a run](/docs/concepts/context/).

## Notes and sections

The buttons at the top left of the canvas add **Title**, **Text** and **Note** cards, to explain the flow to whoever reads it, and **Section**, a frame around nodes.

A section can be run on its own, with the play button on it, which is handy to try a part of a big flow. Turn off **Run with the flow** in its settings and it runs only from that button: a place for maintenance steps, like filling a table once.

## The run inspector

After a run, the inspector below the canvas lists its steps. Click one to see what it got (**Input**), what it changed (**Output**), how many tries it took and its error. From there:

- **Copy as {{placeholder}}** gives the path to a value.
- **Pin output** makes runs from the editor take that output instead of running the node.
- **Run from here** runs the flow again from that step, with the data it had.
- **Run again** runs the whole flow again with the same input.

See [Debugging a run](/docs/guides/debugging/).

## The AI chat

When an AI is set up, the chat at the bottom right builds and changes flows for you. Tell it what you need: it reads the flow, plans the change, and edits the canvas in front of you. It always asks before running or publishing. See [The AI Agent and the chat](/docs/guides/ai-agent/#the-chat-in-the-editor).

## The terminal

On local installs, an admin can turn on the **Terminal** in the **AI** page. It opens Claude Code in the editor, already connected to this Heddle through MCP. See [MCP](/docs/reference/mcp/).

## Language and theme

The menu under your name, at the bottom of the sidebar, opens **Preferences**: the language of the interface, or the one of your browser, and a light, dark or system theme. They are saved with your account, so they follow you to any browser.
