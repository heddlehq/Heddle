defmodule HeddleNodes.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Bobbin starts the connections of the database nodes, see Bobbin.Connections.
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: HeddleNodes.Supervisor)
  end
end
