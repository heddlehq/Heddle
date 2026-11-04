defmodule HeddleCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HeddleCore.Repo,
      {Phoenix.PubSub, name: HeddleCore.PubSub},
      {Task.Supervisor, name: HeddleCore.TaskSupervisor},
      HeddleCore.Webhooks.Registry,
      HeddleCore.Flows.Cache
    ]

    opts = [strategy: :one_for_one, name: HeddleCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
