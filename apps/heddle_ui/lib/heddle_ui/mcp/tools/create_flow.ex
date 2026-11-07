defmodule HeddleUI.MCP.Tools.CreateFlow do
  @moduledoc """
  Creates a flow. Call list_nodes first: each node needs an id, a type from that list,
  and optionally a label and controls. Connections use source, sourceOutput and target.
  Nodes are laid out automatically.
  """

  use Anubis.Server.Component, type: :tool, name: "create_flow"

  alias HeddleCore.Flows
  alias HeddleUI.AIChat
  alias HeddleUI.MCP.Tool
  alias HeddleUI.PublicAPI.V1.WorkflowJSON

  schema do
    field :name, :string, required: true, description: "Flow name"
    field :nodes, {:list, :map}, required: true, description: "Nodes of the flow"
    field :connections, {:list, :map}, description: "Connections between nodes"
  end

  @impl true
  def execute(%{name: name, nodes: nodes} = params, frame) do
    Tool.authorize(frame, "workflows:write", fn scope ->
      attrs = %{
        name: name,
        nodes: AIChat.normalize_nodes(nodes),
        connections: Map.get(params, :connections) || []
      }

      case Flows.create_flow(scope, attrs) do
        {:ok, flow} -> Tool.reply(WorkflowJSON.show(%{workflow: flow}).data, frame)
        {:error, changeset} -> Tool.changeset_error(changeset, frame)
      end
    end)
  end
end
