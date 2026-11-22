# 1. Integrations catalog and declarative manifests

- Status: accepted
- Date: 2026-11-22
- Epic: #84

## Context

Heddle will ship many more integrations. If every one of them is listed in the node sidebar, the sidebar becomes too long to use. We also want the community to build and share integrations, but Heddle ships as a single binary. Loading community Elixir code into the running VM would give that code full access to the instance, and a bug in it could crash the VM.

## Decision

1. **Install per workspace.** The core nodes (triggers, logic, data, HTTP, AI) are always in the sidebar. An integration appears only after it is installed in the workspace, including the official integrations that ship in the binary. The sidebar search also finds integrations that are not installed and offers to install them.
2. **Declarative manifests first.** A community integration is a manifest. It declares a credential (API key, bearer, basic or OAuth 2.0) and a set of HTTP actions, and each action becomes a node with `success` and `error` outputs. Requests are built with Heddle's `{{ }}` templates, a response path selects the output, and pagination uses presets (cursor, offset, Link header). Manifests cannot contain arbitrary code.
3. **Bobbin owns the format.** Bobbin defines the manifest, publishes its JSON Schema, validates manifests and provides `mix bobbin.new`, `mix bobbin.validate` and `mix bobbin.run`. Heddle loads manifests through Bobbin.
4. **A GitHub index repo is the registry.** Integrations live in `heddlehq/integrations` and are added through reviewed PRs. CI validates each manifest and publishes `index.json`.
5. **OAuth 2.0 uses the admin's own app.** The instance admin registers an app with each service and enters its client_id and secret. Heddle stores the tokens encrypted and refreshes them. There is no heddlehq broker.
6. **Versions are pinned.** An installed integration keeps its version until someone updates it. Flows never change on their own.
7. **Official HTTP integrations dogfood the format.** Slack, and later Google Sheets, are rewritten as manifests and keep the same node names. Native drivers (SQL, Redis, Mongo, Cassandra, FTP, S3) stay in Elixir.

## Consequences

- The sidebar stays short, and each workspace sees only what it uses.
- Community integrations run no code inside the VM, so they are safe to offer to any instance, hosted or self-hosted.
- Some integrations cannot be expressed as a manifest, such as complex transforms, binary protocols and custom signing. They wait for native Bobbin nodes, which can be loaded at runtime only by self-hosted instances that opt in.
- Heddle has to become an OAuth 2.0 client, which means storing refresh tokens and refreshing them.
- Self-hosted instances without internet access can use only the official integrations.
