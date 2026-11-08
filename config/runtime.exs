import Config

env_int = fn name, default ->
  case System.get_env(name) do
    nil -> default
    value -> String.to_integer(value)
  end
end

release_name = System.get_env("RELEASE_NAME")
local_install? = release_name == "heddle"

# The installed release brings its own database and stands in for the variables
# an operator would set, so this comes before anything that reads them.
if local_install? do
  System.put_env(HeddleLocal.boot())

  config :heddle_local, enabled: true
  config :heddle_ui, terminal: true
  config :heddle_core, migrate_on_boot: true
end

runtime_role =
  case release_name do
    "heddle" -> :all
    "heddle_ui" -> :ui
    "heddle_worker" -> :worker
    _ -> if(System.get_env("PHX_SERVER"), do: :ui, else: :worker)
  end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/heddle start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :heddle_ui, HeddleUI.Endpoint, server: true
  config :heddle_ui, HeddleUI.ApiEndpoint, server: true
end

config :heddle_ui, HeddleUI.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :heddle_ui, HeddleUI.ApiEndpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  pool_size =
    case runtime_role do
      :ui -> env_int.("UI_POOL_SIZE", env_int.("POOL_SIZE", 10))
      :worker -> env_int.("WORKER_POOL_SIZE", env_int.("POOL_SIZE", 10))
      :all -> env_int.("POOL_SIZE", 20)
    end

  config :heddle_core, HeddleCore.Repo,
    # ssl: true,
    url: database_url,
    pool_size: pool_size,
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  if runtime_role in [:worker, :all] do
    config :heddle_worker, Oban,
      engine: Oban.Engines.Basic,
      notifier: Oban.Notifiers.Postgres,
      queues: [
        default: env_int.("OBAN_DEFAULT_CONCURRENCY", 2),
        executions: env_int.("OBAN_EXECUTIONS_CONCURRENCY", 50)
      ],
      # A worker that dies leaves its jobs marked as executing forever. Without this,
      # those runs stay "running" and never finish.
      plugins: [
        {Oban.Plugins.Lifeline,
         rescue_after: :timer.minutes(env_int.("OBAN_RESCUE_AFTER_MINUTES", 60))},
        {Oban.Plugins.Cron, crontab: [{"* * * * *", HeddleWorker.ScheduleWorker}]}
      ],
      repo: HeddleCore.Repo
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :heddle_core, :credentials_secret, secret_key_base

  # PHX_HOST is the public domain of a deployment behind TLS, and turns on the
  # HTTPS redirect and the strict origin check. Without it Heddle answers plain
  # HTTP on whatever address it was reached at, so a fresh install works the same
  # on localhost, a LAN IP or a bare server IP.
  host = System.get_env("PHX_HOST", "")
  public_host? = host not in ["", "localhost", "127.0.0.1"]
  port = String.to_integer(System.get_env("PORT", "4000"))

  url =
    if public_host?,
      do: [host: host, port: 443, scheme: "https"],
      else: [host: "localhost", port: port, scheme: "http"]

  # Flows run code with the rights of whoever installed Heddle, so an install on a
  # personal machine must not be reachable from the network.
  listen_ip = if local_install?, do: {127, 0, 0, 1}, else: {0, 0, 0, 0, 0, 0, 0, 0}

  # Where a Wait's address points, for the workers that build it.
  config :heddle_core,
         :public_url,
         if(public_host?, do: "https://#{host}", else: "http://localhost:#{port}")

  config :heddle_ui, :force_ssl, public_host?
  config :heddle_ui, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :heddle_ui, HeddleUI.Endpoint,
    url: url,
    check_origin: if(public_host?, do: true, else: :conn),
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: listen_ip
    ],
    secret_key_base: secret_key_base

  config :heddle_ui, HeddleUI.ApiEndpoint,
    url: url,
    http: [
      ip: listen_ip
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :heddle_ui, HeddleUI.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :heddle_ui, HeddleUI.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
