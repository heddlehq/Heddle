defmodule HeddleUI.MCP.Tools.ListFlows do
  @moduledoc "Lists the flows you can access, with their id and name."

  use Anubis.Server.Component,
    type: :tool,
    name: "list_flows",
    annotations: %{readOnlyHint: true}

  alias HeddleCore.Flows
  alias HeddleUI.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      scope
      |> Flows.list_flows()
      |> Enum.map(&Map.take(&1, [:id, :name, :updated_at]))
      |> then(&Tool.reply(%{flows: &1}, frame))
    end)
  end
end
