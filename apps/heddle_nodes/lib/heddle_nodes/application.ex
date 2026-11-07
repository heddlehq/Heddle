defmodule HeddleNodes.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: HeddleNodes.Connections.Registry},
      {DynamicSupervisor, name: HeddleNodes.Connections.Supervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: HeddleNodes.Supervisor)
  end
end
