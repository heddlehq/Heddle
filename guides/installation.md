# Installation Guide

This guide will help you get **Heddle** up and running on your local machine.

## 🛠 Prerequisites

Before you begin, ensure you have the following installed:

- **Elixir** ~> 1.15
- **Erlang/OTP** 26+
- **PostgreSQL**
- **Node.js** (for assets)

---

## 🏗 Installation (Source)

Follow these steps to run Heddle directly from the source code.

### 1. Clone the repository
```bash
git clone https://github.com/heddlehq/heddle.git
cd heddle
```

### 2. Install dependencies and setup
This command will install Elixir dependencies, install the UI JavaScript dependencies in
`apps/heddle_ui/assets` including Rete.js, preferring `npm` and falling back to `bun`,
create the database, and run migrations.
```bash
mix setup
```

### 3. Start UI and worker together
Open two terminals.

In the first terminal:
```bash
cd apps/heddle_ui
mix phx.server
```

In the second terminal:
```bash
cd apps/heddle_worker
mix run --no-halt
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

This is the recommended local setup. The UI can render without the worker, but asynchronous executions and webhooks need the worker running.

### 4. Start only one service
If you need to isolate a process during development:

Start only the UI:
```bash
cd apps/heddle_ui
mix phx.server
```

Start only the worker:
```bash
cd apps/heddle_worker
mix run --no-halt
```

---

## 🐳 Installation (Docker)

Running with Docker is the fastest way to get started without worrying about local dependencies.

### 1. Start Heddle
```bash
git clone https://github.com/heddlehq/heddle.git
cd heddle
docker compose up -d --build
```

This starts the UI, a worker and Postgres. The first build takes a few minutes.

### 2. Create your admin account
Visit [`localhost:4000`](http://localhost:4000). The first visit asks you to create the admin account.

From another machine, use this computer's address, like `http://192.168.1.50:4000`.

### 3. Optional settings
Nothing else is required. To change a default, copy `.env.example` to `.env` and edit it:

- `HEDDLE_PORT` is the port published on this machine, when `4000` is taken.
- `PHX_HOST` is your public domain, only when Heddle sits behind HTTPS. Setting it turns on the redirect to HTTPS, so your proxy must send `X-Forwarded-Proto`.
- `SECRET_KEY_BASE` is generated on the first boot and kept in the `heddle_data` volume.

To run everything in a single service:
```bash
docker compose --profile all up -d --build db all
```

### 4. Run without Compose
Build the image and point it at your own Postgres. `all` is the default mode. Pass `ui` or `worker` to start only one of them.

```bash
docker build -t heddle .

docker run --rm -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://USER:PASS@HOST/heddle \
  heddle
```

Mount a volume on `/app/data`, or set `SECRET_KEY_BASE`, to keep people signed in across restarts.

### 5. Use the database from source
To run `mix phx.server` against the Compose database, publish it on this machine:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db
```

### 6. Concurrency and pool tuning

The default Docker setup now separates the main scaling knobs:

- `UI_POOL_SIZE=10`
- `WORKER_POOL_SIZE=3`
- `OBAN_EXECUTIONS_CONCURRENCY=5`
- `OBAN_DEFAULT_CONCURRENCY=2`

Increase worker replicas carefully and tune these values together with your Postgres limits.

### 7. API-only UI mode

The UI release can run as an HTTP API gateway without the visual interface:

```bash
HEDDLE_UI_MODE=api
```

In this mode Heddle starts the API endpoint only:

- `/api/*` routes stay available
- webhook execution endpoints stay available
- LiveView routes are disabled
- static visual assets are not served
- `/live` is not registered

Docker example:

```bash
docker run --rm -p 4000:4000 \
  --env-file .env \
  -e DATABASE_URL=ecto://USER:PASS@HOST/heddle \
  -e HEDDLE_UI_MODE=api \
  heddle ui
```

---

## 🧪 Verification

To ensure everything is working correctly, you can run the test suite:
```bash
mix test
```

For multi-instance deployment and worker scaling, see [guides/scaling.md](./scaling.md).
