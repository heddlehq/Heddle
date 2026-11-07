defmodule HeddleUI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    endpoint = HeddleUI.Mode.endpoint()

    children = [
      HeddleUI.Telemetry,
      {DNSCluster, query: Application.get_env(:heddle_ui, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:heddle_core, Oban)},
      {Registry, keys: :unique, name: HeddleUI.AgentChat.registry()},
      {Registry, keys: :unique, name: HeddleUI.Agent.registry()},
      {DynamicSupervisor, name: HeddleUI.Agent.supervisor(), strategy: :one_for_one},
      {Task.Supervisor, name: HeddleUI.Agent.task_supervisor()},
      {HeddleUI.MCP.Server,
       transport: {:streamable_http, start: true},
       request_timeout: HeddleUI.MCP.Server.request_timeout()},
      endpoint
    ]

    opts = [strategy: :one_for_one, name: HeddleUI.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HeddleUI.Mode.endpoint().config_change(changed, removed)
    :ok
  end
end
