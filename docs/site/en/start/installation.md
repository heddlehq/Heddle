---
title: Installation
description: Install Heddle on your computer with one command, on a server with Docker, or from source.
sidebar:
  order: 2
---

This guide will help you get **Heddle** up and running.

## One-line install

This is the easiest way to try Heddle on your own computer. It needs nothing else: Postgres and everything Heddle runs on come in the download.

On Linux and macOS (Apple Silicon):
```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | sh
```

On Windows 10 or later, in PowerShell:
```powershell
irm https://heddlehq.github.io/website/install.ps1 | iex
```

The installer then asks what you want. **Quick install** only asks whether you also want Treadle and which AI to use, and **Customize everything** goes through the folder, version, port, performance and how it starts. Your AI key is checked with the provider before anything is installed, and nothing changes on your computer until you confirm.

Heddle then starts and opens in your browser, where you create the admin account.

- **Where it lives:** `~/.heddle`, or `%LOCALAPPDATA%\Heddle` on Windows. If your Windows user folder has an accent in its name, it's `%ProgramData%\Heddle` instead, because Postgres and Python can't load from one. Your data is in the `data` folder inside it, and your settings in `heddle.env`.
- **Folders with accents:** on Linux and macOS, a home folder like `/home/joão` needs `HEDDLE_HOME` set to a folder without accents.
- **Network access:** this install answers on your computer only. Flows can run code with your account's permissions, so run only the ones you trust.
- **Python:** the first start downloads Python, which needs an internet connection.

This install is for one person on one computer. For a server, or to share Heddle with a team, choose Docker in the installer, or see [Docker](#installation-docker) below. As root or on Linux with musl, like Alpine, Docker is the option the installer offers.

### Installing only Treadle

[Treadle](https://github.com/heddlehq/Treadle) is the terminal editor. To install only it, on a machine that connects to a Heddle running elsewhere:

```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | sh -s -- --treadle
```

```powershell
& ([scriptblock]::Create((irm https://heddlehq.github.io/website/install.ps1))) --treadle
```

It asks for the server and an API key, checks them, and Treadle opens already connected. Leave them empty to sign in with your browser when you open it.

### Installing with no questions

With no terminal, or with `--yes`, nothing is asked and what wasn't passed takes its default. Every question has an option, and `heddle install --help` lists them:

```bash
curl -fsSL https://heddlehq.github.io/website/install.sh | \
  HEDDLE_LLM_API_KEY=sk-ant-... sh -s -- --yes --with-treadle --port 4100 \
  --llm-provider anthropic --llm-model claude-sonnet-5-5
```

Prefer the `HEDDLE_LLM_API_KEY` variable to `--llm-key`, which shows in the process list.

### The `heddle` command

| Command | What it does |
| --- | --- |
| `heddle` or `heddle start` | Starts Heddle in this terminal. `Ctrl+C` stops it. |
| `heddle start -d` | Starts it in the background. |
| `heddle stop` | Stops Heddle and its database, wherever it was started. |
| `heddle restart` | Stops and starts again, in the background. |
| `heddle status` | Shows what's running and how it's set up. Takes `--json`. |
| `heddle logs -f` | Follows the logs. `--db` shows the database's. |
| `heddle open` | Opens Heddle in the browser. |
| `heddle setup` | Changes the AI, step by step. |
| `heddle config` | Lists the settings. `set`, `get` and `unset` change them. |
| `heddle autostart on` | Starts Heddle with the computer. Needs systemd. |
| `heddle doctor` | Checks that everything is in order, your AI key included. |
| `heddle update` | Updates Heddle, Treadle and this command. `--check` only looks. |
| `heddle backup` | Copies your data. `list` shows the copies, `restore` puts one back. |
| `heddle uninstall` | Removes Heddle. `--keep-data` keeps your data. |

- **Updating:** `heddle update`, or run the install command again. Your data stays, and a copy goes to the `backups` folder first, keeping the latest three. If a new version needs a Postgres your data can't use, it stops without changing anything.
- **Backing up:** `heddle backup` stops Heddle for the copy and starts it again after. `heddle backup restore` moves your current data aside instead of deleting it.
- **Settings:** `heddle config set` takes anything in [`.env.example`](https://github.com/heddlehq/Heddle/blob/main/.env.example). Restart for a change to apply.

---

## Prerequisites for running from source

Before you begin, ensure you have the following installed:

- **Elixir** ~> 1.15
- **Erlang/OTP** 26+
- **PostgreSQL**
- **Node.js** (for assets)

---

## Installation (Source)

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

## Installation (Docker)

Running with Docker is the fastest way to get started without worrying about local dependencies.

### 1. Start Heddle
```bash
git clone https://github.com/heddlehq/heddle.git
cd heddle
docker compose up -d --build
```

This starts the UI, a worker and Postgres. The first build takes a few minutes.

### 2. Create your admin account
Visit [`localhost:4000`](http://localhost:4000). The first visit asks you to create the admin account, which starts in a workspace called Default. To bring your team in, see [Workspaces and roles](/docs/concepts/workspaces/).

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
- `WORKER_POOL_SIZE=10`
- `OBAN_EXECUTIONS_CONCURRENCY=50`
- `OBAN_DEFAULT_CONCURRENCY=2`
- `OBAN_RESCUE_AFTER_MINUTES=60`

Increase worker replicas carefully and tune these values together with your Postgres limits.

`OBAN_RESCUE_AFTER_MINUTES` is how long a run can go on before Heddle assumes its worker died and starts it again from the beginning. Keep it longer than your longest flow, or a flow that is still running gets started twice.

### 7. Credentials

The **Credentials** page stores what nodes like Slack, S3 and FTP need to reach other services. Values are encrypted with a key derived from `SECRET_KEY_BASE`, and flows only keep the credential's name.

The nodes of the **Database** category take a credential of their database, and [Database nodes](/docs/guides/databases/) explains them.

Sending email takes an **Email (SMTP)** credential, and reading a mailbox takes an **Email (IMAP)** one. IMAP only connects over TLS, usually on port 993.

The **AI** page sets what each AI task uses by default: text and chat, reading images, creating images, transcribing audio and text to speech. Each one takes an **AI provider** credential and a model. A node can override them, and the models offered are only the ones that can do the task. Generating images with Nano Banana takes a Google credential, with a key from Google AI Studio. Transcribing audio and text to speech take an OpenAI one. Without any of this, text tasks use the `HEDDLE_LLM_*` variables.

The UI and the workers must share that secret. If it changes, every credential stops working and has to be entered again, so back it up with your data.

### 8. API-only UI mode

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

## Verification

To ensure everything is working correctly, you can run the test suite:
```bash
mix test
```

For multi-instance deployment and worker scaling, see [Scaling](/docs/self-hosting/scaling/).
