defmodule HeddleUI.MCP.Tools.ReadAgent do
  @moduledoc """
  Reads an agent by its name: its instances, with what each keeps (its state), how
  many messages it handled, and what it has scheduled.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "read_agent",
    annotations: %{readOnlyHint: true}

  alias HeddleUI.ChatTriggers
  alias HeddleUI.MCP.Tool

  schema do
    field :name, :string, required: true, description: "The agent's name, as list_agents gives it"
  end

  @impl true
  def execute(%{name: name}, frame) do
    Tool.authorize(frame, "workflows:read", fn scope ->
      case ChatTriggers.find(scope, name) do
        {:ok, entry} ->
          Tool.reply(
            %{
              name: entry.name,
              flow_id: entry.flow_id,
              panel: ChatTriggers.panel(entry)
            },
            frame
          )

        {:error, message} ->
          Tool.error(message, frame)
      end
    end)
  end
end
