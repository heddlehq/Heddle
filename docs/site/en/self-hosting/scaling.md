---
title: Scaling
description: Run the UI and the workers apart, and size them for the load.
sidebar:
  order: 1
---

This guide shows how to scale **Heddle** after the umbrella split between UI and worker.

## Runtime model

Heddle now has two operational roles:

- `heddle_ui`: serves Phoenix, LiveView, HTTP and enqueues executions
- `heddle_worker`: consumes Oban jobs and executes flows

That means scaling usually looks like this:

- keep a small number of UI instances
- increase the number of worker instances based on execution volume

For example, if you want **1 server and 5 workers**, you run:

- 1 `ui`
- 5 `worker`
- 1 shared Postgres

## Important constraint

All UI and worker instances must point to the same database because Oban uses Postgres as the job backend.

At minimum, every instance needs:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `HEDDLE_LLM_PROVIDER`, `HEDDLE_LLM_MODEL` and `HEDDLE_LLM_API_KEY` to enable the AI chats (`OPENAI_API_KEY` still works when the provider is unset)
- `HEDDLE_CLAUDE_API_KEY` on the UI instances to use the Claude Agent, which also needs the `claude` binary there: build the image with `--build-arg INSTALL_CLAUDE=true`

## Docker Compose

This is the simplest way to run **1 UI and 5 workers** locally or in a single host environment.

Start the stack:

```bash
docker compose up -d --build db ui
docker compose up -d --scale worker=5 worker
```

You can also do it in one command:

```bash
docker compose up -d --build db ui --scale worker=5 worker
```

Check the containers:

```bash
docker compose ps
```

You should see:

- `db`
- `ui`
- `worker-1`
- `worker-2`
- `worker-3`
- `worker-4`
- `worker-5`

## Docker run

If you are not using Compose, build the image once:

```bash
docker build -t heddle .
```

Run the UI:

```bash
docker run -d --name heddle-ui -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/heddle \
  -v heddle_data:/app/data \
  heddle ui
```

Run 5 workers:

```bash
docker run -d --name heddle-worker-1 \
  --env-file .env \
  -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/heddle \
  heddle worker
```

Repeat for `heddle-worker-2` through `heddle-worker-5`.

The image is the same. What changes is only the container mode:

- `heddle ui`
- `heddle worker`

## Separate releases without Docker

If you deploy directly on VMs or bare metal, build both releases:

```bash
mix release heddle_ui
mix release heddle_worker
```

Then distribute them separately.

On the UI host:

```bash
_build/prod/rel/heddle_ui/bin/heddle_ui start
```

On each worker host:

```bash
_build/prod/rel/heddle_worker/bin/heddle_worker start
```

To reach **1 UI and 5 workers**, you start:

- 1 host or process running `heddle_ui`
- 5 hosts or processes running `heddle_worker`

## Capacity planning

Scaling workers is not only "add more containers". You also need to watch the database and queue concurrency.

Current default worker configuration:

- `WORKER_POOL_SIZE=10`
- Oban queue `executions: 50`
- Oban queue `default: 2`

That means each worker instance can execute up to roughly:

- 50 jobs concurrently in `executions`
- plus up to 2 jobs concurrently in `default`, if that queue is used

So with **5 workers**, the `executions` queue alone can reach about **250 concurrent jobs**.

Most of a run is spent waiting on other services, and a waiting run holds no database connection, so the queue can be much larger than the pool. Lower it if your flows are heavy on CPU or memory, or if the services they call can't take that many calls at once.

Because of that, review these settings before scaling up:

- `POOL_SIZE` for the database
- Postgres connection limits
- CPU and memory available per worker
- runtime dependencies used by each flow

If you scale workers but keep a tiny DB pool, the bottleneck just moves to Postgres.

## Tuning knobs

These are the main environment variables to change when scaling:

- `UI_POOL_SIZE`
- `WORKER_POOL_SIZE`
- `OBAN_EXECUTIONS_CONCURRENCY`
- `OBAN_DEFAULT_CONCURRENCY`

Example for a more conservative worker profile:

```bash
WORKER_POOL_SIZE=2
OBAN_EXECUTIONS_CONCURRENCY=4
OBAN_DEFAULT_CONCURRENCY=1
```

## Recommended production topology

For most deployments:

1. Run UI and worker as separate services
2. Keep Postgres external and persistent
3. Scale workers horizontally first
4. Scale UI only when HTTP or LiveView traffic requires it

Typical examples:

- low traffic: `1 ui`, `1 worker`
- moderate traffic: `1 ui`, `3 workers`
- heavier async load: `2 ui`, `5 workers`

## Operational notes

- Migrations should run once per deploy, not once per worker replica
- UI should be behind a load balancer if you run multiple instances
- Workers do not need port `4000`
- If a worker dies, Oban will recover jobs based on its retry and rescue logic

## Quick recipes

### 1 UI and 5 workers with Compose

```bash
docker compose up -d --build db ui --scale worker=5 worker
```

### 2 UI and 10 workers with Compose

```bash
docker compose up -d --build db --scale ui=2 --scale worker=10 ui worker
```

### Worker-only expansion

If the UI is already running and executions are backing up:

```bash
docker compose up -d --scale worker=8 worker
```
