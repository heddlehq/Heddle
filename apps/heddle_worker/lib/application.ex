defmodule HeddleWorker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # The flows a Subflow node waits for, see `HeddleWorker.Subflow`.
      {Task.Supervisor, name: HeddleWorker.TaskSupervisor},
      {Oban, Application.fetch_env!(:heddle_worker, Oban)}
    ]

    opts = [strategy: :one_for_one, name: HeddleWorker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
