defmodule HeddleUI.MCP.Tools.RunFlow do
  @moduledoc """
  Runs the saved version of a flow. This can have real side effects, such as calling
  external APIs. Returns the execution id: read the outcome with get_execution.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "run_flow",
    annotations: %{destructiveHint: true, openWorldHint: true}

  alias HeddleCore.Executions
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.ExecutionJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :input, :map, description: "Input payload"
  end

  @impl true
  def execute(%{flow_id: id} = params, frame) do
    Tool.authorize(frame, "executions:write", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        input = params |> Map.get(:input) |> Kernel.||(%{}) |> Map.put_new("trigger", "mcp")

        case Executions.start_execution(flow, input) do
          {:ok, execution} -> Tool.reply(ExecutionJSON.show(%{execution: execution}).data, frame)
          {:error, _reason} -> Tool.error("The flow could not be started.", frame)
        end
      end)
    end)
  end
end
