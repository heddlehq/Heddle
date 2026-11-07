defmodule HeddleUI.MCP.Tools.UpdateFlow do
  @moduledoc """
  Replaces the name, nodes or connections of a flow. Read it with get_flow first and
  send the complete list of nodes. Every node needs id, type and controls. Keep the
  position of the ones that have one, and a node without it is placed automatically.
  """

  use Anubis.Server.Component, type: :tool, name: "update_flow"

  alias HeddleCore.Flows
  alias HeddleUI.AIChat
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.WorkflowJSON

  schema do
    field :flow_id, :string, required: true, description: "Flow id"
    field :name, :string, description: "New name"
    field :nodes, {:list, :map}, description: "Complete list of nodes"
    field :connections, {:list, :map}, description: "Complete list of connections"
  end

  @impl true
  def execute(%{flow_id: id} = params, frame) do
    Tool.authorize(frame, "workflows:write", fn scope ->
      Tool.with_flow(scope, id, frame, fn flow ->
        case Flows.update_flow(scope, flow, attrs(params)) do
          {:ok, flow} -> Tool.reply(WorkflowJSON.show(%{workflow: flow}).data, frame)
          {:error, changeset} -> Tool.changeset_error(changeset, frame)
        end
      end)
    end)
  end

  defp attrs(params) do
    params
    |> Map.take([:name, :nodes, :connections])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn
      {:nodes, nodes} -> {:nodes, AIChat.persistable_nodes(nodes)}
      other -> other
    end)
  end
end
