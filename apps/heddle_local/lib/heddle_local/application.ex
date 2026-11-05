defmodule HeddleLocal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:heddle_local, :enabled, false), do: [HeddleLocal.Server], else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: HeddleLocal.Supervisor)
  end
end
