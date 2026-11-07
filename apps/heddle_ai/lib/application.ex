defmodule HeddleAI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: HeddleAI.ClaudeAgent.Supervisor, strategy: :one_for_one},
      # The first read of the model registry takes seconds. It shouldn't be on someone's click.
      {Task, fn -> LLMDB.models(:openai) end}
    ]

    opts = [strategy: :one_for_one, name: HeddleAI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
