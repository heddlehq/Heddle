defmodule HeddleUI.MCP.Tools.TestFlow do
  @moduledoc """
  Runs the draft of a flow, as it is saved now, and waits for it, returning its status, error, the
  context it ended with, what it answered and the steps it took. Use it to check a
  change really works. For a flow that starts at a Webhook node, send webhook with the
  body of the request, as if it had been called. Otherwise, the fields of input become
  variables of the run. With section_id, it runs only that section of the flow, the id
  of a comment of kind section. It has real side effects, so the user may be asked first.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "test_flow",
    annotations: %{destructiveHint: true, openWorldHint: true}

  alias HeddleCore.Executions
  alias HeddleUI.AgentChat
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.ExecutionJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :input, :map, description: "Input of the run"

    field :webhook, :map,
      description: "The request to simulate: body, and optionally method, query_params, headers"

    field :section_id, :string, description: "Run only this section of the flow"
  end

  @impl true
  def execute(%{flow_id: id} = params, frame) do
    Tool.authorize(frame, "executions:write", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        with :ok <- AgentChat.confirm_run(frame.assigns.api_key, flow),
             input = Tool.put_section(input(params), params),
             {:ok, execution} <- Executions.run_and_await(scope, flow, input, version: :draft) do
          Tool.reply(ExecutionJSON.for_agent(%{execution: execution}).data, frame)
        else
          {:error, :forbidden} -> Tool.forbidden(frame)
          {:error, :timeout} -> Tool.error("The flow is still running after 2 minutes.", frame)
          {:error, message} when is_binary(message) -> Tool.error(message, frame)
          {:error, _reason} -> Tool.error("The flow could not be started.", frame)
        end
      end)
    end)
  end

  defp input(%{webhook: webhook}) when is_map(webhook) do
    webhook
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Executions.webhook_input()
  end

  defp input(params) do
    params |> Map.get(:input) |> Kernel.||(%{}) |> Map.put_new("trigger", "test")
  end
end
