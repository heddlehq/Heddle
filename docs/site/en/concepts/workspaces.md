---
title: Workspaces and roles
description: Where a team keeps its flows, and what each role can do.
sidebar:
  order: 5
---

A workspace is where a team keeps its flows, their runs, credentials and API keys. Nobody outside it sees any of them. The first admin starts in one called **Default**, and every install made before workspaces existed has its flows there.

## Roles

People join a workspace with a role. Each role can do everything the one above it in this table can.

| Role     | What they can do                                                        |
|----------|-------------------------------------------------------------------------|
| Viewer   | See the flows, their runs, the names of the credentials and the members |
| Operator | Also run flows, as they were saved                                      |
| Editor   | Also create, change, delete and publish flows, change credentials, and use the agent |
| Admin    | Also add people, change roles, send invites and rename the workspace    |

A workspace always keeps at least one admin.

**System admins** run the instance. They are admins in every workspace, and they alone create and delete workspaces, manage users, set up the AI page and the Terminal, and share credentials with every workspace.

## Bringing people in

Open **Members** in the sidebar:

- **Add someone** who already has an account, by email or username.
- **Invite by link** someone new. The link creates their account and brings them in with the role you picked. It works once, for 7 days.

## Credentials

A credential belongs to its workspace, and only its flows can use it. Two workspaces can each have a credential with the same name.

A system admin can also **share a credential with every workspace**, such as the company's AI provider key. A flow first looks for the name in its own workspace, then among the shared ones. The defaults of the AI page use shared credentials, since they are for the whole instance.

## API keys and apps

An API key belongs to you and to the workspace you made it in. It reaches only that workspace, and never does more than your role there allows: if your role goes down, so does the key, and if you leave, it stops working. Workspace admins see and revoke every key in their workspace.

When an app such as Treadle signs in through the browser, you pick the workspace it gets.
