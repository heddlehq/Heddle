defmodule HeddleUI.MCP.Tools.ListNodes do
  @moduledoc "Describes the node types available to build flows."

  use Anubis.Server.Component,
    type: :tool,
    name: "list_nodes",
    annotations: %{readOnlyHint: true}

  alias HeddleAI.Agents.Shared
  alias HeddleUI.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Tool.authorize(frame, "nodes:read", fn _scope ->
      Tool.reply_text(Shared.nodes_description(), frame)
    end)
  end
end
