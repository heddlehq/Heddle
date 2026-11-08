defmodule HeddleUI.MCP.Tools.GetFlow do
  @moduledoc """
  Returns a flow with its nodes, connections and comments. A comment of kind section
  groups the nodes in its `nodes`, and with `manual` they don't run with the flow.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "get_flow",
    annotations: %{readOnlyHint: true}

  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.WorkflowJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
  end

  @impl true
  def execute(%{flow_id: id}, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        Tool.reply(WorkflowJSON.show(%{workflow: flow}).data, frame)
      end)
    end)
  end
end
