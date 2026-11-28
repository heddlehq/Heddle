defmodule HeddleUI.MCP.Tools.ListAgents do
  @moduledoc """
  Lists the agents of the workspace: the published flows that begin at an Agent
  trigger, which keep their state between messages. Talk to one with message_agent,
  and see its instances with read_agent.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "list_agents",
    annotations: %{readOnlyHint: true}

  alias HeddleUI.ChatTriggers
  alias HeddleUI.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      agents =
        scope
        |> ChatTriggers.list()
        |> Enum.map(&Map.take(&1, [:name, :flow_id, :flow_name, :node_id, :type]))

      Tool.reply(%{agents: agents}, frame)
    end)
  end
end
