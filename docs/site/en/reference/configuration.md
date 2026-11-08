---
title: Configuration
description: The environment variables Heddle reads, what each one does and its default.
sidebar:
  order: 4
---

Nothing here is required: Heddle starts with sensible defaults. On a local install, change these with `heddle config set KEY=VALUE` and restart. With Docker, put them in `.env`, next to `docker-compose.yml`. The [`.env.example`](https://github.com/heddlehq/Heddle/blob/main/.env.example) has them all.

## Server

| Variable | Default | What it does |
| --- | --- | --- |
| `PORT` | `4000` | The port Heddle listens on. |
| `HEDDLE_PORT` | `4000` | With Docker Compose, the port published on the machine. |
| `PHX_HOST` | | Your public domain, only behind HTTPS. Turns on the redirect to HTTPS, so the proxy must send `X-Forwarded-Proto`. |
| `SECRET_KEY_BASE` | Generated | Signs sessions and encrypts credentials. Keep it, back it up, and give every UI and worker the same one: changing it loses every credential. |
| `DATABASE_URL` | | The Postgres to use, like `ecto://user:pass@host/heddle`. |
| `HEDDLE_UI_MODE` | `full` | `api` serves only the API and webhooks, without the editor. |
| `HEDDLE_HOME` | `~/.heddle` | Where a local install lives. Set it when your home folder has accents. |
| `HEDDLE_NO_BROWSER` | | Set it to stop `heddle start` from opening the browser. |

## Database and workers

| Variable | Default | What it does |
| --- | --- | --- |
| `POOL_SIZE` | `20` | Database connections, when the UI and the workers run together. |
| `UI_POOL_SIZE` | `10` | Database connections of the UI. |
| `WORKER_POOL_SIZE` | `10` | Database connections of each worker. |
| `OBAN_EXECUTIONS_CONCURRENCY` | `50` | How many runs one worker runs at once. |
| `OBAN_DEFAULT_CONCURRENCY` | `2` | How many background jobs, like cleanups, one worker runs at once. |
| `OBAN_RESCUE_AFTER_MINUTES` | `60` | How long a run can go on before Heddle assumes its worker died and starts it again. Keep it longer than your longest flow. |
| `DNS_CLUSTER_QUERY` | | A DNS name that lists the other Heddle machines, so they find each other and form a cluster. |

Raise the concurrency and the pools together, within what your Postgres accepts. See [Scaling](/docs/self-hosting/scaling/).

## AI

| Variable | What it does |
| --- | --- |
| `HEDDLE_LLM_PROVIDER` | The provider for text tasks when the AI page sets none: `anthropic`, `openai`, `google` or `xai`. |
| `HEDDLE_LLM_MODEL` | Its model, like `claude-sonnet-5-5`. |
| `HEDDLE_LLM_API_KEY` | Its key. Prefer this to passing it on the command line. |
| `HEDDLE_CLAUDE_API_KEY` | The key of the Claude Agent in the editor chat. Can be empty when the provider is `anthropic`. |
| `HEDDLE_CLAUDE_BIN` | Where the `claude` program is, when it isn't found by itself. |
| `HEDDLE_CLAUDE_MAX_BUDGET_USD` | The most one chat turn of the Claude Agent may spend, `1` by default. |

The **AI** page overrides these per kind of task. See [AI providers](/docs/guides/ai-providers/).
