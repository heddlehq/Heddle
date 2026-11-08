defmodule HeddleCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HeddleCore.Repo,
      {Ecto.Migrator, repos: [HeddleCore.Repo], skip: !migrate_on_boot?()},
      {Phoenix.PubSub, name: HeddleCore.PubSub},
      {Task.Supervisor, name: HeddleCore.TaskSupervisor},
      HeddleCore.Webhooks.Registry,
      HeddleCore.Flows.Cache,
      # One editing session per flow in the whole cluster, see `HeddleCore.Flows.Session`.
      {Horde.Registry, name: HeddleCore.Flows.SessionRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: HeddleCore.Flows.SessionSupervisor, strategy: :one_for_one, members: :auto}
    ]

    opts = [strategy: :one_for_one, name: HeddleCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Docker migrates from its entrypoint. The installed release has no such step.
  defp migrate_on_boot?, do: Application.get_env(:heddle_core, :migrate_on_boot, false)
end
