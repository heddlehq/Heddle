# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :heddle_ui, :scopes,
  user: [
    default: true,
    module: HeddleCore.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: HeddleCore.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :heddle_worker, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 2, executions: 50],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", HeddleWorker.ScheduleWorker},
       {"17 3 * * *", HeddleWorker.VersionPruneWorker}
     ]}
  ],
  repo: HeddleCore.Repo

config :heddle_core, Oban,
  engine: Oban.Engines.Basic,
  name: HeddleCore.Oban,
  notifier: Oban.Notifiers.Postgres,
  queues: [],
  repo: HeddleCore.Repo

config :heddle_core, :oban_name, HeddleCore.Oban

config :heddle_nodes, :llm_client, HeddleAI.AI
config :heddle_nodes, :agent_memory, HeddleCore.AgentMemory
config :heddle_nodes, :credentials_client, HeddleCore.Credentials

# Replaced in production by a key derived from SECRET_KEY_BASE. See runtime.exs.
config :heddle_core, :credentials_secret, "development only"

# Env is read by HeddleAI.LLM. A stray .env must not change what the app talks to.
config :req_llm, load_dotenv: false

config :heddle_core,
  ecto_repos: [HeddleCore.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :heddle_ui, HeddleUI.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HeddleUI.ErrorHTML, json: HeddleUI.ErrorJSON],
    layout: false
  ],
  pubsub_server: HeddleCore.PubSub,
  live_view: [signing_salt: "41Etxq0i"]

config :heddle_ui, HeddleUI.ApiEndpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: HeddleUI.ErrorJSON],
    layout: false
  ],
  pubsub_server: HeddleCore.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  heddle_ui: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/heddle_ui/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  heddle_ui: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/heddle_ui/assets", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, [
  "password",
  "secret",
  "token",
  "authorization",
  "x-heddle-api-key"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
