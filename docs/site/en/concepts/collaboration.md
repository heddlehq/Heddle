---
title: Editing together
description: Several people, and the AI, on the same flow at once, with live cursors, autosave and an undo that is yours alone.
sidebar:
  order: 4
---

A flow can be open in many browsers at once, and everyone works on the same canvas. There is nothing to merge and no save button.

## What you see of the others

- **Avatars** at the top: who else has the flow open. Your own isn't shown.
- **Cursors** with their names, where they point on the canvas.
- **Rings** in their color around the nodes they selected, and a mark on the one whose drawer they have open.
- **Drags** as they happen: a node someone moves slides on your screen too.

Click an avatar to **follow** that person: your view goes where their cursor goes, until you move the canvas yourself or click again.

## How changes meet

Every change goes to one process on the server for that flow, which puts them in order and sends them to everyone. Two people can change different nodes, or different fields of one node, at the same time, and both changes stay. When two people change the same field, the last one wins.

In the node drawer, a field someone else changes updates in front of you, except the one you are typing in. The code editor tells you when someone changed the code after you opened it, and lets you load theirs or keep yours.

## Saving

Changes are saved a moment after they are made, and **Saving...** shows next to the flow's name until they are. If the connection drops, it says **Reconnecting...**, and what you did meanwhile is sent when it comes back. A run, or a publish, always saves first.

## Undo

**Ctrl+Z** takes back your own last change, never someone else's. If someone changed the same thing after you, undoing puts back what you had, over theirs.

## In the terminal

[Treadle](https://github.com/heddlehq/Treadle), the terminal editor, edits the same flow live. Whoever has it open there shows up like anyone else: an avatar, rings on the nodes they selected, and a cursor on the one they are on. They see you too, with your cursor. Anything else that edits through the API can do the same, see [Editing together](/docs/reference/api/) in the API.

## The AI on the canvas

When the AI chat edits a flow, it shows among the avatars while it works, and the nodes it changes flash. Its changes go through the same process as everyone else's, so they never step on what you are doing. The same holds for the API, MCP and imports: what they change shows up on every open canvas.

## Who can edit

Viewers and operators see the canvas and the others on it, but can't change it. Editors and admins can. See [Workspaces and roles](/docs/concepts/workspaces/).
