defmodule HeddleAI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: HeddleAI.Finch}
    ]

    opts = [strategy: :one_for_one, name: HeddleAI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
