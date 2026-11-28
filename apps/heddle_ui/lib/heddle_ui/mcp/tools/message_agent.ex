defmodule HeddleUI.MCP.Tools.MessageAgent do
  @moduledoc """
  Sends a message to an agent, by its name, and waits up to a minute for its reply.
  This runs its published flow, which can have real side effects. Each API key talks
  in a conversation of its own, unless `conversation` names another, which is the
  agent's instance key.
  """

  use Anubis.Server.Component,
    type: :tool,
    name: "message_agent",
    annotations: %{destructiveHint: true, openWorldHint: true}

  alias HeddleUI.ChatTriggers
  alias HeddleUI.MCP.Tool

  @timeout to_timeout(minute: 1)

  schema do
    field :name, :string, required: true, description: "The agent's name"
    field :message, :string, required: true, description: "What to say"
    field :conversation, :string, description: "The conversation to talk in"
  end

  @impl true
  def execute(%{name: name, message: message} = params, frame) do
    Tool.authorize(frame, "executions:write", fn scope ->
      conversation =
        case params[:conversation] do
          text when is_binary(text) and text != "" -> text
          _none -> "mcp:#{frame.assigns.api_key.id}"
        end

      with {:ok, entry} <- ChatTriggers.find(scope, name),
           {:ok, reply} <- ChatTriggers.message(entry, conversation, message, @timeout) do
        Tool.reply(
          %{
            agent: entry.name,
            conversation: conversation,
            reply: reply,
            answered: not is_nil(reply)
          },
          frame
        )
      else
        {:error, message} -> Tool.error(message, frame)
      end
    end)
  end
end
