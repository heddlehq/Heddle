---
title: Integrations
description: Install the services a workspace's flows can reach, or write your own integration as a manifest.
sidebar:
  order: 2
---

The **Integrations** page lists the services a workspace can reach. The editor's node sidebar shows only the ones installed in the workspace.

- **Official** integrations are kept by Heddle and come with it.
- **Community** integrations come from the [catalog](https://github.com/heddlehq/integrations). Heddle doesn't review them, and their nodes send what they get to their service, so only workspace admins install them.
- Removing an integration takes its nodes out of the sidebar. A flow that still uses one keeps it installed.

## Create an integration

A workspace admin can write one in **Create integration**. An integration is a manifest in YAML: the service's address, its credential and its actions as HTTP requests. Each action becomes a node, with a `success` and an `error` output.

```yaml
id: acme_crm
name: Acme CRM
version: 1.0.0
base_url: https://api.acme.example/v1/
credential:
  fields:
    - name: api_key
      label: API key
      secret: true
  auth:
    type: bearer
    token: "{{credential.api_key}}"
actions:
  - name: Get Contact
    fields:
      - name: id
        label: Contact ID
    request:
      method: GET
      path: "contacts/{{fields.id}}"
```

The page checks the manifest as you write and shows what to fix. **Create and install** installs it in the workspace, as a community integration of the instance, so other workspaces can install it too.

- The `id` can't be taken by another integration, and its nodes can't take the name of official ones.
- What a manifest can hold (pagination, triggers, OAuth2) is in [Bobbin's README](https://github.com/heddlehq/Bobbin#integrations-without-code). To share it, open a pull request in [heddlehq/integrations](https://github.com/heddlehq/integrations).
