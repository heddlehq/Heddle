defmodule HeddleUI.MCP.Tools.RunFlow do
  @moduledoc """
  Runs the saved version of a flow. This can have real side effects, such as calling
  external APIs, so the user may be asked to confirm first. Returns the execution id:
  read the outcome with get_execution.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "run_flow",
    annotations: %{destructiveHint: true, openWorldHint: true}

  alias HeddleCore.Executions
  alias HeddleUI.AgentChat
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

        with :ok <- AgentChat.confirm_run(frame.assigns.api_key, flow),
             {:ok, execution} <- Executions.run(scope, flow, input) do
          Tool.reply(ExecutionJSON.show(%{execution: execution}).data, frame)
        else
          {:error, :forbidden} -> Tool.forbidden(frame)
          {:error, message} when is_binary(message) -> Tool.error(message, frame)
          {:error, _reason} -> Tool.error("The flow could not be started.", frame)
        end
      end)
    end)
  end
end
