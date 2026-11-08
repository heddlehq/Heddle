defmodule HeddleUI.MCP.Tools.GetExecution do
  @moduledoc "Returns an execution with its input, result, error and logs."

  use Anubis.Server.Component,
    type: :tool,
    name: "get_execution",
    annotations: %{readOnlyHint: true}

  alias HeddleCore.Executions
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.ExecutionJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :execution_id, :string, required: true, description: "Execution id"
  end

  @impl true
  def execute(%{flow_id: id, execution_id: public_id}, frame) do
    Tool.authorize(frame, "executions:read", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        case Executions.get_execution_by_flow_and_public_id(flow.id, public_id) do
          nil -> Tool.error("Execution #{public_id} was not found.", frame)
          execution -> Tool.reply(ExecutionJSON.for_agent(%{execution: execution}).data, frame)
        end
      end)
    end)
  end
end
