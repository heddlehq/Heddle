import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1
config :heddle_core, Oban, testing: :manual
config :heddle_ui, :webhook_response, timeout: 300, poll: 5
config :heddle_ui, :resume_call, timeout: 300, poll: 5
config :heddle_worker, Oban, testing: :manual
config :heddle_core, :log_email_notifications?, false
config :heddle_core, :async_api_key_touch?, false
config :heddle_runtime, :log_python_execution_errors?, false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :heddle_core, HeddleCore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("HEDDLE_DB_PORT", "5432")),
  database: "heddle_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # A server started here for E2E holds a connection in every editor's session and
  # channel, as the sandbox gives each process its own.
  pool_size: System.schedulers_online() * 4

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :heddle_ui, HeddleUI.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RGDMKwy9wtqfdYXUnhZUPhKjpRZJaZAjQKUtup44jrU3NmYZNqepUEc/l3pEtpP4",
  server: false

config :heddle_ui, HeddleUI.ApiEndpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "RGDMKwy9wtqfdYXUnhZUPhKjpRZJaZAjQKUtup44jrU3NmYZNqepUEc/l3pEtpP4",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :heddle_ai, :text_default, nil
config :heddle_ai, :claude_binary, nil
config :heddle_nodes, :req_plug, {Req.Test, HeddleNodes.Nodes.HttpRequest}

# A flow session goes soon after its last editor leaves, so it doesn't keep a connection.
config :heddle_core, session_idle_after: 2_000
