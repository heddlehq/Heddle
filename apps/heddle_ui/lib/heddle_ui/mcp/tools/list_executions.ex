defmodule HeddleUI.MCP.Tools.ListExecutions do
  @moduledoc "Lists the latest executions of a flow, most recent first."

  use Anubis.Server.Component,
    type: :tool,
    name: "list_executions",
    annotations: %{readOnlyHint: true}

  alias HeddleCore.Executions
  alias HeddleUI.MCP.Tool

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
  end

  @impl true
  def execute(%{flow_id: id}, frame) do
    Tool.authorize(frame, "executions:read", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        flow
        |> Executions.list_executions_for_flow_page(HeddleUI.Pagination.from_params(%{}))
        |> Map.fetch!(:entries)
        |> Enum.map(&summary/1)
        |> then(&Tool.reply(%{executions: &1}, frame))
      end)
    end)
  end

  defp summary(execution) do
    %{
      id: execution.public_id,
      status: execution.status,
      error: execution.error,
      started_at: execution.started_at,
      finished_at: execution.finished_at
    }
  end
end
