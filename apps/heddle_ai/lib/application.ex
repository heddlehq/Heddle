defmodule HeddleAI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: HeddleAI.ClaudeAgent.Supervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: HeddleAI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
